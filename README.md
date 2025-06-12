# export_PVC_PV_YAML
## Step 1
Add configmap to select proper storage class given a specified label

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pvc-export-config
  namespace: kasten-io
data:
  storageClassLabel: "zfs=true"
```
