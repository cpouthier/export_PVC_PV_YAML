# Blueprint: pvc-pv-manifest-export-restore

This Kanister blueprint enables the **backup and restoration of PersistentVolumeClaim (PVC)** and **PersistentVolume (PV)** manifests via ConfigMaps. It is designed to work with Veeam Kasten and can be used to preserve Kubernetes storage object definitions during application backup and restore operations.

**WARNING**

The provided blueprint **is not supported by the editor and is supplied as-is**. Functionality, compatibility, and correctness are not guaranteed. Please verify and adjust as needed before use.

---

## 🧩 Use Case

This blueprint is intended for scenarios where:
- You need to retain or migrate PVC/PV manifests during a Kasten K10 snapshot-based backup.
- You use dynamic storage classes and want to preserve/restore claims manually.
- Your storage class or CSI driver does not support full-volume restore.

---

## 🛠️ Actions

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

## 🔁 How It Works

1. **Label-based selection**: The storage classes to include are identified using a label defined in this ConfigMap:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: sc-label
     namespace: kasten-io
   data:
     storageClassLabel: "zfs=true"
   ```
   Remember that you'll need to exclude from the bakcup policy PVCs belonging to this storage class.

2. **Export logic**:
   - Extract PVC/PV YAMLs to a temporary directory.
   - Sanitize each manifest using `yq`.
   - Store all cleaned YAMLs as files in a ConfigMap.

3. **Restore logic**:
   - Decode ConfigMap content back into YAML files.
   - Reapply them in order (PVs first, then PVCs).

---

## 🧱 Requirements

- Kubernetes 1.21+
- Access to Image (or you can build your own in your prefered repository): [`cpouthier/blueprint:latest`](https://hub.docker.com/r/cpouthier/blueprint)
  > Includes `bash`, `kubectl`, `jq`, and `yq`

---

## 📂 Cleanup

After restore, the blueprint automatically deletes the intermediate ConfigMap (`cm-pvc-pv`) into the application namespace.
