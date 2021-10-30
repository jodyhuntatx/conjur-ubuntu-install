#!/bin/bash
sudo apt update
sudo apt install -y python3 python3-pip
python3 -m pip install keyrings.alt
echo "Set Conjur admin password:"
keyring set conjur adminpwd
