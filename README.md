# Kafka Connect Homework

## Introduction

This project is a homework at the EPAM Data Engineering Mentor program. The main idea behind this task is to demonstrate how to connect applications with Kafka and deploy them. Infrastructure should be setup with Terraform on an Azure Kubernetes Cluster, and the Kafka deployed on this cluster should read data from an Azure Blob Container. The original copyright belongs to [EPAM](https://www.epam.com/). 

Some instructions from the original task:

* Data “m11kafkaconnect.zip” you can find [here](https://static.cdn.epam.com/uploads/583f9e4a37492715074c531dbd5abad2/dse/m11kafkaconnect.zip). Unzip it and upload into provisioned via Terraform storage account.
* Deploy Kubernetes Service and Storage Account, to setup infrastructure use terraform scripts from module. Kafka will be deployed in AKS, use Confluent Operator and Confluent Platform for this
* Modify Kafka Connect to read data from storage container into Kafka topic (expedia)
* Before uploading data into Kafka topic, please, mask time from the date field using MaskField transformer like: 2015-08-18 12:37:10 -> 0000-00-00 00:00:00


## About the repo

This repo is hosted [here](https://github.com/devtpc/Kafka02-Connect)

> [!NOTE]
> The original data files are not included in this repo, only the link.
> Some sensitive files, like configuration files, API keys, tfvars are not included in this repo.

## Prerequisites

* The necessiary software environment should be installed on the computer (python, spark, azure cli, docker, terraform, etc.)
* For Windows use Gitbash to run make and shell commands. (Task was deployed and tested on a Windows machine)
* Have an Azure account (free tier is enough)
* Have an Azure storage account ready for hosting the terraform backend


## Preparatory steps

### Download the data files

Download the data files from [here](https://static.cdn.epam.com/uploads/583f9e4a37492715074c531dbd5abad2/dse/m11kafkaconnect.zip).
Exctract the zip file, and copy its content to this repo. Rename the `m11kafkaconnect` folder to `data`.
The file structure should look like this:

![File structure image](/screenshots/img_file_structure.png)

### Setup your configuration

Go to the [configcripts folder](/configscripts/) and copy/rename the `config.conf.template` file to `config.conf`. Change the AZURE_BASE, DOCKER_IMAGE_NAME values as instructed within the file.

In the [configcripts folder](/configscripts/) copy/rename the `terraform_backend.conf.template` file to `terraform_backend.conf`. Fill the parameters with the terraform data.

Propagate your config data to other folders with the [refreshconfs.sh](/configscripts/refresh_confs.sh) script, or with `make refresh-confs` from the main folder

The details are in comments in the config files.

### Create and push the Docker image for Azure Blob Connector

We need an image with the  Azure Blob Storage Source Connector to be used later in the confluent-platform.yaml. The dockerfile is ready in the [connectors folder](/connectors/). In the dockerfile we basically use `confluentinc/cp-server-connect-base:7.5.4` as base, and install the latest `kafka-connect-azure-blob-storage` and `kafka-connect-azure-blob-storage-source`

```
# content of the dockerfile
FROM confluentinc/cp-server-connect-base:7.5.4 AS base

USER root

RUN confluent-hub install --no-prompt confluentinc/kafka-connect-azure-blob-storage:latest \
    && confluent-hub install --no-prompt confluentinc/kafka-connect-azure-blob-storage-source:latest

USER user
```

Before creating the image, make sure your docker daemon / docker desktop is running, and you are logged in your DockerHub account. This command uses internally the following structure:

```
cd connectors
# Build the image
docker build ./docker -t $DOCKER_IMAGE_NAME

# push the image
docker push $DOCKER_IMAGE_NAME
```
The image is pushed to DockerHub:

![Docker pushed image](/screenshots/img_docker_pushed.png)

## Create Azure base infrastructure with Terraform

Use `make createinfra` command to create the Azure infrastructure. This command uses internally the following structure:
```
cd terraform
#initialize your terraform
terraform init --backend-config=backend.conf

#plan the deployment
terraform plan -out terraform.plan

#confirm and apply the deployment. If asked, answer yes.
terraform apply terraform.plan
```
Surprisingly, for the first try Azure could not create the cluster in my `westeurope` region due to capacity error. 

![Cluster region error image](/screenshots/img_cluster_region_error.png)

Changing the Azure region to an alternative one (in my case to `northeurope`) solved the issue, and the resources were created:

![AKS created image](/screenshots/img_resources_created_cmd.png)

To verify the infrastructure visually, login to the Azure portal, and view your resource groups. There are  2 new resource groups:

* the one, which was parameterized, named rg-youruniquename-yourregion, with the Kubernetes Service and the Storage account.

![AKS created 2 image](/screenshots/img_resources_created_2.png)

* the managed cluster resource group, starting with MC_

![AKS created 3 image](/screenshots/img_resources_created_3.png)

After entering the AKS, it can be observed that events are occuring, confirming that the cluster is up and running:

![AKS created 4 image](/screenshots/img_resources_created_4.png)

## Upload data to provisioned account

### Save needed keys from Azure
Storage access key will be needed for data access, so save the storage account key from Azure by typing `make retrieve-storage-keys`. This saves the storage key to `configscripts/az_secret.conf` file. For retrieving, the command uses internally the following structure:
```
keys=$(az storage account keys list --resource-group $AKS_RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" --output tsv)
echo STORAGE_ACCOUNT_KEY='"'$keys'"' > ./az_secret.conf
```

### Upload data files to the storage account

Now, that you have your storage account and key ready, the data files can be uploaded to the storage. Type `make uploaddata` to upload the data files. This command uses internally the following structure:

```
az storage blob upload-batch --source ./../data --destination data  --account-name $STORAGE_ACCOUNT --account-key $STORAGE_ACCOUNT_KEY
```

The data is uploaded to the server:

![Data upload 1 img](/screenshots/img_data_uploaded.png)

## Prepare the cluster before deployment

If you destroyed your previous AKS cluster, and now you are trying to set it up with the same name, you might need to edit your `.kube/.config` file to remove your previous credentials. 

Use `make retrieve-aks-credentials` to get the AKS credentials, and prepare the `kubectl` to use the cluster. This command uses internally the following structure:
```
az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER
```

![AKS credentials ready img](/screenshots/img_aks_credentials_ready.png)

## Prepare the cluster for using Confluent

Use `make prepare-confluent` to prepare kubernetes for using confluent. This command uses internally the following structure:
```
# Create a namespace
kubectl create namespace confluent

#Set this namespace to default for Kubernetes context
kubectl config set-context --current --namespace confluent

# Add Confluent for Kubernetes Helm repository:
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

# Install Confluent for Kubernetes via Helm
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
```
![Prepare confluent img](/screenshots/img_prepare_confluent.png)

## Deploy the Confluent Kafka Environment

Use `make deploy-kafka` to deploy the Confluent Platform Component, and a sample producer app and topic. This command uses internally the following structure:
```
#deploy the platform using env. variables
envsubst < ./confluent-platform.yaml | kubectl apply -f -

#use this, if your docker image is hardcoded, alternatively you can use this:
#kubectl apply -f ./confluent-platform.yaml 


#deploy the sample producer app, not really needed, just a possible checkpoint
kubectl apply -f ./producer-app-data.yaml

#show the pods
kubectl get pods -o wide
```

> [!NOTE]
> The main part here is deploying the confluent platform with the `confluent-platform.yaml` config file. The values in the `yaml` are hardcoded, except for our docker image for the `connect`, which was created earlier. That's why `envsubst < ./confluent-platform.yaml | kubectl apply -f -` was used. If all files are hardcoded, `kubectl apply -f ./confluent-platform.yaml` can be used

The `kubectl get pods -o wide` at the end shows the pods. As it can be seen, the pods are not ready yet.

![Deploy kafka 1 img](/screenshots/img_deploy_kafka_1.png)

Check regularily with `kubectl get pods -o wide`, if all pods have running, and all heave READY 1/1 state! It may require several minutes. If everything is ready, we can go to the next step.

![Deploy kafka 2 img](/screenshots/img_deploy_kafka_2.png)

## Check the environment at the control center

### Setup port-forwarding

Use `make run-proxys` to start port-forwarding to the Control Center and to Connect Service, in order to use them as localhost. The command internally uses these 2 commands:
```
kubectl port-forward controlcenter-0 9021:9021
kubectl port-forward service/connect 8083:8083
```

Note, that if you are using these commands separately without the `make` command, you should run them in two new terminals, as they are blocking the terminal.

![Portforward img](/screenshots/img_portforward.png)

### Check Control Center

Control Center now can be opened at: [http://localhost:9021](http://localhost:9021)

It can be checked, that it is working:

![Control Center 1 img](/screenshots/img_controlcenter_1.png)
![Control Center 2 img](/screenshots/img_controlcenter_2.png)


## Create the expedia topic

use `make createtopic-expedia` to create the expedia topic. The command internally uses this command:
```
kubectl exec kafka-0 -- /bin/bash -c 'kafka-topics --bootstrap-server localhost:9092 --create --topic expedia --replication-factor 3 --partitions 3'
```
Note, that we are creating 3 partitions, as we have 3 partitions in the original source files.

Normally, when not using `Makefile` this command is executed in two steps. First we open a terminal in one of the a cluster's node:
```
kubectl exec -it kafka-0 -- /bin/bash
```
And then submit the kafka-topics commad in the node terminal:

```
kafka-topics --bootstrap-server localhost:9092 --create --topic expedia --replication-factor 3 --partitions 3
```

![Topic created 1 img](/screenshots/img_topic_created_1.png)

We can check on the Control Center that the topic is really created

![Topic created 2 img](/screenshots/img_topic_created_2.png)

## Prepare the Azure connector configuration

The created connector is the [azure-source-expedia.json](/connectors/azure-source-expedia.json) in the [/connectors](/connectors/) folder
Some important elements from the connector's config part:

The connector is based on the generic `AzureBlobStorageSourceConnector`, using the generic mode.
```
      "connector.class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
      "mode":"GENERIC",
      "tasks.max": "3",
```

The access path and credentials to the storages should be properly set. You either hardcode the values (not recommended, only for testing) or use the script to replace the placeholders on-the-fly with the real values:
```
      "azblob.account.name": "STORAGE_ACCOUNT_PLACEHOLDER",
      "azblob.account.key": "STORAGE_ACCOUNT_KEY_PLACEHOLDER",
      "azblob.container.name": "data",
```


As the `date_time` field should me masked, it has to be set properly:
```
      "transforms": "MaskField",
      "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value",
      "transforms.MaskField.fields": "date_time",
      "transforms.MaskField.replacement": "0000-00-00 00:00:00",
```

The topic details, and format should be properly set:
```
      "format.class": "io.confluent.connect.cloud.storage.source.format.CloudStorageAvroFormat",
      "topic": "expedia",
      "topics.dir": "topics",
      "topic.regex.list": "expedia:.*"
```


## Upload the connector file through the API


> [!CAUTION]
> Be extreme careful, if the Connector isn't working properly, and immediately examine the logs, or shut down the connector/cluster! Although using the small quantity of data on a storage is very cheap in Azure, the pricing has an other important factor: number or transactions. A badly designed or erroneous Connector may constantly poll your storage at a very high rate, resulting in an extremely high transaction count. This chart shows, that while I was experimenting with some configurations, and used some wrong settings, I had almost 3.5 million transanctions on the storage, resulting in a cost of more that 20 EUR. On the chart a bar is 5 minutes wide, meaning that sometimes it was more than 200,000 ListBlob operations within 5 minutes!
>
> ![Transaction chart img](/screenshots/img_transaction_chart.png)


Use `make deploy-connector` to deploy the connector to the cluster. The command internally uses this command:
```
# to use environment variables for storage account/key
# NOTE: normally we would use envsubst, however "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value" has a $ sign in it, so it's problematic

sed -e "s|STORAGE_ACCOUNT_PLACEHOLDER|$STORAGE_ACCOUNT|g" \
    -e "s|STORAGE_ACCOUNT_KEY_PLACEHOLDER|$STORAGE_ACCOUNT_KEY|g" \
    ./connectors/azure-source-expedia.json | curl -X POST -H "Content-Type: application/json" --data @- http://localhost:8083/connectors

# normal command with hardcoded storage account/key:
# curl -X POST -H "Content-Type: application/json" --data @qconnectors/azure-source-expedia.json http://localhost:8083/connectors
```

If there are no errors, the connector is deployed:

![Connector deployed 1 img](/screenshots/img_connector_deployed.png)


## Observe, that the connector is working

We can observe the connector logs, that it reads the data:

![Topic consumed 1 img](/screenshots/img_topic_consumed_1.png)

On the Control center we can observe, that now there is substantial data at the produced thoughput, the topic now has substantial data read, and the Offset is also greater than 0 in the hundred thousands range, meaning, that data is being read.

![Expedia read 1 img](/screenshots/img_expedia_read_1.png)

![Expedia read 2 img](/screenshots/img_expedia_read_2.png)

If we look at the messages, and jump back to the beginning of the message queue, we can observe, that the expedia data is shown.

![Show messages 1 img](/screenshots/img_show_messages_1.png)

We can observe, that the `date_time` field was really masked to 0


![Show messages 2 img](/screenshots/img_show_messages_2.png)


## Clean up your work
As the task has been finished, use `make destroy-cluster` to destroy the cluster!