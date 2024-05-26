FROM confluentinc/cp-server-connect-base:7.5.4 AS base

USER root

RUN confluent-hub install --no-prompt confluentinc/kafka-connect-azure-blob-storage:latest \
    && confluent-hub install --no-prompt confluentinc/kafka-connect-azure-blob-storage-source:latest

USER user