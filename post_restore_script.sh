#!/bin/bash
APP_NAMESPACE=test-data
APP_CM_NAME="cm-pvc-pv"
WORKDIR=$(mktemp -d)
# Extract YAMLs from ConfigMap and save them to WORKDIR as individual files
kubectl get configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" -o json \
  | jq -r '.data | to_entries[] | @base64' \
  | while read -r entry; do
      name=$(echo "$entry" | base64 -d | jq -r '.key')
      content=$(echo "$entry" | base64 -d | jq -r '.value')
      echo "$content" > "$WORKDIR/$name"
    done
#!/bin/bash
# Apply PVs (only if they don't already exist)
for pvfile in "$WORKDIR"/pv-*.yaml; do
  PV_NAME=$(yq e '.metadata.name' "$pvfile")
  if kubectl get pv "$PV_NAME" &>/dev/null; then
    echo "PV $PV_NAME already exists. Exiting to prevent overwrite."
    exit 1
  fi
  kubectl apply -f "$pvfile"
done
# Apply PVCs
for pvcfile in "$WORKDIR"/pvc-*.yaml; do
  kubectl apply -f "$pvcfile"
done

# Clean up
kubectl delete configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --ignore-not-found