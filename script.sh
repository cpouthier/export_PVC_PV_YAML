#!/bin/bash
# This script exports PVC and PV details based on StorageClass labels defined in a ConfigMap.
NAMESPACE=laurent
CONFIGMAP_NS="kasten-io"
CONFIG_NAME="sc-label"

# Retrieves the label selector from the ConfigMap
SC_LABEL_SELECTOR=$(kubectl get configmap "$CONFIG_NAME" -n "$CONFIGMAP_NS" -o jsonpath='{.data.storageClassLabel}')

# Retrieves storage class names based on the label selector
SC_NAMES=$(kubectl get storageclass -l "$SC_LABEL_SELECTOR" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Retrieves the PVCs list for each identified StorageClass
for SC in $SC_NAMES; do
    PVC_LIST=$(kubectl get pvc -n "$NAMESPACE" -o json | jq -r --arg sc "$SC" '.items[] | select(.spec.storageClassName==$sc) | .metadata.name')

# Retrieves the PVs associated with the PVCs and exports PVC and PV manifests as yaml files
    for PVC in $PVC_LIST; do
        PV_NAME=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
        if [[ -n "$PV_NAME" ]]; then
            kubectl get pvc "$PVC" -n "$NAMESPACE" -o yaml > "pvc-${PVC}.yaml"
            kubectl get pv "$PV_NAME" -o yaml > "pv-${PV_NAME}.yaml"
        fi
    done
 done

# Creates a ConfigMap with the exported PVC and PV manifests
CM_NAME="pvc-pv-export"
kubectl create configmap "$CM_NAME" -n "$NAMESPACE" --from-file=. --dry-run=client -o yaml | kubectl apply -f -