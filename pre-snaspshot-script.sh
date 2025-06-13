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

# Initialize some variables
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

# Retrieves the PVCs list for each identified StorageClass
for SC in $SC_NAMES; do
    PVC_LIST=$(kubectl get pvc -n "$APP_NAMESPACE" -o json | jq -r --arg sc "$SC" '.items[] | select(.spec.storageClassName==$sc) | .metadata.name')

# Retrieves the PVs associated with the PVCs and exports PV and PVC manifests as yaml files
    for PVC in $PVC_LIST; do
        PV_NAME=$(kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o jsonpath='{.spec.volumeName}')
        if [[ -n "$PV_NAME" ]]; then
            kubectl get pv "$PV_NAME" -o yaml > "pv-${PV_NAME}.yaml"
            kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o yaml > "pvc-${PVC}.yaml"
        fi
    done
 done

# Creates a ConfigMap with the exported PV and PVC manifests
kubectl create configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --from-file=. --dry-run=client -o yaml | kubectl apply -f -