$AKS_CLUSTER_NAME="aks-test-weu-01"
$AKS_RESOURCE_GROUP="rg-aks-test-weu-02"
$USER_POOL_NAME="userpool1" # up to 12 alphanumeric characters

# Add a user node pool to the cluster
az aks nodepool add --cluster-name $AKS_CLUSTER_NAME --name $USER_POOL_NAME --resource-group $AKS_RESOURCE_GROUP `
                --node-count 1 `
                --node-vm-size standard_d4as_v6 `
                --enable-cluster-autoscaler `
                --min-count 1 `
                --max-count 3 `
                --mode user   