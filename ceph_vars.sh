#!/bin/bash

# Define variables(Modify)
SSH_KEY="/home/ubuntu/.ssh/id_rsa_ansible"
INVENTORY_FILE="inventory.ini"
CEPHADM_PREFLIGHT_PLAYBOOK="cephadm-preflight.yml"
CEPHADM_CLIENTS_PLAYBOOK="cephadm-clients.yml"
CEPHADM_DISTRIBUTE_SSHKEY_PLAYBOOK="cephadm-distribute-ssh-key.yml"
HOST_GROUP=(test-server test-server-agent test-server-storage)
ADMIN_HOST="test-server"
OSD_HOST="test-server-storage"
HOST_IPS=("192.0.2.47" "192.0.2.43" "192.0.2.48") # Same order as HOST_GROUP; [0] is the MON_IP
OSD_DEVICES=("sdb" "sdc" "sdd") # Without the /dev/ prefix
CLUSTER_NETWORK="192.0.2.0/24"
SSH_USER="ubuntu"
CLEANUP_CEPH="false" # Overridden by the yes/no prompt at runtime
