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
  storageClassLabel: "nfs=true" 
EOF

#!/bin/bash
set -euo pipefail

clear

# ✅ Configuration
APP_NAMESPACE=test-data
APP_CM_NAME="cm-pvc-pv"
CONFIGMAP_LABEL_NS="kasten-io"
CONFIGMAP_LABEL_NAME="sc-label"
TMP_DIR=$(mktemp -d)

# 🧹 Clean existing ConfigMap
kubectl delete configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --ignore-not-found

# 📥 Retrieve StorageClass label selector
SC_LABEL=$(kubectl get configmap "$CONFIGMAP_LABEL_NAME" -n "$CONFIGMAP_LABEL_NS" -o jsonpath='{.data.storageClassLabel}')
if [ -z "$SC_LABEL" ]; then
  echo "❌ Error: No 'storageClassLabel' found in ConfigMap '$CONFIGMAP_LABEL_NAME' in namespace '$CONFIGMAP_LABEL_NS'."
  exit 1
fi

# 📋 Retrieve list of storage classes matching the label
SC_NAMES=$(kubectl get storageclass -l "$SC_LABEL" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
if [ -z "$SC_NAMES" ]; then
  echo "❌ Error: No StorageClass found matching label selector '$SC_LABEL'."
  exit 1
fi

# 🔁 Loop through each StorageClass and export YAMLs
for SC in $SC_NAMES; do
    echo "🔍 Processing StorageClass: $SC"

    PVC_LIST=$(kubectl get pvc -n "$APP_NAMESPACE" -o json | jq -r --arg sc "$SC" '.items[] | select(.spec.storageClassName==$sc) | .metadata.name')

    if [ -z "$PVC_LIST" ]; then
        echo "❌ Error: No PVCs found in namespace '$APP_NAMESPACE' using StorageClass '$SC'"
        exit 1
    fi

    for PVC in $PVC_LIST; do
        echo "📦 Found PVC: $PVC"
        PV_NAME=$(kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o jsonpath='{.spec.volumeName}')

        if [ -z "$PV_NAME" ]; then
            echo "❌ Error: No bound PV found for PVC '$PVC' in namespace '$APP_NAMESPACE'"
            exit 1
        fi

        echo "📄 Exporting YAML for PVC '$PVC' and PV '$PV_NAME'"
        kubectl get pvc "$PVC" -n "$APP_NAMESPACE" -o yaml > "$TMP_DIR/pvc-${PVC}.yaml"
        kubectl get pv "$PV_NAME" -o yaml > "$TMP_DIR/pv-${PV_NAME}.yaml"
    done
done

# 🧼 Clean YAML files with yq
for file in "$TMP_DIR"/*.yaml; do
  kind=$(yq e '.kind' "$file")
  
  if [[ "$kind" == "PersistentVolume" ]]; then
    yq e 'del(.metadata.annotations, .metadata.finalizers, .metadata.managedFields, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .status, .spec.claimRef.uid, .spec.claimRef.resourceVersion)' "$file" -i
  elif [[ "$kind" == "PersistentVolumeClaim" ]]; then
    yq e 'del(.metadata.annotations, .metadata.finalizers, .metadata.managedFields, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .status)' "$file" -i
  fi
done

# Create ConfigMap from cleaned files
kubectl create configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --from-file="$TMP_DIR" --dry-run=client -o yaml | kubectl apply -f -
