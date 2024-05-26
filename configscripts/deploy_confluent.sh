#run this only after you retreived the azure secret keys (you have the az_secret.conf) For more details see README.md
source ./config.conf
source ./az_secret.conf

# Set the environment variable
export DOCKER_IMAGE_PATH=$DOCKER_IMAGE_PATH

# Apply the YAML configuration with the substituted variable
envsubst < ./../confluent-platform.yaml | kubectl apply -f -
