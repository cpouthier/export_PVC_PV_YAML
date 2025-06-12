CM_NAME="pvc-pv-export"
CM_NS="my-namespace"
kubectl get configmap $CM_NAME -n $CM_NS -o json | jq -r '.data | to_entries[] | .value' | kubectl apply -f -