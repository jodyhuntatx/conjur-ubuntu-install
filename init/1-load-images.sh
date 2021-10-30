#!/bin/bash
source ./conjur.config

echo "Loading Conjur appliance image..."
sudo docker load -i ./image_files/conjur-appliance_12.0.0.tar.gz
sudo docker load -i ./image_files/cli5.tar.gz
