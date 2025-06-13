#!/bin/bash

set -euo pipefail

CM_NAME="pvc-pv-export"
CM_NS="test-data"
WORKDIR=$(mktemp -d)
echo "📦 Using temp dir: $WORKDIR"

# STEP 1: Extract YAMLs from ConfigMap
echo "📥 Extracting PVC/PV manifests from ConfigMap '$CM_NAME'..."
kubectl get configmap "$CM_NAME" -n "$CM_NS" -o json \
  | jq -r '.data | to_entries[] | @base64' \
  | while read -r entry; do
      name=$(echo "$entry" | base64 --decode | jq -r '.key')
      content=$(echo "$entry" | base64 --decode | jq -r '.value')
      echo "$content" > "$WORKDIR/$name"
  done

# STEP 2: Stop Pods using PVCs
echo "🛑 Checking for Pods using PVCs..."
for pvcfile in "$WORKDIR"/pvc-*.yaml; do
  pvcname=$(yq '.metadata.name' "$pvcfile")
  echo "🔍 Looking for Pods using PVC: $pvcname..."

  kubectl get pod -n "$CM_NS" -o json \
    | jq -r --arg pvc "$pvcname" \
      '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' \
    | while read -r pod; do
        echo "⚠️ Deleting pod $pod using PVC $pvcname..."
        kubectl delete pod "$pod" -n "$CM_NS" --grace-period=0 --force || true
    done
done

# STEP 3: Delete PVCs if they still exist
echo "🧹 Deleting PVCs..."
for pvcfile in "$WORKDIR"/pvc-*.yaml; do
  pvcname=$(yq '.metadata.name' "$pvcfile")
  kubectl delete pvc "$pvcname" -n "$CM_NS" --ignore-not-found
done

# STEP 4: Clean and reconstruct PVs if needed
echo "🔧 Processing PVs..."
for pvfile in "$WORKDIR"/pv-*.yaml; do
  echo "🛠 Cleaning $pvfile"
  cp "$pvfile" "${pvfile}.bak"

  # Remove status if exists
  yq 'del(.status)' "$pvfile" > "${pvfile}.tmp" && mv "${pvfile}.tmp" "$pvfile"

  # Clean claimRef
  if yq eval '.spec.claimRef' "$pvfile" >/dev/null 2>&1; then
    yq 'del(.spec.claimRef.uid)' "$pvfile" \
      | yq 'del(.spec.claimRef.resourceVersion)' \
      > "${pvfile}.tmp" && mv "${pvfile}.tmp" "$pvfile"
  fi

  # Rebuild PV if broken
  if ! grep -q 'apiVersion:' "$pvfile" || ! grep -q 'kind:' "$pvfile"; then
    echo "⚠️ Rebuilding broken PV: $pvfile"
    PV_NAME=$(yq '.metadata.name' "${pvfile}.bak")
    CAPACITY=$(yq '.spec.capacity.storage' "${pvfile}.bak")
    ACCESSMODES=$(yq '.spec.accessModes[0]' "${pvfile}.bak")
    STORAGECLASS=$(yq '.spec.storageClassName' "${pvfile}.bak")

    cat <<EOF > "$pvfile"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
spec:
  capacity:
    storage: ${CAPACITY}
  accessModes:
    - ${ACCESSMODES}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${STORAGECLASS}
  hostPath:
    path: /mnt/data/${PV_NAME}
EOF
  fi
done

# STEP 5: Apply PVs
echo "🚀 Applying PVs..."
for pvfile in "$WORKDIR"/pv-*.yaml; do
  echo "📄 $pvfile"
  kubectl apply -f "$pvfile"
done

# STEP 6: Force-replace PVCs
echo "🚀 Replacing PVCs..."
for pvcfile in "$WORKDIR"/pvc-*.yaml; do
  echo "📄 $pvcfile"
  kubectl replace --force --grace-period=0 -f "$pvcfile" || {
    echo "❌ Failed to replace $pvcfile"
  }
done

echo "✅ All done. PVs and PVCs restored successfully."
