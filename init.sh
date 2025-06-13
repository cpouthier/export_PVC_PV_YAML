


# Variables
NAMESPACE="test-data"
PVC_NAME="my-pvc"
STORAGE_CLASS="zfs"  # Change this if your ZFS storage class has a different name

# Create Namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create PVC
echo "Creating PersistentVolumeClaim: $PVC_NAME with storage class: $STORAGE_CLASS"
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: $STORAGE_CLASS
EOF