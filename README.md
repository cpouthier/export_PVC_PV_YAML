# WIP
## Step 1
Add configmap in kasten-io namespace to select proper storage class to be used in the blueprint given a specific label.

In this example, we set up the label zfs=true on our StorageClass named "zfs".

`kubectl label storageclass zfs zfs=true --overwrite
`
