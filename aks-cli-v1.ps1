$AKS_RESOURCE_GROUP="rg-aks-test-weu-02"
$REGION="westeurope"
$MY_AKS_CLUSTER_NAME="aks-test-weu-02"
$MY_DNS_LABEL="aktestweu02"
$AAD_TENANT_ID='798ee643-af94-452c-83ba-2299a6353069'
$AKS_AAD_ADMIN_GROUP_NAME="aks_dev_admins"
$MY_ACR_NAME="acrtestweu02"
$VNET_RESOURCE_GROUP="rg-aks-test-weu-02"
$VNET_NAME="vnet-aks-test-weu-02"
$VNET_ADDRESS_PREFIX="10.10.0.0/16"
$SUBNET_NAME="subnet-aks-test-weu-02"
$SUBNET_ADDRESS_PREFIX="10.10.0.0/22"

# check if resource group exists otherwise create it   
$group_count = az group list --query "[?name=='$AKS_RESOURCE_GROUP'] | length(@)" 
if($group_count -eq 1) {
    echo "Resource group $AKS_RESOURCE_GROUP already exists." }
else {
    echo "Creating resource group $AKS_RESOURCE_GROUP..."
    az group create --name $AKS_RESOURCE_GROUP --location $REGION
}

# create a virtual network
if((az network vnet list --resource-group $VNET_RESOURCE_GROUP --query "[?name=='$VNET_NAME']| length(@)") -eq 1) {
    echo "VNet $VNET_NAME already exists." }
else {
    echo "Creating VNet $VNET_NAME..."
    az network vnet create --name $VNET_NAME --resource-group $VNET_RESOURCE_GROUP `
        --address-prefix $VNET_ADDRESS_PREFIX `
        --subnet-name $SUBNET_NAME `
        --subnet-prefix $SUBNET_ADDRESS_PREFIX
}

# Create an Azure Container Registry (ACR)
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


az aks create --resource-group $AKS_RESOURCE_GROUP --name $MY_AKS_CLUSTER_NAME --node-count 1 `
            --generate-ssh-keys  `
            --enable-managed-identity `
            --enable-azure-rbac `
            --enable-aad `
            --aad-admin-group-object-ids $aad_ak_dev_admin_group_object_id `
            --aad-tenant-id $AAD_TENANT_ID `
            --dns-name-prefix $MY_DNS_LABEL --location $REGION `
            --network-plugin azure --network-policy azure `
            --node-vm-size standard_a4m_v2 `
            --attach-acr $MY_ACR_NAME
            
az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $MY_AKS_CLUSTER_NAME --overwrite-existing
