CONFIG = ./configscripts/config.conf
include ${CONFIG}


#propagateing config settings to the respective folders/files
refresh-confs:
	@cd configscripts && \
	sh refresh_confs.sh


#docker commands - Note: docker dameon should be running
docker-build:
	@echo "Building docker image" $(DOCKER_IMAGE_NAME)
	@cd connectors && \
	docker build . -t $(DOCKER_IMAGE_NAME)
docker-push:
	@echo "Pushing docker image" $(DOCKER_IMAGE_NAME)
	@docker push $(DOCKER_IMAGE_NAME)
	@echo docker image $(DOCKER_IMAGE_NAME) pushed.
docker-upload: docker-build docker-push


#create infra with terraform - Note: you should be logged in with 'az login'
planinfra:
	@cd terraform && \
	terraform init --backend-config=backend.conf && \
	terraform plan -out terraform.plan

createinfra: planinfra
	@cd terraform && \
	terraform apply -auto-approve terraform.plan

#retrieve azure storage key and save it to a config file
retrieve-storage-keys:
	@echo "Retrieving azure keys"
	@cd configscripts && \
	sh retrieve_storage_keys.sh

#upload data to the provisioned storage account
uploaddata:
	@echo "Uploading data"
	@cd configscripts && \
	sh upload_data.sh


# Set open new terminal command. "kubectl proxy" should run in a new open terminal, which opens differently in different OS-s. Tested in Windows with Git Bash
ifeq ($(OS),Windows_NT)
    # Windows with Git Bash
    NEW_TERMINAL := cmd //c start cmd //k
else ifeq ($(shell uname),Linux)
    # Linux
    NEW_TERMINAL := x-terminal-emulator -e
else ifeq ($(shell uname),Darwin)
    # macOS
    NEW_TERMINAL := open -a Terminal
else
    $(error Unsupported operating system: $(shell uname))
endif


# preparing environment for kubectl commands
retrieve-aks-credentials:
	@cd configscripts && \
	sh retrieve_aks_credentials.sh

#prepare and install confluent for k8s
prepare-confluent:
	@kubectl create namespace confluent
	@kubectl config set-context --current --namespace=confluent
	@helm repo add confluentinc https://packages.confluent.io/helm
	@helm repo update	
	@helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes


#deploy our kafka environment
deploy-kafka:
	@cd configscripts && \
	sh deploy_confluent.sh
	kubectl apply -f ./producer-app-data.yaml
	kubectl get pods -o wide
	@echo "Start proxys only after all pods are running!"

#prev steps together
deploy-kafka-on-aks: retrieve-aks-credentials prepare-confluent deploy-kafka

#run port-forward to use localhost for some commands
run-proxys:
	@echo "Port Forward for control center"
	@$(NEW_TERMINAL) "kubectl port-forward controlcenter-0 9021:9021"
	@sleep 1
	@echo "Port Forward for Connect"
	@$(NEW_TERMINAL) "kubectl port-forward service/connect 8083:8083"
	@sleep 1



#create the expedia topic
createtopic-expedia:
	@kubectl exec kafka-0 -- /bin/bash -c 'kafka-topics --bootstrap-server localhost:9092 --create --topic expedia --replication-factor 3 --partitions 3'

#deploy the expedia connector
deploy-connector:
	@cd configscripts && \
	sh deploy_connector.sh


#destroy cluster with terraform. Only the cluster, the data storage part remains	
destroy-cluster:
	@cd terraform && \
	terraform destroy -auto-approve --target azurerm_kubernetes_cluster.bdcc

#bigger blocks

# all functions after `az login`, untipl kapfka is deployey:
deploy-env: refresh-confs docker-upload createinfra retrieve-storage-keys uploaddata deploy-kafka-on-aks


# after fully running env:
deploy-expedia: run-proxys createtopic-expedia deploy-connector