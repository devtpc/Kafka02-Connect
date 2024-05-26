# Run this script only after AKS is running. See README.md
source ./config.conf

az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER
