#!/bin/bash

source ./conjur.config

# This script deletes running instances and brings up 
#   initialized Conjur Leader & CLI nodes.

  echo "Terminating any running CLI container..."
  $DOCKER stop $CLI_CONTAINER_NAME
  $DOCKER rm $CLI_CONTAINER_NAME
  if [[ "$1" == "stop" ]]; then
    exit -1
  fi

  $DOCKER run -d			\
    --name $CLI_CONTAINER_NAME		\
    --label role=cli			\
    --add-host "$CONJUR_LEADER_HOSTNAME:$CONJUR_LEADER_HOST_IP" \
    --restart unless-stopped		\
    --security-opt seccomp:unconfined	\
    --entrypoint sh			\
    $CLI_IMAGE_NAME			\
    -c "sleep infinity"

  # Initialize connection to service (create .conjurrc and conjur-xx.pem cert)
  $DOCKER exec $CLI_CONTAINER_NAME \
    bash -c "echo yes | conjur init -u $CONJUR_APPLIANCE_URL -a $CONJUR_ACCOUNT"

  # Login as admin
  $DOCKER exec $CLI_CONTAINER_NAME \
    conjur authn login -u admin -p $CONJUR_ADMIN_PASSWORD
