#run this only after you retreived ahe azure secret keys (you have the az_secret.conf) For more details see README.md
source ./config.conf
source ./az_secret.conf

az storage blob upload-batch --source ./../data --destination data  --account-name $STORAGE_ACCOUNT --account-key $STORAGE_ACCOUNT_KEY
