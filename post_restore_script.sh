CM_NAME="pvc-pv-export"
CM_NS="laurent"
kubectl get configmap $CM_NAME -n $CM_NS -o json | jq -r '.data | to_entries[] | .value' | kubectl apply -f -