#!/bin/sh
# Test seams override variables and functions consumed by sourced helpers.
# shellcheck disable=SC1091,SC2034,SC2329
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    expected=$1
    actual=$2
    context=$3
    [ "$actual" = "$expected" ] || fail "$context: expected <$expected>, got <$actual>"
}

assert_status_format() {
    name=$1
    file=$2
    awk -v name="$name" '
        /^[A-Za-z_][A-Za-z0-9_]*=/ {
            key=$0
            sub(/=.*/, "", key)
            if (seen[key]++) bad=1
            count++
            next
        }
        { bad=1 }
        END {
            if (!count || bad) {
                print "invalid key=value status: " name > "/dev/stderr"
                exit 1
            }
        }
    ' "$file" || fail "$name has invalid status output"
}

assert_required_fields() {
    file=$1
    shift
    for key in "$@"; do
        count=$(awk -F= -v key="$key" '$1 == key { count++ } END { print count+0 }' "$file")
        [ "$count" -eq 1 ] || fail "$file: missing or duplicate field $key"
    done
}

assert_value() {
    file=$1
    key=$2
    expected=$3
    actual=$(sed -n "s/^${key}=//p" "$file")
    assert_equal "$expected" "$actual" "$file field $key"
}

assert_empty_dir() {
    directory=$1
    context=$2
    [ -z "$(find "$directory" -mindepth 1 -print -quit)" ] \
        || fail "$context created or modified state"
}

test_fixtures() {
    network=$ROOT/tests/fixtures/network-status.txt
    virtual=$ROOT/tests/fixtures/virtual-status.txt
    missing=$ROOT/tests/fixtures/missing-status.txt

    assert_status_format network "$network"
    assert_status_format virtual "$virtual"
    assert_required_fields "$network" enabled mode effective_mode state lan_active clients watch internet
    assert_required_fields "$virtual" present enabled sunshine managed lifecycle width height refresh mode audio capture
    if (assert_required_fields "$missing" enabled mode effective_mode state) 2>/dev/null; then
        fail "missing status fields were accepted"
    fi
}

test_network_functions() (
    fixture=$TMP_ROOT/network
    mkdir "$fixture"
    MONITOR_MENU_SOURCE_ONLY=1
    export MONITOR_MENU_SOURCE_ONLY
    # shellcheck source=network-helper.sh
    . "$ROOT/network-helper.sh"

    for mode in auto current bypass; do
        actual=$(normalize_mode "$mode") || fail "valid mode rejected: $mode"
        assert_equal "$mode" "$actual" "network mode $mode"
    done
    for mode in '' AUTO private direct 'current ' 'bypass=1'; do
        if normalize_mode "$mode" >/dev/null 2>&1; then
            fail "invalid mode accepted: <$mode>"
        fi
    done

    RUN_DIR=$fixture
    STATE_DIR=$fixture
    STATE_FILE=$fixture/state
    MODE_FILE=$fixture/mode
    phase=UPLINK
    write_state bypass RECONFIGURING wlan0 phy0 36 5 uplink mm-ap0
    assert_equal UPLINK "$phase" "write_state caller phase"
    assert_value "$STATE_FILE" PHASE RECONFIGURING

    stop_pid() { :; }
    ap_iface() { printf '%s\n' mm-ap0; }
    ensure_ap_interface() { :; }
    start_hostapd() { :; }
    start_dnsmasq() { :; }
    setup_forwarding() { :; }
    log_event() { :; }
    apply_plan 'wlan0|phy0|36|5180|5|a|uplink'
    assert_value "$STATE_FILE" PHASE UPLINK

    rm -f "$STATE_FILE"
    require_root() { :; }
    default_route_iface() { return 1; }
    output=$fixture/status
    cmd_status > "$output"
    assert_status_format network-defaults "$output"
    assert_required_fields "$output" enabled mode effective_mode state lan_active clients watch internet
    assert_value "$output" enabled 0
    assert_value "$output" mode auto
    assert_value "$output" effective_mode stopped
    assert_value "$output" state STOPPED
    assert_value "$output" internet unavailable
    rm -f "$output"
    assert_empty_dir "$fixture" "network status"
)

test_vkms_status() (
    fixture=$TMP_ROOT/vkms
    mkdir "$fixture"
    MONITOR_MENU_SOURCE_ONLY=1
    export MONITOR_MENU_SOURCE_ONLY
    # shellcheck source=vkms-helper.sh
    . "$ROOT/vkms-helper.sh"

    RUN_DIR=$fixture/run
    STATE_DIR=$fixture/state-dir
    STATE_FILE=$RUN_DIR/state
    LOCK_DIR=$RUN_DIR/lock
    OWNED_FILE=$STATE_DIR/owned
    require_root() { :; }
    module_loaded() { return 1; }
    connector_present() { return 1; }
    connector_connected() { return 1; }

    output=$fixture/status
    cmd_status > "$output"
    assert_status_format vkms "$output"
    assert_required_fields "$output" owned loaded connector connected state
    assert_value "$output" state ABSENT
    rm -f "$output"

    mkdir -p "$RUN_DIR"
    printf '%s\n' 'STATE=CREATING' > "$STATE_FILE"
    cmd_status > "$output"
    assert_value "$output" state ABSENT
    rm -f "$output" "$STATE_FILE"
    rmdir "$RUN_DIR"
    assert_empty_dir "$fixture" "VKMS status"
)

test_virtual_status() {
    fixture=$TMP_ROOT/virtual
    bin=$fixture/bin
    mkdir -p "$bin"

    printf '#!/bin/sh\nexit 0\n' > "$bin/niri"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\n[ "${1:-}" != -n ] || shift\nexec "$@"\n' > "$bin/sudo"
    printf '#!/bin/sh\nexit 1\n' > "$bin/vkms"
    chmod +x "$bin/niri" "$bin/sudo" "$bin/vkms"

    output=$fixture/status
    HOME=$fixture/home \
        XDG_RUNTIME_DIR=$fixture/runtime \
        XDG_STATE_HOME=$fixture/state \
        XDG_CACHE_HOME=$fixture/cache \
        XDG_CONFIG_HOME=$fixture/config \
        MONITOR_MENU_VKMS_HELPER=$bin/vkms \
        PATH=$bin:/usr/bin:/bin \
        dash "$ROOT/virtual-monitor-helper.sh" status > "$output"

    assert_status_format virtual-defaults "$output"
    assert_required_fields "$output" present enabled sunshine managed lifecycle width height refresh mode audio capture
    assert_value "$output" lifecycle ERROR
    assert_value "$output" mode 1920x1080@60.000
    assert_value "$output" audio local
    [ ! -e "$fixture/runtime" ] || fail "virtual status created runtime state"
    [ ! -e "$fixture/state/monitor-menu" ] || fail "virtual status created persistent state"
    [ ! -e "$fixture/config/sunshine" ] || fail "virtual status created Sunshine config"
}

test_virtual_functions() (
    fixture=$TMP_ROOT/virtual-functions
    mkdir "$fixture"
    MONITOR_MENU_SOURCE_ONLY=1
    export MONITOR_MENU_SOURCE_ONLY
    # shellcheck source=virtual-monitor-helper.sh
    . "$ROOT/virtual-monitor-helper.sh"

    state_file=$fixture/virtual.state
    stop_sunshine() { :; }
    disable_virtual() { :; }
    destroy_virtual_device() { :; }

    rc=0
    rollback_virtual_start 42 on || rc=$?
    assert_equal 42 "$rc" "virtual rollback exit code"
    assert_equal on "$(sed -n '1p' "$state_file")" "virtual restore preference"

    valid_audio_mode local || fail "local audio mode rejected"
    valid_audio_mode virtual || fail "virtual audio mode rejected"
    if valid_audio_mode remote; then
        fail "invalid audio mode accepted"
    fi
)

test_mirror_status() {
    fixture=$TMP_ROOT/mirror
    mkdir "$fixture"
    pidfile=$fixture/monitor-menu-wl-mirror.pids
    printf '%s\n' 999999999 > "$pidfile"
    cp "$pidfile" "$fixture/original"
    output=$(XDG_RUNTIME_DIR=$fixture dash "$ROOT/mirror-helper.sh" status)
    assert_equal inactive "$output" "mirror status"
    cmp -s "$fixture/original" "$pidfile" || fail "mirror status modified its PID file"
}

test_fixtures
test_network_functions
test_vkms_status
test_virtual_status
test_virtual_functions
test_mirror_status

printf '%s\n' "helper tests passed"
