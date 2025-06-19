#!/bin/bash
# This script exports PVC and PV details based on StorageClass labels defined in a ConfigMap.
# Create the sc-label ConfigMap in the kasten-io namespace with the label selector for your StorageClass. Modify the StorageClass label as needed.
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: sc-label
  namespace: kasten-io
data:
  storageClassLabel: "zfs=true" 
EOF

# Initialize some variables to be modified as per your environment
APP_NAMESPACE=test-data
APP_CM_NAME="cm-pvc-pv"
CONFIGMAP_LABEL_NS="kasten-io"
CONFIGMAP_LABEL_NAME="sc-label"

# Deletes existing ConfigMap in the application namespace if it exists
kubectl delete configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --ignore-not-found

# Retrieves the label selector from the ConfigMap in kasten-io namespace
SC_LABEL_SELECTOR=$(kubectl get configmap "$CONFIGMAP_LABEL_NAME" -n "$CONFIGMAP_LABEL_NS" -o jsonpath='{.data.storageClassLabel}')

# Retrieves all storage class names based on the label selector
SC_NAMES=$(kubectl get storageclass -l "$SC_LABEL_SELECTOR" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Prepare temporary working directory
WORKDIR=$(mktemp -d)


# Loop through each StorageClass and export + clean YAMLs
for SC in $SC_NAMES; do
    PVC_LIST=$(kubectl get pvc -n "$APP_NAMESPACE" -o json | jq -r --arg sc "$SC" '.items[] | select(.spec.storageClassName==$sc) | .metadata.name')

    for PVC in $PVC_LIST; do
        PV_NAME=$(kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o jsonpath='{.spec.volumeName}')
        
        if [[ -n "$PV_NAME" ]]; then
            kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o yaml > "$WORKDIR/pvc-${PVC}.yaml"
            kubectl get pv "$PV_NAME" -o yaml > "$WORKDIR/pv-${PV_NAME}.yaml"
        fi
    done
done

# Clean YAMLs with yq
for file in "$WORKDIR"/*.yaml; do
  kind=$(yq e '.kind' "$file")
  
  if [[ "$kind" == "PersistentVolume" ]]; then
    yq e 'del(.metadata.annotations, .metadata.finalizers, .metadata.managedFields, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .status, .spec.claimRef.uid, .spec.claimRef.resourceVersion)' "$file" -i
  elif [[ "$kind" == "PersistentVolumeClaim" ]]; then
    yq e 'del(.metadata.annotations, .metadata.finalizers, .metadata.managedFields, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .status)' "$file" -i
  fi
done

# Create ConfigMap from cleaned files
kubectl create configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --from-file="$WORKDIR" --dry-run=client -o yaml | kubectl apply -f -
