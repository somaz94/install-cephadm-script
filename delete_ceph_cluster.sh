#!/bin/bash

source ceph_vars.sh
source ceph_functions.sh

read -p "Do you want to cleanup existing Ceph cluster? (yes/no): " user_confirmation
if [[ "$user_confirmation" == "yes" ]]; then
    CLEANUP_CEPH="true"
else
    CLEANUP_CEPH="false"
fi

cleanup_ceph_cluster

echo "Wiping OSD devices on $OSD_HOST..."
for device in ${OSD_DEVICES[@]}; do
    if ssh $OSD_HOST "sudo wipefs --all /dev/$device"; then
        echo "Wiped $device successfully."
    else
        echo "Failed to wipe $device."
    fi
done
