#!/bin/bash

stop_all_ceph_services() {
    echo "Stopping all Ceph services..."
    local services=$(sudo ceph orch ls --format=json | jq -r '.[].service_name')
    for service in $services; do
        if [[ "$service" != "mgr" && "$service" != "mon" && "$service" != "osd" ]]; then
            echo "Stopping $service..."
            sudo ceph orch stop $service
        else
            echo "Skipping $service (cannot be stopped directly)."
        fi
    done
}

remove_osds_and_cleanup_lvm() {
    echo "Checking for existing OSDs and cleaning them up..."
    osd_ids=$(sudo ceph osd ls)
    if [ -z "$osd_ids" ]; then
        echo "No OSDs to remove."
    else
        for osd_id in $osd_ids; do
            echo "Removing OSD.$osd_id..."
            sudo ceph orch daemon stop osd.$osd_id
            sleep 10
            sudo ceph osd out $osd_id
            sleep 10
            sudo ceph osd rm $osd_id
            # Wait a bit to ensure the OSD is fully purged
            sleep 10
        done
    fi

    echo "Cleaning up LVM volumes on $OSD_HOST..."
    ssh $OSD_HOST <<'EOF'
        sudo lvscan | awk '/ceph/ {print $2}' | xargs -I{} sudo lvremove -y {}
        sleep 5
        sudo vgscan | awk '/ceph/ {print $4}' | xargs -I{} sudo vgremove -y {}
        sleep 5
        sudo pvscan | grep '/dev/sd' | awk '{print $2}' | xargs -I{} sudo pvremove -y {}
EOF
}

cleanup_ceph_cluster() {
    if [ "$CLEANUP_CEPH" == "true" ]; then
        echo "Initiating Ceph cluster cleanup..."

        stop_all_ceph_services

        # Wait a bit to ensure all services are stopped
        sleep 10

        # Needs a running cluster, so it must precede rm-cluster
        remove_osds_and_cleanup_lvm

        if sudo test -d /var/lib/ceph; then
            echo "Cleaning up existing Ceph cluster..."
            sudo cephadm rm-cluster --fsid=$(sudo ceph fsid) --force
            echo "Ceph cluster removed successfully."
        else
            echo "No existing Ceph cluster found to clean up."
        fi

        echo "Removing any leftover Ceph containers..."
        for host in "${HOST_GROUP[@]}"; do
            echo "Cleaning up containers on $host..."
            ssh "$SSH_USER@$host" '
            if command -v docker &> /dev/null; then
                container_runtime="docker"
            elif command -v podman &> /dev/null; then
                container_runtime="podman"
            else
                echo "No container runtime (Docker or Podman) found on '"$host"'. Skipping container cleanup."
                exit 1
            fi

            sudo $container_runtime ps -a | grep ceph | awk '"'"'{print $1}'"'"' | xargs -I {} sudo $container_runtime rm -f {}
            '
            if [ $? -ne 0 ]; then
                echo "Error cleaning up containers on $host"
            else
                echo "Leftover Ceph containers removed successfully on $host."
            fi
        done
    else
        echo "Skipping Ceph cluster cleanup as per user's choice."
    fi
}

run_ansible_playbook() {
    playbook=$1
    extra_vars=$2
    ansible-playbook -i $INVENTORY_FILE $playbook $extra_vars --become
    if [ $? -ne 0 ]; then
        echo "Execution of playbook $playbook failed. Exiting..."
        exit 1
    fi
}

add_to_known_hosts() {
    host_ip=$1
    ssh-keyscan -H $host_ip >> ~/.ssh/known_hosts
}

add_osds_and_wait() {
    for device in "${OSD_DEVICES[@]}"; do
        echo "Attempting to add OSD on /dev/$device..."
        output=$(sudo /usr/bin/ceph orch daemon add osd $OSD_HOST:/dev/$device 2>&1)
        retval=$?

        if [ $retval -ne 0 ]; then
            echo "Command to add OSD on /dev/$device failed. Please check logs for errors. Output: $output"
            continue
        fi

        echo "Waiting a moment for OSD to be registered..."
        sleep 10

        osd_id=$(sudo /usr/bin/ceph osd tree | grep -oP "/dev/$device.*osd.\K[0-9]+")

        if [ -z "$osd_id" ]; then
            echo "Unable to find OSD ID for /dev/$device. It might take a moment for the OSD to be visible in the cluster."
        else
            echo "OSD with ID $osd_id has been added on /dev/$device."
        fi

        echo "Monitoring the readiness of OSD.$osd_id on /dev/$device..."

        success=false
        for attempt in {1..12}; do
            if sudo /usr/bin/ceph osd tree | grep "osd.$osd_id" | grep -q "up" && sudo /usr/bin/ceph osd tree | grep "osd.$osd_id"; then
                echo "OSD.$osd_id on /dev/$device is now ready."
                success=true
                break
            else
                echo "Waiting for OSD.$osd_id on /dev/$device to become ready..."
                sleep 10
            fi
        done

        if ! $success; then
            echo "Timeout waiting for OSD.$osd_id on /dev/$device to become ready. Please check Ceph cluster status."
        fi
    done
}


check_osd_creation() {
    echo "Checking Ceph cluster status and OSD creation..."
    sudo ceph -s
    sudo ceph osd tree
}

add_host_and_label() {
  echo "Adding and labeling hosts in the cluster..."
  for i in "${!HOST_GROUP[@]}"; do
      host="${HOST_GROUP[$i]}"
      ip="${HOST_IPS[$i]}"

      ssh-copy-id -f -i /etc/ceph/ceph.pub $host

      sudo ceph orch host add $host $ip

      if [[ "$host" == "$ADMIN_HOST" ]]; then
          sudo ceph orch host label add $host mon && \
          sudo ceph orch host label add $host mgr && \
          echo "Labels 'mon' and 'mgr' added to $host."
      fi

      if [[ "$host" == "$OSD_HOST" ]]; then
          sudo ceph orch host label add $host osd && \
          echo "Label 'osd' added to $host."
      fi

      if [[ "$host" != "$ADMIN_HOST" ]] && [[ "$host" != "$OSD_HOST" ]]; then
          sudo ceph orch host label add $host _no_schedule && \
          echo "Label '_no_schedule' added to $host."
      fi

      labels=$(sudo ceph orch host ls --format=json | jq -r '.[] | select(.hostname == "'$host'") | .labels[]')
      echo "Current labels for $host: $labels"
  done
}

label_osd_hosts_no_schedule() {
    echo "Applying '_no_schedule' label to all OSD hosts..."
    # OSD_HOST may be a single host or an array
    if [[ ! "${OSD_HOST[@]}" ]]; then
        osd_hosts=($OSD_HOST)
    else
        osd_hosts=("${OSD_HOST[@]}")
    fi

    for osd_host in "${osd_hosts[@]}"; do
        sudo ceph orch host label add $osd_host _no_schedule && \
        echo "Label '_no_schedule' added to $osd_host."
    done
}