#!/bin/sh
set -eu

# Installed root-owned by setup-network.sh. The plugin never runs this copy.
AP_IF_DEFAULT=mm-ap0
SSID_DEFAULT=MonitorMenu
LAN_CIDR=10.77.0.1/24
DHCP_START=10.77.0.10
DHCP_END=10.77.0.50
NO_UPLINK_GRACE=8
CONNECT_TIMEOUT=30
STABLE_SAMPLES=2

RUN_DIR=/run/monitor-menu-network
STATE_DIR=/var/lib/monitor-menu-network
STATE_FILE=$RUN_DIR/state
LOCK_DIR=$RUN_DIR/lock
HOSTAPD_CONF=$RUN_DIR/hostapd.conf
HOSTAPD_PID=$RUN_DIR/hostapd.pid
DNSMASQ_PID=$RUN_DIR/dnsmasq.pid
WATCH_PID=$RUN_DIR/watch.pid
LEASE_FILE=$RUN_DIR/dnsmasq.leases
LOG_FILE=$RUN_DIR/network.log
MODE_FILE=$STATE_DIR/mode
SSID_FILE=$STATE_DIR/ssid
PASS_FILE=$STATE_DIR/passphrase
MAC_FILE=$STATE_DIR/ap.mac
AP_IF_FILE=$STATE_DIR/interface
OWNED_FILE=$RUN_DIR/interface-owned
FORWARD_FILE=$RUN_DIR/forwarding.previous
ROUTE_FILE=$RUN_DIR/forwarding.route
NFT_TABLE=monitor_menu_network

err() { printf 'monitor-menu-network: %s\n' "$*" >&2; }

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        err "esta acción requiere root"
        exit 77
    }
}

ensure_dirs() {
    mkdir -p "$RUN_DIR" "$STATE_DIR"
    chmod 0755 "$RUN_DIR"
    chmod 0700 "$STATE_DIR"
}

log_event() {
    ensure_dirs
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "falta el comando: $1"
        return 127
    }
}

acquire_lock() {
    ensure_dirs
    tries=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        set -- "$LOCK_DIR"/owner.*
        owner=
        [ ! -d "$1" ] || owner=${1##*.}
        case "$owner" in
            ''|*[!0-9]*)
                if [ "$tries" -ge 20 ]; then
                    rmdir "$LOCK_DIR" 2>/dev/null || true
                fi
                ;;
            *)
                if ! kill -0 "$owner" 2>/dev/null; then
                    rmdir "$LOCK_DIR/owner.$owner" 2>/dev/null || true
                    rmdir "$LOCK_DIR" 2>/dev/null || true
                fi
                ;;
        esac
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || { err "otra operación de red sigue activa"; return 75; }
        sleep 0.1
    done
    mkdir "$LOCK_DIR/owner.$$" || { rmdir "$LOCK_DIR" 2>/dev/null || true; return 75; }
}

release_lock() {
    if [ -d "$LOCK_DIR/owner.$$" ]; then
        rmdir "$LOCK_DIR/owner.$$" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}

normalize_mode() {
    case "${1:-}" in
        auto) printf 'auto\n' ;;
        current) printf 'current\n' ;;
        bypass) printf 'bypass\n' ;;
        *) return 1 ;;
    esac
}

get_mode() {
    if [ -s "$MODE_FILE" ]; then
        mode=$(sed -n '1p' "$MODE_FILE" 2>/dev/null || true)
        normalize_mode "$mode" 2>/dev/null || printf 'auto\n'
    else
        printf 'auto\n'
    fi
}

persist_value() {
    file=$1
    value=$2
    tmp="$file.tmp.$$"
    umask 077
    printf '%s\n' "$value" > "$tmp" || return 1
    chmod 0600 "$tmp" || return 1
    mv "$tmp" "$file" || return 1
}

set_mode() {
    mode=$(normalize_mode "$1") || { err "modo inválido: $1"; return 2; }
    ensure_dirs
    persist_value "$MODE_FILE" "$mode"
}

ensure_identity() {
    ensure_dirs
    [ -s "$AP_IF_FILE" ] || persist_value "$AP_IF_FILE" "$AP_IF_DEFAULT" || return 1
    [ -s "$SSID_FILE" ] || persist_value "$SSID_FILE" "$SSID_DEFAULT" || return 1

    if [ ! -s "$PASS_FILE" ]; then
        pass=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | dd bs=1 count=20 2>/dev/null || true)
        [ "${#pass}" -ge 16 ] || { err "no se pudo generar una clave segura"; return 1; }
        persist_value "$PASS_FILE" "$pass" || return 1
    fi

    mac=$(sed -n '1p' "$MAC_FILE" 2>/dev/null || true)
    if ! printf '%s\n' "$mac" | grep -Eq '^02(:[0-9a-fA-F]{2}){5}$' || mac_in_use "$mac"; then
        attempt=0
        while [ "$attempt" -lt 10 ]; do
            bytes=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
            [ "${#bytes}" -eq 10 ] || { err "no se pudo generar la MAC local"; return 1; }
            mac="02:$(printf '%s' "$bytes" | cut -c1-2):$(printf '%s' "$bytes" | cut -c3-4):$(printf '%s' "$bytes" | cut -c5-6):$(printf '%s' "$bytes" | cut -c7-8):$(printf '%s' "$bytes" | cut -c9-10)"
            mac_in_use "$mac" || break
            attempt=$((attempt + 1))
        done
        [ "$attempt" -lt 10 ] || { err "no se pudo generar una MAC única"; return 1; }
        persist_value "$MAC_FILE" "$mac" || return 1
    fi
}

mac_in_use() {
    wanted=$1
    [ -n "$wanted" ] || return 1
    for address_file in /sys/class/net/*/address; do
        [ -r "$address_file" ] || continue
        current=$(sed -n '1p' "$address_file" 2>/dev/null || true)
        [ "$current" != "$wanted" ] || return 0
    done
    return 1
}

ap_iface() {
    [ -s "$AP_IF_FILE" ] && sed -n '1p' "$AP_IF_FILE" || printf '%s\n' "$AP_IF_DEFAULT"
}

pid_matches() {
    pidfile=$1
    marker=$2
    [ -s "$pidfile" ] || return 1
    pid=$(sed -n '1p' "$pidfile" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 0
    tr '\000' ' ' < "/proc/$pid/cmdline" | grep -Fq -- "$marker"
}

stop_pid() {
    pidfile=$1
    marker=$2
    if pid_matches "$pidfile" "$marker"; then
        pid=$(sed -n '1p' "$pidfile")
        kill "$pid" 2>/dev/null || return 1
        i=0
        while [ "$i" -lt 30 ] && pid_matches "$pidfile" "$marker"; do
            sleep 0.1
            i=$((i + 1))
        done
        if pid_matches "$pidfile" "$marker"; then
            kill -KILL "$pid" 2>/dev/null || return 1
            sleep 0.1
            pid_matches "$pidfile" "$marker" && return 1
        fi
    fi
    rm -f "$pidfile"
}

write_state() {
    effective=$1
    phase=$2
    uplink=$3
    phy=$4
    channel=$5
    band=$6
    source=$7
    ap=$8
    tmp="$STATE_FILE.tmp.$$"
    {
        printf 'EFFECTIVE_MODE=%s\n' "$effective"
        printf 'PHASE=%s\n' "$phase"
        printf 'UPLINK=%s\n' "$uplink"
        printf 'PHY=%s\n' "$phy"
        printf 'CHANNEL=%s\n' "$channel"
        printf 'BAND=%s\n' "$band"
        printf 'SOURCE=%s\n' "$source"
        printf 'AP_IF=%s\n' "$ap"
    } > "$tmp" || return 1
    chmod 0644 "$tmp" || return 1
    mv "$tmp" "$STATE_FILE" || return 1
}

state_get() {
    key=$1
    [ -r "$STATE_FILE" ] || return 1
    sed -n "s/^${key}=//p" "$STATE_FILE" | sed -n '1p'
}

list_wifi_ifaces() {
    iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }'
}

iface_type() {
    iw dev "$1" info 2>/dev/null | awk '$1 == "type" { print $2; exit }'
}

find_connected_managed() {
    ap=$(ap_iface)
    for iface in $(list_wifi_ifaces); do
        [ "$iface" = "$ap" ] && continue
        [ "$(iface_type "$iface" 2>/dev/null || true)" = managed ] || continue
        if iw dev "$iface" link 2>/dev/null | grep -q '^Connected to '; then
            printf '%s\n' "$iface"
            return 0
        fi
    done
    return 1
}

find_managed_iface() {
    connected=$(find_connected_managed 2>/dev/null || true)
    [ -z "$connected" ] || { printf '%s\n' "$connected"; return 0; }
    ap=$(ap_iface)
    for iface in $(list_wifi_ifaces); do
        [ "$iface" = "$ap" ] && continue
        [ "$(iface_type "$iface" 2>/dev/null || true)" = managed ] || continue
        printf '%s\n' "$iface"
        return 0
    done
    return 1
}

iface_phy() {
    iface=$1
    link=$(readlink -f "/sys/class/net/$iface/phy80211" 2>/dev/null || true)
    [ -z "$link" ] || { basename "$link"; return 0; }
    wiphy=$(iw dev "$iface" info 2>/dev/null | awk '$1 == "wiphy" { print $2; exit }')
    [ -n "$wiphy" ] || return 1
    printf 'phy%s\n' "$wiphy"
}

connected_radio_info() {
    iface=${1:-$(find_connected_managed 2>/dev/null || true)}
    [ -n "$iface" ] || return 1
    line=$(iw dev "$iface" info 2>/dev/null | awk '/^[[:space:]]*channel [0-9]+ / { sub(/^[[:space:]]*/, ""); print; exit }')
    [ -n "$line" ] || return 1
    channel=$(printf '%s\n' "$line" | awk '{print $2}')
    freq=$(printf '%s\n' "$line" | sed -n 's/.*(\([0-9][0-9]*\) MHz).*/\1/p')
    phy=$(iface_phy "$iface")
    case "$channel:$freq" in *[!0-9:]*|:*) return 1 ;; esac
    if [ "$freq" -lt 3000 ]; then band=2.4; hw=g
    elif [ "$freq" -lt 5925 ]; then band=5; hw=a
    else return 1
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$iface" "$phy" "$channel" "$freq" "$band" "$hw"
}

country_code() {
    iw reg get 2>/dev/null | sed -n 's/^[[:space:]]*country \([A-Z][A-Z]\):.*/\1/p' | grep -v '^00$' | sed -n '1p'
}

channel_usable() {
    iw phy "$1" info 2>/dev/null | awk -v wanted="[$2]" '
        index($0, wanted) && $0 !~ /disabled|no IR|radar detection/ { ok=1 }
        END { exit ok ? 0 : 1 }
    '
}

choose_standalone_channel() {
    phy=$1
    for channel in 149 157 153 161 36 44 40 48 6 1 11; do
        channel_usable "$phy" "$channel" || continue
        printf '%s\n' "$channel"
        return 0
    done
    return 1
}

radio_plan() {
    managed=$(find_managed_iface 2>/dev/null || true)
    [ -n "$managed" ] || { err "no se encontró una interfaz Wi-Fi managed"; return 1; }
    associated=$(find_connected_managed 2>/dev/null || true)
    if [ -n "$associated" ]; then
        connected=$(connected_radio_info "$associated" 2>/dev/null || true)
        [ -n "$connected" ] || { err "el canal del uplink no admite Bypass"; return 1; }
        printf '%s|uplink\n' "$connected"
        return 0
    fi
    phy=$(iface_phy "$managed")
    channel=$(choose_standalone_channel "$phy") || { err "no hay un canal AP permitido"; return 1; }
    if [ "$channel" -le 14 ]; then band=2.4; hw=g; freq=0; else band=5; hw=a; freq=0; fi
    printf '%s|%s|%s|%s|%s|%s|standalone\n' "$managed" "$phy" "$channel" "$freq" "$band" "$hw"
}

ensure_ap_interface() {
    phy=$1
    ap=$(ap_iface)
    mac=$(sed -n '1p' "$MAC_FILE")
    if ip link show "$ap" >/dev/null 2>&1; then
        [ -f "$OWNED_FILE" ] || { err "la interfaz $ap ya existe y no pertenece a Monitor Menu"; return 1; }
    else
        iw phy "$phy" interface add "$ap" type __ap || return 1
        : > "$OWNED_FILE"
    fi
    command -v nmcli >/dev/null 2>&1 && nmcli device set "$ap" managed no >/dev/null 2>&1 || true
    ip link set "$ap" down >/dev/null 2>&1 || true
    iw dev "$ap" set type __ap || return 1
    ip link set dev "$ap" address "$mac" || return 1
    ip addr flush dev "$ap" || return 1
    ip addr add "$LAN_CIDR" dev "$ap" || return 1
    ip link set "$ap" up || return 1
}

write_hostapd_conf() {
    channel=$1
    hw=$2
    ap=$(ap_iface)
    ssid=$(sed -n '1p' "$SSID_FILE")
    pass=$(sed -n '1p' "$PASS_FILE")
    country=$(country_code || true)
    umask 077
    {
        printf 'interface=%s\n' "$ap"
        printf 'driver=nl80211\nssid=%s\n' "$ssid"
        [ -z "$country" ] || printf 'country_code=%s\n' "$country"
        printf 'hw_mode=%s\nchannel=%s\nwmm_enabled=1\nauth_algs=1\n' "$hw" "$channel"
        printf 'wpa=2\nwpa_passphrase=%s\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=CCMP\n' "$pass"
        printf 'ieee80211n=1\nap_isolate=1\n'
        [ "$hw" != a ] || printf 'ieee80211ac=1\n'
    } > "$HOSTAPD_CONF" || return 1
    chmod 0600 "$HOSTAPD_CONF" || return 1
}

start_hostapd() {
    channel=$1
    hw=$2
    ap=$(ap_iface)
    stop_pid "$HOSTAPD_PID" hostapd || return 1
    write_hostapd_conf "$channel" "$hw" || return 1
    hostapd -B -P "$HOSTAPD_PID" "$HOSTAPD_CONF" >/dev/null 2>&1 || return 1
    i=0
    while [ "$i" -lt 40 ]; do
        if pid_matches "$HOSTAPD_PID" hostapd \
            && iw dev "$ap" info 2>/dev/null | grep -q "channel $channel "; then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    stop_pid "$HOSTAPD_PID" hostapd
    return 1
}

lan_address() {
    ap=$(ap_iface)
    ip -4 -o addr show dev "$ap" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}'
}

start_dnsmasq() {
    ap=$(ap_iface)
    address=$(lan_address)
    [ -n "$address" ] || return 1
    stop_pid "$DNSMASQ_PID" dnsmasq || return 1
    : > "$LEASE_FILE"
    if dnsmasq --conf-file= --interface="$ap" --bind-dynamic --listen-address="$address" \
        --dhcp-range="$DHCP_START,$DHCP_END,255.255.255.0,12h" \
        --dhcp-option="3,$address" --dhcp-option="6,$address" \
        --dhcp-leasefile="$LEASE_FILE" --pid-file="$DNSMASQ_PID" 2>/dev/null \
        && pid_matches "$DNSMASQ_PID" dnsmasq; then
        return 0
    fi
    stop_pid "$DNSMASQ_PID" dnsmasq || return 1
    dns=$(awk '$1 == "nameserver" && $2 !~ /^127\./ && $2 != "::1" {
        if (count++) printf ","
        printf "%s", $2
        if (count == 2) exit
    } END { print "" }' /etc/resolv.conf 2>/dev/null)
    [ -n "$dns" ] || dns=1.1.1.1,8.8.8.8
    dnsmasq --conf-file= --interface="$ap" --bind-dynamic --port=0 \
        --dhcp-range="$DHCP_START,$DHCP_END,255.255.255.0,12h" \
        --dhcp-option="3,$address" --dhcp-option="6,$dns" \
        --dhcp-leasefile="$LEASE_FILE" \
        --pid-file="$DNSMASQ_PID" >/dev/null 2>&1
    pid_matches "$DNSMASQ_PID" dnsmasq
}

nft_bin() {
    command -v nft 2>/dev/null
}

default_route_iface() {
    ap=$(ap_iface)
    ip -4 route show default 2>/dev/null | awk -v ap="$ap" '$1 == "default" {for (i=1;i<=NF;i++) if ($i=="dev" && $(i+1)!=ap) {print $(i+1); exit}}'
}

remember_forwarding() {
    iface=$1
    file="/proc/sys/net/ipv4/conf/$iface/forwarding"
    [ -r "$file" ] || return 0
    grep -q "^$iface=" "$FORWARD_FILE" 2>/dev/null || printf '%s=%s\n' "$iface" "$(sed -n '1p' "$file")" >> "$FORWARD_FILE"
    printf '1\n' > "$file"
}

setup_forwarding() {
    ap=$(ap_iface)
    route_if=$(default_route_iface 2>/dev/null || true)
    [ -n "$route_if" ] || { teardown_forwarding || return 1; return 0; }
    nft=$(nft_bin 2>/dev/null || true)
    [ -n "$nft" ] || { teardown_forwarding || return 1; log_event "routing disabled: nft not found"; return 0; }
    remember_forwarding "$ap"
    remember_forwarding "$route_if"
    "$nft" delete table inet "$NFT_TABLE" >/dev/null 2>&1 || true
    "$nft" add table inet "$NFT_TABLE" || return 1
    "$nft" "add chain inet $NFT_TABLE forward { type filter hook forward priority -10; policy accept; }" || return 1
    "$nft" add rule inet "$NFT_TABLE" forward iifname "$ap" oifname "$ap" drop || return 1
    "$nft" add rule inet "$NFT_TABLE" forward iifname "$ap" oifname "$route_if" accept || return 1
    "$nft" add rule inet "$NFT_TABLE" forward iifname "$route_if" oifname "$ap" ct state established,related accept || return 1
    "$nft" add rule inet "$NFT_TABLE" forward iifname "$ap" drop || return 1
    "$nft" add rule inet "$NFT_TABLE" forward oifname "$ap" drop || return 1
    "$nft" "add chain inet $NFT_TABLE postrouting { type nat hook postrouting priority srcnat; policy accept; }" || return 1
    network=$(printf '%s\n' "$LAN_CIDR" | awk -F'[./]' '{printf "%s.%s.%s.0/24",$1,$2,$3}')
    "$nft" add rule inet "$NFT_TABLE" postrouting ip saddr "$network" oifname "$route_if" masquerade || return 1
    printf '%s\n' "$route_if" > "$ROUTE_FILE"
}

teardown_forwarding() {
    rc=0
    nft=$(nft_bin 2>/dev/null || true)
    if [ -n "$nft" ]; then
        if "$nft" list table inet "$NFT_TABLE" >/dev/null 2>&1; then
            "$nft" delete table inet "$NFT_TABLE" >/dev/null 2>&1 || rc=1
        fi
    elif [ -s "$ROUTE_FILE" ]; then
        rc=1
    fi
    if [ -r "$FORWARD_FILE" ]; then
        while IFS='=' read -r iface value; do
            case "$iface" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
            case "$value" in 0|1) ;; *) continue ;; esac
            file="/proc/sys/net/ipv4/conf/$iface/forwarding"
            if [ -e "$file" ]; then
                [ -w "$file" ] && printf '%s\n' "$value" > "$file" || rc=1
            fi
        done < "$FORWARD_FILE"
    fi
    if [ "$rc" -eq 0 ]; then
        rm -f "$FORWARD_FILE" "$ROUTE_FILE"
    fi
    return "$rc"
}

cleanup_private() {
    rc=0
    stop_pid "$HOSTAPD_PID" hostapd || rc=1
    stop_pid "$DNSMASQ_PID" dnsmasq || rc=1
    teardown_forwarding || rc=1
    ap=$(ap_iface)
    if [ -f "$OWNED_FILE" ] && ip link show "$ap" >/dev/null 2>&1; then
        ip link set "$ap" down >/dev/null 2>&1 || true
        iw dev "$ap" del >/dev/null 2>&1 || true
    fi
    if [ -f "$OWNED_FILE" ] && ip link show "$ap" >/dev/null 2>&1; then
        rc=1
    else
        rm -f "$OWNED_FILE"
    fi
    if ! pid_matches "$HOSTAPD_PID" hostapd && ! pid_matches "$DNSMASQ_PID" dnsmasq; then
        rm -f "$HOSTAPD_CONF" "$LEASE_FILE"
    fi
    return "$rc"
}

apply_plan() {
    plan=$1
    oldifs=$IFS; IFS='|'; set -- $plan; IFS=$oldifs
    uplink=$1; phy=$2; channel=$3; freq=$4; band=$5; hw=$6; source=$7
    : "$freq"
    ap=$(ap_iface)
    phase=UPLINK
    [ "$source" = uplink ] || phase=STANDALONE
    write_state bypass RECONFIGURING "$uplink" "$phy" "$channel" "$band" "$source" "$ap" || return 1
    stop_pid "$HOSTAPD_PID" hostapd || return 1
    ensure_ap_interface "$phy" || return 1
    start_hostapd "$channel" "$hw" || return 1
    start_dnsmasq || return 1
    if ! setup_forwarding; then
        log_event "routing unavailable; private LAN remains local"
        teardown_forwarding || return 1
    fi
    write_state bypass "$phase" "$uplink" "$phy" "$channel" "$band" "$source" "$ap" || return 1
    log_event "LAN started: band=$band channel=$channel source=$source"
}

start_private() {
    ensure_identity || return 1
    plan=$(radio_plan) || return 1
    if ! apply_plan "$plan"; then
        log_event "error starting private LAN; rolling back"
        cleanup_private
        return 1
    fi
}

nm_state_number() {
    command -v nmcli >/dev/null 2>&1 || return 1
    value=$(LC_ALL=C nmcli -g GENERAL.STATE device show "$1" 2>/dev/null | sed -n '1p')
    value=${value%% *}
    case "$value" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' "$value"
}

watch_loop() {
    require_root
    ensure_dirs
    printf '%s\n' "$$" > "$WATCH_PID"
    trap 'release_lock; rm -f "$WATCH_PID"' EXIT
    trap 'exit 0' HUP INT TERM
    paused=0
    connecting_since=0
    no_uplink_since=0
    stable_channel=
    stable_count=0
    retry_after=0
    association_timed_out=0
    missing_since=0

    while [ "$(state_get EFFECTIVE_MODE 2>/dev/null || true)" = bypass ]; do
        sleep 1
        managed=$(find_managed_iface 2>/dev/null || true)
        now=$(date +%s)
        if [ -z "$managed" ]; then
            [ "$missing_since" -ne 0 ] || missing_since=$now
            if [ $((now - missing_since)) -ge "$NO_UPLINK_GRACE" ] && pid_matches "$HOSTAPD_PID" hostapd; then
                acquire_lock || continue
                cleanup_private || log_event "error cleaning unavailable Wi-Fi interface"
                write_state bypass RECONFIGURING "" "" "" "" missing "$(ap_iface)" || true
                release_lock
                log_event "Wi-Fi interface unavailable; private LAN paused"
            fi
            continue
        fi
        missing_since=0
        info=$(connected_radio_info "$managed" 2>/dev/null || true)

        route_if=$(default_route_iface 2>/dev/null || true)
        configured_route=$(sed -n '1p' "$ROUTE_FILE" 2>/dev/null || true)
        if pid_matches "$HOSTAPD_PID" hostapd && [ -n "$(nft_bin 2>/dev/null || true)" ] \
            && [ "$route_if" != "$configured_route" ]; then
            acquire_lock || continue
            if ! teardown_forwarding; then
                log_event "error removing previous routing"
                release_lock
                continue
            fi
            setup_forwarding || { log_event "error updating routing"; teardown_forwarding; }
            release_lock
            log_event "routing updated: interface=${route_if:-none}"
        fi

        if [ -n "$info" ]; then
            no_uplink_since=0
            connecting_since=0
            association_timed_out=0
            oldifs=$IFS; IFS='|'; set -- $info; IFS=$oldifs
            iface=$1; phy=$2; channel=$3; freq=$4; band=$5; hw=$6
            : "$freq"
            if [ "$stable_channel" = "$channel" ]; then stable_count=$((stable_count + 1)); else stable_channel=$channel; stable_count=1; fi
            [ "$stable_count" -ge "$STABLE_SAMPLES" ] || continue
            current=$(state_get CHANNEL 2>/dev/null || true)
            source=$(state_get SOURCE 2>/dev/null || true)
            old_uplink=$(state_get UPLINK 2>/dev/null || true)
            old_phy=$(state_get PHY 2>/dev/null || true)
            if [ "$paused" -eq 1 ] || [ "$channel" != "$current" ] || [ "$source" != uplink ] \
                || [ "$iface" != "$old_uplink" ] || [ "$phy" != "$old_phy" ] \
                || ! pid_matches "$HOSTAPD_PID" hostapd || ! pid_matches "$DNSMASQ_PID" dnsmasq; then
                [ "$now" -ge "$retry_after" ] || continue
                acquire_lock || continue
                plan="$iface|$phy|$channel|$freq|$band|$hw|uplink"
                if apply_plan "$plan"; then
                    log_event "new uplink stable: band=$band channel=$channel"
                    paused=0
                else
                    log_event "error reconfiguring AP for uplink"
                    retry_after=$((now + 5))
                fi
                release_lock
            fi
            continue
        fi

        nmstate=$(nm_state_number "$managed" 2>/dev/null || true)
        case "$nmstate" in
            40|50|60|70|80|90)
                [ "$association_timed_out" -eq 0 ] || continue
                if [ "$paused" -eq 0 ]; then
                    acquire_lock || continue
                    write_state bypass CONNECTING "$managed" "$(iface_phy "$managed" 2>/dev/null || true)" "" "" connecting "$(ap_iface)"
                    if ! stop_pid "$HOSTAPD_PID" hostapd; then
                        release_lock
                        log_event "error pausing private AP"
                        continue
                    fi
                    release_lock
                    log_event "association detected: private AP paused"
                    paused=1
                    connecting_since=$now
                    stable_channel=
                    stable_count=0
                fi
                [ "$connecting_since" -gt 0 ] && [ $((now - connecting_since)) -lt "$CONNECT_TIMEOUT" ] && continue
                log_event "association timed out; entering standalone"
                association_timed_out=1
                no_uplink_since=$((now - NO_UPLINK_GRACE))
                ;;
            *) connecting_since=0; association_timed_out=0 ;;
        esac

        if [ "$no_uplink_since" -eq 0 ]; then
            no_uplink_since=$now
            log_event "uplink lost; debounce ${NO_UPLINK_GRACE}s"
        fi
        [ $((now - no_uplink_since)) -ge "$NO_UPLINK_GRACE" ] || continue
        phy=$(iface_phy "$managed" 2>/dev/null || true)
        [ -n "$phy" ] || continue
        channel=$(choose_standalone_channel "$phy" 2>/dev/null || true)
        [ -n "$channel" ] || continue
        if [ "$channel" -le 14 ]; then band=2.4; hw=g; else band=5; hw=a; fi
        source=$(state_get SOURCE 2>/dev/null || true)
        current=$(state_get CHANNEL 2>/dev/null || true)
        if [ "$paused" -eq 1 ] || [ "$source" != standalone ] || [ "$current" != "$channel" ] \
            || ! pid_matches "$HOSTAPD_PID" hostapd || ! pid_matches "$DNSMASQ_PID" dnsmasq; then
            [ "$now" -ge "$retry_after" ] || continue
            acquire_lock || continue
            if apply_plan "$managed|$phy|$channel|0|$band|$hw|standalone"; then
                log_event "standalone active: band=$band channel=$channel"
                paused=0
                no_uplink_since=$now
            else
                log_event "error restoring standalone LAN"
                retry_after=$((now + 5))
            fi
            release_lock
        fi
    done
}

start_watch() {
    pid_matches "$WATCH_PID" _watch && return 0
    self=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
    nohup "$self" _watch >> "$LOG_FILE" 2>&1 &
    printf '%s\n' "$!" > "$WATCH_PID"
}

stop_watch() {
    stop_pid "$WATCH_PID" _watch
}

start_current() {
    stop_watch
    cleanup_private
    route_if=$(default_route_iface 2>/dev/null || true)
    write_state current UPLINK "$route_if" "" "" "" current "" || return 1
    log_event "current network mode active: interface=${route_if:-none}"
}

live_ap_radio() {
    ap=$(state_get AP_IF 2>/dev/null || ap_iface)
    line=$(iw dev "$ap" info 2>/dev/null | awk '/^[[:space:]]*channel [0-9]+ / { sub(/^[[:space:]]*/, ""); print; exit }')
    [ -n "$line" ] || return 1
    channel=$(printf '%s\n' "$line" | awk '{print $2}')
    freq=$(printf '%s\n' "$line" | sed -n 's/.*(\([0-9][0-9]*\) MHz).*/\1/p')
    case "$freq" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$freq" -lt 3000 ]; then band=2.4; elif [ "$freq" -lt 5925 ]; then band=5; else band=6; fi
    printf '%s|%s\n' "$channel" "$band"
}

live_ap_ssid() {
    sed -n 's/^ssid=//p' "$HOSTAPD_CONF" 2>/dev/null | sed -n '1p'
}

live_clients() {
    ap=$(state_get AP_IF 2>/dev/null || ap_iface)
    iw dev "$ap" station dump 2>/dev/null | awk '$1 == "Station" {count++} END {print count+0}'
}

internet_state() {
    effective=$1
    route_if=$(default_route_iface 2>/dev/null || true)
    [ -n "$route_if" ] || { printf 'unavailable\n'; return; }
    connectivity=$(LC_ALL=C nmcli -t -f CONNECTIVITY general 2>/dev/null | sed -n '1p' || true)
    [ "$connectivity" = full ] || { printf 'unavailable\n'; return; }
    if [ "$effective" = bypass ]; then
        nft=$(nft_bin 2>/dev/null || true)
        configured_route=$(sed -n '1p' "$ROUTE_FILE" 2>/dev/null || true)
        ap=$(ap_iface)
        ap_forward=$(sed -n '1p' "/proc/sys/net/ipv4/conf/$ap/forwarding" 2>/dev/null || true)
        route_forward=$(sed -n '1p' "/proc/sys/net/ipv4/conf/$route_if/forwarding" 2>/dev/null || true)
        [ "$configured_route" = "$route_if" ] && [ "$ap_forward" = 1 ] && [ "$route_forward" = 1 ] \
            && [ -n "$nft" ] && "$nft" list table inet "$NFT_TABLE" >/dev/null 2>&1 \
            && printf 'shared\n' || printf 'unavailable\n'
    else
        printf 'current\n'
    fi
}

cmd_configure() {
    require_root
    acquire_lock
    trap 'release_lock' EXIT
    trap 'release_lock; exit 129' HUP
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM
    set_mode "$1"
    release_lock
    trap - EXIT HUP INT TERM
    printf 'mode=%s\n' "$(get_mode)"
}

cmd_start() {
    require_root
    need_cmd iw; need_cmd ip
    acquire_lock
    trap 'release_lock' EXIT
    trap 'release_lock; exit 129' HUP
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM
    requested=$(normalize_mode "${1:-$(get_mode)}") || { release_lock; err "modo inválido"; exit 2; }
    set_mode "$requested"
    stop_watch
    cleanup_private
    case "$requested" in
        current) start_current ;;
        bypass)
            need_cmd hostapd; need_cmd dnsmasq
            if ! start_private; then release_lock; exit 1; fi
            start_watch
            ;;
        auto)
            if command -v hostapd >/dev/null 2>&1 && command -v dnsmasq >/dev/null 2>&1 && start_private; then
                start_watch
                log_event "automatic selected private LAN"
            else
                cleanup_private
                start_current
                log_event "automatic fallback to current network"
            fi
            ;;
    esac
    release_lock
    trap - EXIT HUP INT TERM
    cmd_status
}

cmd_stop() {
    require_root
    acquire_lock
    trap 'release_lock' EXIT
    trap 'release_lock; exit 129' HUP
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM
    stop_watch
    cleanup_private
    rm -f "$STATE_FILE"
    log_event "network stopped"
    release_lock
    trap - EXIT HUP INT TERM
    printf 'enabled=0\n'
}

cmd_status() {
    require_root
    requested=$(get_mode)
    effective=$(state_get EFFECTIVE_MODE 2>/dev/null || true)
    [ -n "$effective" ] || effective=stopped
    phase=$(state_get PHASE 2>/dev/null || true)
    enabled=0
    [ "$effective" = stopped ] || enabled=1
    printf 'enabled=%s\nmode=%s\neffective_mode=%s\nstate=%s\n' "$enabled" "$requested" "$effective" "${phase:-STOPPED}"
    if [ "$effective" = bypass ]; then
        ap=$(state_get AP_IF 2>/dev/null || ap_iface)
        active=0
        radio=$(live_ap_radio 2>/dev/null || true)
        pid_matches "$HOSTAPD_PID" hostapd && pid_matches "$DNSMASQ_PID" dnsmasq \
            && [ -n "$(lan_address 2>/dev/null || true)" ] && [ -n "$radio" ] && active=1
        channel=; band=
        if [ -n "$radio" ]; then oldifs=$IFS; IFS='|'; set -- $radio; IFS=$oldifs; channel=$1; band=$2; fi
        printf 'lan_active=%s\ninterface=%s\nssid=%s\nip=%s\n' "$active" "$ap" "$(live_ap_ssid)" "$(lan_address 2>/dev/null || true)"
        printf 'uplink=%s\nband=%s\nchannel=%s\nsource=%s\nclients=%s\nwatch=%s\n' \
            "$(state_get UPLINK 2>/dev/null || true)" "$band" "$channel" "$(state_get SOURCE 2>/dev/null || true)" \
            "$(live_clients)" "$(pid_matches "$WATCH_PID" _watch && printf 1 || printf 0)"
    elif [ "$effective" = current ]; then
        iface=$(default_route_iface 2>/dev/null || true)
        address=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}' || true)
        printf 'lan_active=0\ninterface=%s\naddress=%s\nclients=0\nwatch=0\n' "$iface" "$address"
    else
        printf 'lan_active=0\nclients=0\nwatch=0\n'
    fi
    printf 'internet=%s\n' "$(internet_state "$effective")"
}

cmd_secret() {
    require_root
    field=${1:-}
    effective=$(state_get EFFECTIVE_MODE 2>/dev/null || true)
    [ "$effective" = bypass ] || return 1
    case "$field" in
        host) value=$(lan_address 2>/dev/null || true) ;;
        password) value=$(sed -n 's/^wpa_passphrase=//p' "$HOSTAPD_CONF" 2>/dev/null | sed -n '1p') ;;
        *) return 2 ;;
    esac
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

cmd_log() {
    require_root
    lines=${1:-80}
    case "$lines" in ''|*[!0-9]*) return 2 ;; esac
    [ "$lines" -le 500 ] || lines=500
    [ ! -r "$LOG_FILE" ] || tail -n "$lines" "$LOG_FILE"
}

usage() {
    printf '%s\n' "usage: $0 {configure MODE|start MODE|stop|status|secret host|password|log [N]}"
}

case "${1:-}" in
    configure) [ "$#" -eq 2 ] || exit 2; cmd_configure "$2" ;;
    start) [ "$#" -eq 2 ] || exit 2; cmd_start "$2" ;;
    stop) [ "$#" -eq 1 ] || exit 2; cmd_stop ;;
    status) [ "$#" -eq 1 ] || exit 2; cmd_status ;;
    secret) [ "$#" -eq 2 ] || exit 2; cmd_secret "$2" ;;
    log) [ "$#" -le 2 ] || exit 2; cmd_log "${2:-80}" ;;
    _watch) watch_loop ;;
    *) usage >&2; exit 2 ;;
esac
