#!/usr/bin/env bats

setup() {
    CALLS="$BATS_TEST_TMPDIR/calls.log"
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_bin"
    for cmd in sudo ssh; do
        cat > "$stub_bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$CALLS"
case "\$*" in
    *"orch ls"*) echo '[]' ;;
    "test -d"*) exit 1 ;;
esac
EOF
        chmod +x "$stub_bin/$cmd"
    done
    export PATH="$stub_bin:$PATH"
    cd "$BATS_TEST_DIRNAME/.."
}

@test "declining cleanup exits without touching the cluster or devices" {
    run bash -c "echo no | bash delete_ceph_cluster.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleanup declined"* ]]
    [ ! -e "$CALLS" ]
}

@test "confirming cleanup wipes every OSD device" {
    run bash -c "echo yes | bash delete_ceph_cluster.sh"
    [ "$status" -eq 0 ]
    source ceph_vars.sh
    for device in "${OSD_DEVICES[@]}"; do
        grep -q "ssh $OSD_HOST sudo wipefs --all /dev/$device" "$CALLS"
    done
}
