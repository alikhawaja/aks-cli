$AKS_RESOURCE_GROUP="rg-aks-test-weu-02"
$MANAGED_RESOURCE_GROUP="mg-rg-aks-test-weu-02"
$REGION="westeurope"
$AKS_CLUSTER_NAME="aks-test-weu-03"
$MY_DNS_LABEL="aktestweu03"
#$AAD_TENANT_ID='798ee643-af94-452c-83ba-2299a6353069'  # MSDN Azure AD tenant ID
$AAD_TENANT_ID='5fa993f9-c945-40bd-8d82-cde4f3400956' # MCAPS Azure AD Tenant ID
$AKS_AAD_ADMIN_GROUP_NAME="aks_dev_admins"
$MY_ACR_NAME="acrtestweu02"
$VNET_RESOURCE_GROUP="rg-aks-test-weu-02"
$VNET_NAME="vnet-aks-test-weu-02"
$VNET_ADDRESS_PREFIX="10.10.0.0/16"
$SUBNET_NAME="subnet-aks-test-weu-02"
$SUBNET_ADDRESS_PREFIX="10.10.0.0/22"
$SYSTEM_POOL_NAME="systempool1" # up to 12 alphanumeric characters


# check if resource group exists otherwise create it   
$group_count = az group list --query "[?name=='$AKS_RESOURCE_GROUP'] | length(@)" 
if($group_count -eq 1) {
    echo "Resource group $AKS_RESOURCE_GROUP already exists." }
else {
    echo "Creating resource group $AKS_RESOURCE_GROUP..."
    az group create --name $AKS_RESOURCE_GROUP --location $REGION
}

# retreive vnet if exists, otherwise create a a new virtual network
if((az network vnet list --resource-group $VNET_RESOURCE_GROUP --query "[?name=='$VNET_NAME']| length(@)") -eq 1) {
    echo "VNet $VNET_NAME already exists." }
else {
    echo "Creating VNet $VNET_NAME..."
    az network vnet create --name $VNET_NAME --resource-group $VNET_RESOURCE_GROUP `
        --address-prefix $VNET_ADDRESS_PREFIX `
        --subnet-name $SUBNET_NAME `
        --subnet-prefix $SUBNET_ADDRESS_PREFIX
}

# Retrieve the existing ACR, otherwise create a new Azure Container Registry (ACR)
if((az acr check-name --name $MY_ACR_NAME --query "nameAvailable") -eq "false") {
    echo "ACR $MY_ACR_NAME already exists." }
else {
    echo "Creating ACR $MY_ACR_NAME..."
    az acr create --resource-group $AKS_RESOURCE_GROUP --name $MY_ACR_NAME --sku Premium --admin-enabled true 
}

#check if the ad group already exists otherwise create it
$aad_ak_dev_admin_group = $(az ad group list --query "[?displayName=='$AKS_AAD_ADMIN_GROUP_NAME'].id" -o tsv)
if($aad_ak_dev_admin_group -ne $null) {
    echo "AAD group aks_dev_admins already exists." 
    $aad_ak_dev_admin_group_object_id = $(az ad group show --group aks_dev_admins --query id -o tsv)
    echo "AAD group aks_dev_admins object ID: $aad_ak_dev_admin_group_object_id"
}
else {
    echo "Creating AAD group aks_dev_admins..."
    $aad_ak_dev_admin_group_object_id=$(az ad group create --display-name aks_dev_admins --mail-nickname aks_dev_admins --query id -o tsv)

    echo "AAD group aks_dev_admins created with object ID: $aad_ak_dev_admin_group_object_id"
}


$vnet_subnet_id=$(az network vnet subnet list --resource-group $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME --query "[?name=='$SUBNET_NAME'].id" -o tsv)
if($vnet_subnet_id -eq $null) {
    echo "Subnet $SUBNET_NAME not found in VNet $VNET_NAME."
    exit 1
}
else {
    echo "Subnet $SUBNET_NAME found in VNet $VNET_NAME with ID: $vnet_subnet_id"
}

echo "Creating AKS cluster $AKS_CLUSTER_NAME in resource group $AKS_RESOURCE_GROUP..."
az aks create --resource-group $AKS_RESOURCE_GROUP `
                --name $AKS_CLUSTER_NAME `
                --nodepool-name $SYSTEM_POOL_NAME `
                --node-resource-group $MANAGED_RESOURCE_GROUP `
                --generate-ssh-keys  `
                --enable-managed-identity `
                --disable-local-accounts `
                --enable-azure-rbac `
                --enable-aad --aad-admin-group-object-ids $aad_ak_dev_admin_group_object_id `
                --aad-tenant-id $AAD_TENANT_ID `
                --dns-name-prefix $MY_DNS_LABEL `
                --location $REGION `
                --network-plugin azure `
                --network-policy azure `
                --vnet-subnet-id $vnet_subnet_id `
                --load-balancer-sku standard `
                --enable-cluster-autoscaler `
                --node-count 1 `
                --min-count 1 `
                --max-count 3 `
                --node-vm-size standard_d4as_v6 `
                --attach-acr $MY_ACR_NAME `
                --enable-azure-monitor-metrics  

# sleep until the cluster is ready
$cluster_status = $(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query provisioningState -o tsv)
while ($cluster_status -ne "Succeeded") {
    echo "Waiting for AKS cluster to be ready..."
    Start-Sleep -Seconds 30
    $cluster_status = $(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query provisioningState -o tsv)
}   

# Add a user node pool to the cluster

$USER_POOL_NAME = "userpool1"
echo "Adding user node pool $USER_POOL_NAME to AKS cluster $AKS_CLUSTER_NAME..."
az aks nodepool add --cluster-name $AKS_CLUSTER_NAME --name $USER_POOL_NAME --resource-group $AKS_RESOURCE_GROUP `
                --node-count 1 `
                --node-vm-size standard_d4as_v6 `
                --enable-cluster-autoscaler `
                --os-sku AzureLinux `
                --min-count 1 `
                --max-count 3 `
                --mode user   

echo "Retreiving AKS credentials..."
az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing
