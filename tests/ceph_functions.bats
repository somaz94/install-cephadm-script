#!/usr/bin/env bats

setup() {
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    source "$BATS_TEST_DIRNAME/../ceph_functions.sh"
    OSD_HOST="ceph-storage"
    POLL_FILE="$BATS_TEST_TMPDIR/metadata_polls"
    METADATA_READY_AFTER=0

    sleep() { :; }
    sudo() {
        case "$*" in
            *"orch daemon add osd"*"/dev/sdx"*) echo "Error EINVAL: device not found"; return 22 ;;
            *"orch daemon add osd"*) echo "Created osd(s) on host '$OSD_HOST'" ;;
            *"osd metadata"*)
                # Runs inside $(...), so the poll count has to live in a file
                local polls
                polls=$(( $(cat "$POLL_FILE" 2>/dev/null || echo 0) + 1 ))
                echo "$polls" > "$POLL_FILE"
                if [ "$polls" -gt "$METADATA_READY_AFTER" ]; then
                    cat "$FIXTURES/osd_metadata.json"
                else
                    echo '[]'
                fi
                ;;
            *"osd dump"*) cat "$FIXTURES/osd_dump.json" ;;
            *) echo "sudo $*" ;;
        esac
    }
}

@test "find_osd_id ignores the same device on another host" {
    run find_osd_id ceph-storage sdb
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "find_osd_id matches one device of a multi-device OSD" {
    run find_osd_id ceph-storage sda
    [ "$output" = "0" ]
}

@test "find_osd_id prints nothing for an unknown device" {
    run find_osd_id ceph-storage sdz
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "osd_is_up_and_in requires both up and in" {
    run osd_is_up_and_in 0
    [ "$status" -eq 0 ]
    run osd_is_up_and_in 1
    [ "$status" -ne 0 ]
    run osd_is_up_and_in 7
    [ "$status" -ne 0 ]
    run osd_is_up_and_in 99
    [ "$status" -ne 0 ]
}

@test "add_osds_and_wait reports an up and in OSD as ready" {
    OSD_DEVICES=(sdb)
    run add_osds_and_wait
    [[ "$output" == *"OSD with ID 0 has been added on /dev/sdb."* ]]
    [[ "$output" == *"OSD.0 on /dev/sdb is now ready."* ]]
}

@test "add_osds_and_wait retries the ID lookup until the OSD registers" {
    OSD_DEVICES=(sdb)
    METADATA_READY_AFTER=2
    run add_osds_and_wait
    [ "$(cat "$POLL_FILE")" -eq 3 ]
    [[ "$output" == *"OSD.0 on /dev/sdb is now ready."* ]]
}

@test "add_osds_and_wait times out with the ID when the OSD stays out" {
    OSD_DEVICES=(sdc)
    run add_osds_and_wait
    [[ "$output" == *"Timeout waiting for the OSD on /dev/sdc (ID: 1)"* ]]
    [[ "$output" != *"is now ready"* ]]
}

@test "add_osds_and_wait never reports ready when the OSD never registers" {
    OSD_DEVICES=(sdb)
    METADATA_READY_AFTER=99
    run add_osds_and_wait
    [[ "$output" == *"Timeout waiting for the OSD on /dev/sdb (ID: unknown)"* ]]
    [[ "$output" != *"is now ready"* ]]
}

@test "add_osds_and_wait skips a device whose add command fails" {
    OSD_DEVICES=(sdx sdb)
    run add_osds_and_wait
    [[ "$output" == *"Command to add OSD on /dev/sdx failed"* ]]
    [[ "$output" != *"Monitoring the readiness of the OSD on /dev/sdx"* ]]
    [[ "$output" == *"OSD.0 on /dev/sdb is now ready."* ]]
}

@test "label_osd_hosts_no_schedule labels a single host" {
    OSD_HOST="ceph-storage"
    run label_osd_hosts_no_schedule
    [[ "$output" == *"sudo ceph orch host label add ceph-storage _no_schedule"* ]]
}

@test "label_osd_hosts_no_schedule labels every host in an array" {
    OSD_HOST=(storage-1 storage-2)
    run label_osd_hosts_no_schedule
    [[ "$output" == *"label add storage-1 _no_schedule"* ]]
    [[ "$output" == *"label add storage-2 _no_schedule"* ]]
}
