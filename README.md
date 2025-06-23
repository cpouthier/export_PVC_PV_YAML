# Blueprint: pvc-pv-manifest-export-restore

This Kanister blueprint enables the **backup and restoration of PersistentVolumeClaim (PVC)** and **PersistentVolume (PV)** manifests via ConfigMaps. It is designed to work with Veeam Kasten and can be used to preserve Kubernetes storage object definitions during application backup and restore operations.

**WARNING**

The provided blueprint **is not supported by the editor and is supplied as-is**. Functionality, compatibility, and correctness are not guaranteed. Please verify and adjust as needed before use.

---

## 🧩 Use Case

This blueprint is intended for scenarios where:
- You need to retain or migrate PVC/PV manifests during a Kasten K10 snapshot-based backup.
- You use dynamic storage classes and want to preserve/restore claims manually.
- Your storage class does not support snapshots and you backup it in another way.

---

## 🛠️ Actions defined in the blueprint

### `preSnapshot`

Executed before a backup, this action:
- Selects PVCs using a label defined in a ConfigMap (`sc-label`) located in the `kasten-io` namespace.
- Exports all matching PVC and PV manifests in the application namespace.
- Sanitizes the manifests (removes metadata such as UIDs, timestamps, managedFields, etc.).
- Stores them in a new ConfigMap named `cm-pvc-pv` in the application namespace.

### `postRestore`

Executed after a successful restore, this action:
- Retrieves the `cm-pvc-pv` ConfigMap.
- Extracts and re-applies all previously saved PVC and PV manifests.
- Deletes the ConfigMap after rehydration to avoid future conflicts.

---

## 🧱 Requirements

- Kubernetes 1.21+
- Access to Image : [`cpouthier/blueprint:latest`](https://hub.docker.com/r/cpouthier/blueprint)
  > Includes `bash`, `kubectl`, `jq`, and `yq`

  > You can also create your own image using https://github.com/cpouthier/light_docker_image_tools
- The storage class to include is (are) identified using a label defined in a ConfigMap in kasten-io namespace. In the example below we labelled the storage class with "zfs=true" and created the corresponding ConfigMap:

```console
kubectl label storageclass <your-storage-class-name> zfs=true
```

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: sc-label
     namespace: kasten-io
   data:
     storageClassLabel: "zfs=true"
   ```
   **Remember that you'll need to exclude from the bakcup policy PVCs belonging to this storage class.**

2. **Export logic**:
   - Extract PVC/PV YAMLs to a temporary directory.
   - Sanitize each manifest using `yq`.
   - Store all cleaned YAMLs as files in a ConfigMap.

3. **Restore logic**:
   - Decode ConfigMap content back into YAML files.
   - Reapply them in order (PVs first, then PVCs).
   - After restore, the blueprint automatically deletes the intermediate ConfigMap (`cm-pvc-pv`) into the application namespace.

---

## 🔁 How to use this blueprint (example)

In the example below we assume you have an NFS storage class exporting on 127.0.0.1

1. **Create a basic application deployment**:

Create the NFS persistent volume:

```console
Create PV
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    path: /data/nfs
    server: 127.0.0.1
EOF
```

Create the "test-data" namespace:

```console
kubectl create namespace test-data --dry-run=client -o yaml | kubectl apply -f -
```

Create the persistent volume claim:

```console
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
  namespace: test-data
spec:
  storageClassName: nfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
EOF
```

Create the basic-app deployment:

```console
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: basic-app
  namespace: test-data
  labels:
    app: basic-app
spec:
  strategy:
    type: Recreate
  replicas: 1
  selector:
    matchLabels:
      app: basic-app
  template:
    metadata:
      labels:
        app: basic-app
    spec:
      containers:
        - name: basic-app-container
          image: alpine:latest
          resources:
            requests:
              memory: 256Mi
              cpu: 100m
          command: ["sh", "-c", "sleep infinity"]
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: nfs-pvc
EOF
```

Wait for pod to be ready and create random files with random data onto the persistant volume claim on /data:

```console
# Wait for the pod to be Ready
echo "⏳ Waiting for pod to be Ready..."
kubectl wait --for=condition=Ready -n test-data pod -l app=basic-app --timeout=60s

# Get pod name
POD_NAME=$(kubectl get pod -n test-data -l app=basic-app -o jsonpath='{.items[0].metadata.name}')

# Create 10 random files in /data
echo "📄 Creating 10 random files in /data on pod $POD_NAME..."
for i in $(seq 1 10); do
  kubectl exec -n test-data "$POD_NAME" -- sh -c "head -c 1024 </dev/urandom > /data/random-file-$i.txt"
done

echo "✅ Done: test-data basic app ready and 10 files created in /data directory which points on a NFS persistent volume."
```

2. **Set up Veeam Kasten**:

Label the NFS storage class with "nfs=true"

Create the configmap in kasten-io namespace with the label selector "nfs=true"

Create the blueprint

3. Create a backup policy

Create the policy
Add blueprint pointing to the pre-snapshot action
Exclude PVC from backup
Run the policy

4. delete test-data namespace
delete NFS PV (if existing the restore policy will fail to avoid overwrite)

5. restore 
2 steps
Restore first only the cm-pvc-pv config map
Restore the deployment

6. Validate restore
connect to the pod in test-data namespace and check files in /data

---
