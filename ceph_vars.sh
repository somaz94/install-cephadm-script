#!/bin/bash

# Define variables(Modify)
SSH_KEY="/home/ubuntu/.ssh/id_rsa_ansible" # SSH KEY Path
INVENTORY_FILE="inventory.ini" # Inventory Path
CEPHADM_PREFLIGHT_PLAYBOOK="cephadm-preflight.yml"
CEPHADM_CLIENTS_PLAYBOOK="cephadm-clients.yml"
CEPHADM_DISTRIBUTE_SSHKEY_PLAYBOOK="cephadm-distribute-ssh-key.yml"
HOST_GROUP=(test-server test-server-agent test-server-storage) # All host group
ADMIN_HOST="test-server" # Admin host name
OSD_HOST="test-server-storage" # Osd host name
HOST_IPS=("192.0.2.47" "192.0.2.43" "192.0.2.48") # Corresponding IPs and Select the first IP address for MON_IP
OSD_DEVICES=("sdb" "sdc" "sdd") # OSD devices, without /dev/ prefix
CLUSTER_NETWORK="192.0.2.0/24" # Cluster network CIDR
SSH_USER="ubuntu" # SSH user
CLEANUP_CEPH="false" # Ensure this is reset based on user input
