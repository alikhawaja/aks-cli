$AKS_RESOURCE_GROUP="rg-aks-test-weu-02"
$MANAGED_RESOURCE_GROUP="mg-rg-aks-test-weu-02"
$KEY_VAULT_NAME="kv-aks-test-weu-02"
$AKS_KEY_NAME="aksuatkey"
$REGION="westeurope"
$MY_AKS_CLUSTER_NAME="aks-test-weu-03"
$MY_DNS_LABEL="aktestweu03"
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


$vnet_subnet_id=$(az network vnet subnet list --resource-group $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME --query "[?name=='$SUBNET_NAME'].id" -o tsv)
if($vnet_subnet_id -eq $null) {
    echo "Subnet $SUBNET_NAME not found in VNet $VNET_NAME."
    exit 1
}
else {
    echo "Subnet $SUBNET_NAME found in VNet $VNET_NAME with ID: $vnet_subnet_id"
}

# Key Vault - check if it exists otherwise create it
$keyvault_id=$(az keyvault list --query "[?name=='$KEY_VAULT_NAME'].id" -o tsv)
if($keyvault_id -eq $null) {
    echo "Key Vault $KEY_VAULT_NAME not found."
    #create the key vault
    echo "Creating Key Vault $KEY_VAULT_NAME..."
    az keyvault create --name $KEY_VAULT_NAME --resource-group $AKS_RESOURCE_GROUP --location $REGION `
        --sku standard `
        --enable-purge-protection true `
        --default-action Deny --bypass AzureServices `
        --public-network-access Disabled `

    $keyvault_id = $(az keyvault list --query "[?name=='$KEY_VAULT_NAME'].id" -o tsv)
    echo "Key Vault $KEY_VAULT_NAME created with ID: $keyvault_id"
}
else {
    echo "Key Vault $KEY_VAULT_NAME found with ID: $keyvault_id"
}

az keyvault key create --name $AKS_KEY_NAME `
    --vault-name $KEY_VAULT_NAME `
    --protection software --kty RSA --size 2048 `
    --tags "environment=dev" "owner=admin"
$AKS_KEY_ID = $(az keyvault key show --name $AKS_KEY_NAME --vault-name $KEY_VAULT_NAME --query 'key.kid' -o tsv)
az keyvault set-policy --name $KEY_VAULT_NAME --object-id $aad_ak_dev_admin_group_object_id --key-permissions get list create update delete backup restore recover purge

az aks create --resource-group $AKS_RESOURCE_GROUP --name $MY_AKS_CLUSTER_NAME --node-count 1 `
                --node-resource-group $MANAGED_RESOURCE_GROUP `
                --generate-ssh-keys  `
                --enable-managed-identity `
                --enable-azure-rbac --enable-aad --aad-admin-group-object-ids $aad_ak_dev_admin_group_object_id `
                --aad-tenant-id $AAD_TENANT_ID `
                --dns-name-prefix $MY_DNS_LABEL --location $REGION `
                --network-plugin azure --network-policy azure --vnet-subnet-id $vnet_subnet_id `
                --load-balancer-sku standard `
                --node-vm-size standard_d4as_v6 `
                --attach-acr $MY_ACR_NAME `
                --enable-azure-monitor-metrics `
                --enable-azure-keyvault-kms `
                --azure-keyvault-kms-key-id $AKS_KEY_ID `
                --azure-keyvault-kms-key-vault-resource-id $keyvault_id `
                --azure-keyvault-kms-key-vault-network-access 'Public'
 
# sleep until the cluster is ready
while ($true) {
    $cluster_status = az aks show --resource-group $AKS_RESOURCE_GROUP --name $MY_AKS_CLUSTER_NAME --query provisioningState -o tsv
    if ($cluster_status -eq "Succeeded") {
        break
    }
    else {
        echo "Cluster status: $cluster_status. Waiting for cluster to be ready..."
        Start-Sleep -Seconds 30
    }
}
az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $MY_AKS_CLUSTER_NAME --overwrite-existing
