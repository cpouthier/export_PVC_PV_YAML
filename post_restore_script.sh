#!/bin/bash

set -euo pipefail

APP_NAMESPACE=test-data
APP_CM_NAME="cm-pvc-pv"
WORKDIR=$(mktemp -d)

# Extract YAMLs from ConfigMap
kubectl get configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" -o json \
  | jq -r '.data | to_entries[] | @base64' \
  | while read -r entry; do
      name=$(echo "$entry" | base64 --decode | jq -r '.key')
      content=$(echo "$entry" | base64 --decode | jq -r '.value')
      echo "$content" > "$WORKDIR/$name"
    done

              
for pvfile in "$WORKDIR"/pv-*.yaml; do
  kubectl apply -f "$pvfile"
done

for pvcfile in "$WORKDIR"/pvc-*.yaml; do
  kubectl apply -f "$pvcfile"
done

kubectl delete configmap "$APP_CM_NAME" -n "$APP_NAMESPACE" --ignore-not-found