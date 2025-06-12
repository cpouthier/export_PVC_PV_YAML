# WIP
## Step 1
Add configmap in kasten-io namespace to select proper storage class to be used in the blueprint given a specific label

Create the sc-label.yaml below:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sc-label
  namespace: kasten-io
data:
  storageClassLabel: "zfs=true" #Indicates for which storage class you want to use the blueprint given a specific label on the storage class TO BE DEFINED
```
Apply the sc-label.yaml file:

`kubectl apply -k sc-label.yaml`

