#!/bin/bash

source ./conjur.config

# This script deletes running instances and brings up 
#   initialized Conjur Follower & CLI nodes.

CURR_IP=$(ifconfig ens33 | grep "inet " | awk '{print $2}')
if [[ "$CURR_IP" != "$CONJUR_FOLLOWER_HOST_IP" ]]; then
  echo "Edit CONJUR_FOLLOWER_HOST_IP value in conjur.config to $CURR_IP."
  exit -1
fi

LEADER_OK=$(curl -sk $CONJUR_APPLIANCE_URL/health | jq .ok)
if [[ "$LEADER_OK" != "true" ]]; then
  echo "Leader ping failed. Check value of CONJUR_LEADER_HOSTNAME and"
  echo "  CONJUR_LEADER_HOST_IP in conjur.config."
  exit -1
fi

#################
main() {
  teardown_conjur
  if [[ "$1" == "stop" ]]; then
    exit -1
  fi
  follower_up
  cli_up
  echo
  echo
  echo "Performing smoke test secret retrieval:"
  echo -n "DB username: "
  sudo docker exec -it $CLI_CONTAINER_NAME		\
 	conjur variable value secrets/db-username 
  echo
  echo -n "DB password: "
  sudo docker exec -it $CLI_CONTAINER_NAME		\
 	conjur variable value secrets/db-password
  echo
}

#################
teardown_conjur() {
  echo "Terminating any running Follower and CLI containers..."
  sudo systemctl disable apparmor.service --now > /dev/null 2>&1
  sudo service apparmor teardown > /dev/null 2>&1
  sudo docker stop $CONJUR_FOLLOWER_CONTAINER_NAME > /dev/null 2>&1
  sudo docker rm $CONJUR_FOLLOWER_CONTAINER_NAME > /dev/null 2>&1
  sudo docker stop $CLI_CONTAINER_NAME > /dev/null 2>&1
  sudo docker rm $CLI_CONTAINER_NAME > /dev/null 2>&1
  sudo systemctl enable --now apparmor.service > /dev/null 2>&1
}

############################
follower_up() {
  # Bring up Conjur Follower node
  $DOCKER run -d					\
    --name $CONJUR_FOLLOWER_CONTAINER_NAME		\
    --label role=conjur_node				\
    -p "$CONJUR_FOLLOWER_PORT:443"			\
    -e "CONJUR_AUTHENTICATORS=$CONJUR_AUTHENTICATORS"	\
    --restart unless-stopped				\
    --security-opt seccomp:unconfined			\
    $CONJUR_APPLIANCE_IMAGE

  if $NO_DNS; then
    # add entry to follower's /etc/hosts so $CONJUR_LEADER_HOSTNAME resolves
    $DOCKER exec -it $CONJUR_FOLLOWER_CONTAINER_NAME \
	bash -c "echo \"$CONJUR_LEADER_HOST_IP $CONJUR_LEADER_HOSTNAME\" >> /etc/hosts"
  fi

  echo "Initializing Conjur Follower"
  $DOCKER cp $FOLLOWER_SEED_FILE \
		$CONJUR_FOLLOWER_CONTAINER_NAME:/tmp/follower-seed.tar
  $DOCKER exec $CONJUR_FOLLOWER_CONTAINER_NAME \
		evoke unpack seed /tmp/follower-seed.tar
  $DOCKER exec $CONJUR_FOLLOWER_CONTAINER_NAME \
		evoke configure follower -p $CONJUR_LEADER_PORT

  echo "Follower configured."
}

#################
cli_up() {

  # Bring up CLI node
  # If docker-compose installed, replace "docker run..." 
  #   with "docker-compose up -d cli"
  sudo docker run -d			\
    --name $CLI_CONTAINER_NAME		\
    --label role=cli			\
    --restart unless-stopped		\
    --security-opt seccomp:unconfined	\
    --entrypoint sh			\
    $CLI_IMAGE_NAME			\
    -c "sleep infinity"

  # if not relying on DNS - add entry for leader host name to cli container's /etc/hosts
  if $NO_DNS; then
    sudo docker exec $CLI_CONTAINER_NAME \
	bash -c "echo \"$CONJUR_LEADER_HOST_IP    $CONJUR_LEADER_HOSTNAME\" >> /etc/hosts"
  fi

  # Initialize connection to service (create .conjurrc and conjur-xx.pem cert)
  sudo docker exec $CLI_CONTAINER_NAME \
    bash -c "echo yes | conjur init -u $CONJUR_APPLIANCE_URL -a $CONJUR_ACCOUNT"

  # Login as admin
  sudo docker exec $CLI_CONTAINER_NAME \
    conjur authn login -u admin -p $CONJUR_ADMIN_PASSWORD
}

main "$@"
