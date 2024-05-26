#run this only after you retreived the azure secret keys (you have the az_secret.conf) For more details see README.md
source ./config.conf
source ./az_secret.conf

# Set the environment variables
export STORAGE_ACCOUNT=$STORAGE_ACCOUNT
export STORAGE_ACCOUNT_KEY=$STORAGE_ACCOUNT_KEY

# Apply the YAML configuration with the substituted variable
# NOTE: normally we would use envsubst, however "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value" has a $ sign in it, so it's problematic
# envsubst < ./../connectors/azure-source-expedia.json | curl -X POST -H "Content-Type: application/json" --data @- http://localhost:8083/connectors

# we are sed instead of envsubst:
sed -e "s|STORAGE_ACCOUNT_PLACEHOLDER|$STORAGE_ACCOUNT|g" \
    -e "s|STORAGE_ACCOUNT_KEY_PLACEHOLDER|$STORAGE_ACCOUNT_KEY|g" \
    ./../connectors/azure-source-expedia.json | curl -X POST -H "Content-Type: application/json" --data @- http://localhost:8083/connectors