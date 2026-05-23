# Blueprint: pvc-pv-manifest-export-restore

## 🧩 Use Case

This Kanister blueprint enables the **backup and restoration of PersistentVolumeClaim (PVC)** and **PersistentVolume (PV)** manifests only via ConfigMaps when storage is based on NFS and when the NFS storage does not need backup (done in another way). It is designed to work with Veeam Kasten and can be used to preserve Kubernetes storage object definitions during application backup and restore operations.

> ⚠️ **WARNING**  
> The provided blueprint is **not supported by the editor** and is supplied *as-is*.  
> Functionality, compatibility, and correctness are **not guaranteed**.  
> Please **verify and adjust** as needed **before use**.


---

## 🛠️ Actions defined in the blueprint

### `preSnapshot`

Executed before a snapshot, this action:
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
- The storage class to include is (are) identified using a label defined in a ConfigMap in kasten-io namespace. 

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: sc-label
     namespace: kasten-io
   data:
     storageClassLabel: "<your label>"
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
kubectl wait --for=condition=Ready -n test-data pod -l app=basic-app --timeout=60s

# Get pod name
POD_NAME=$(kubectl get pod -n test-data -l app=basic-app -o jsonpath='{.items[0].metadata.name}')

# Create 10 random files in /data
for i in $(seq 1 10); do
  kubectl exec -n test-data "$POD_NAME" -- sh -c "head -c 1024 </dev/urandom > /data/random-file-$i.txt"
done
```

2. **Set up environment and Veeam Kasten**:

Label the NFS storage class (named nfs in the example below) with "nfs=true":

```console
kubectl label storageclass nfs nfs=true
```

Create the configmap in kasten-io namespace with the label selector "nfs=true":

```console
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: sc-label
  namespace: kasten-io
data:
  storageClassLabel: "nfs=true"
EOF
```

Create the blueprint:

```console
kubectl apply -f https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/pvc_pv_manifest_blueprint.yaml
```


3. Create a backup policy

Create the backup policy for the "test-data" namespace where your application is working and exclude the persistent volume claim from the backup:

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/newpolicy.png)

Add a pre-snasphot action hook and select the blueprint and the preSnasphot action:

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/presnapshotaction.png)

Finally click on "Submit" and run the policy.

4. Simulate a crash

Delete the test-data namespace:

```console
kubectl delete ns test-data
```

As the PersistentVolume is not namespaced, you'll need to delete it also otherwise, if it exists, the blueprint will stop to prevent overwrite and the restore action will fail. 

```console
kubectl delete pv nfs-pv
```

5. Restore 

Restoration is done in 2 steps as Veeam Kasten allows granular restore.

- (Step1) First of all select the restore point from which you want to restore.

- Once selected, on the Optional Restore settings, select on "After - On Success", select the blueprint and and the posrRestore action:

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/postrestoreaction.png)

- Restore only the ConfigMap which has been created during backup (deselect all artifacts and select only "cm-pvc-pv" ConfigMap):

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/restoreconfigmap.png)

- Click on "Restore" and Kasten will restore the ConfigMap and then the script will extract PersistantVolume and PersistantVolumeClaim from it and apply them.

- (Step 2) Select again the restore point in Veeam Kasten GUI (should be ideally the one used previously)

- Deselect all artifacts and select only the deployment and click on "Restore":

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/restoredeployment.png)

6. Validate your restore

To validate if the restore has been donne properly, connect to the pod in test-data namespace and check files in /data. You should normally see something like this:

![alt text](https://raw.githubusercontent.com/cpouthier/export_PVC_PV_YAML/main/img/results.png)


---
