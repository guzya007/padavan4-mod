#!/bin/sh
# padavan-ng native VPN client, adapted for Padavan 4.4 and BusyBox ash.
# SPDX-License-Identifier: GPL-2.0-or-later
. /usr/bin/wg-common.sh
IF_NAME=wg0
TABLE=51
FWMARK=51820
PREF_WG=5182
PREF_MAIN=5181
CONF="/tmp/wg0.conf.$$"
REMOTE_NETWORK_LIST=/etc/storage/vpnc_remote_network.list
EXCLUDE_NETWORK_LIST=/etc/storage/vpnc_exclude_network.list
ENDPOINT_STATE=/var/run/wgc.endpoint
ACTIVE_STATE=/var/run/wgc.active
trap 'rm -f "$CONF"' EXIT

mkdir -p /var/lock
exec 9>/var/lock/wgc_watchdog.lock
if [ "$1" = watchdog ]; then flock -n 9; else flock 9; fi || exit 1

is_started() { [ -f "$ACTIVE_STATE" ] && ip link show "$IF_NAME" >/dev/null 2>&1; }
set_state() { nvram settmp "vpnc_state_t=$1"; }
filter_ipv4()
{
    awk '{ n=split($0,p,"/"); if(n>2 || (n==2 && (p[2] !~ /^[0-9]+$/ || p[2]>32))) next;
        if(split(p[1],a,".")!=4) next; valid=1;
        for(i=1;i<=4;i++) if(a[i] !~ /^[0-9]+$/ || a[i]>255) valid=0;
        if(valid) print }' | sort -u
}
lists()
{
    [ -f "$1" ] || return 0
    local raw valid
    raw=$(sed 's/#.*//' "$1" | tr ',[:space:]' '\n' | sed '/^$/d' | sort -u)
    valid=$(printf '%s\n' "$raw" | filter_ipv4)
    [ "$raw" = "$valid" ] || return 1
    printf '%s\n' "$valid"
}
exclusions()
{
    printf '%s\n' 0.0.0.0/8 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4 240.0.0.0/4 \
        "$(nvram get lan_ipaddr)/$(wg_prefix "$(nvram get lan_netmask)")" "$(nvram get vpns_vnet)/24" | filter_ipv4
    lists "$EXCLUDE_NETWORK_LIST"
}

stop_fw()
{
    local ipt
    for ipt in iptables ip6tables; do
        while "$ipt" -t mangle -D PREROUTING -i br0 -j vpnc_wireguard 2>/dev/null; do :; done
        while "$ipt" -t mangle -D PREROUTING -i wg1 -j vpnc_wireguard 2>/dev/null; do :; done
        "$ipt" -t mangle -F vpnc_wireguard 2>/dev/null
        "$ipt" -t mangle -F vpnc_wireguard_remote 2>/dev/null
        "$ipt" -t mangle -X vpnc_wireguard 2>/dev/null
        "$ipt" -t mangle -X vpnc_wireguard_remote 2>/dev/null
    done
    return 0
}

start_fw()
{
    is_started || return 0
    iptables -t mangle -nL vpnc_wireguard >/dev/null 2>&1 && return 0
    local i clients raw_clients default routes excluded
    raw_clients=$(nvram get vpnc_clients_allowed | tr ',[:space:]' '\n' | sed '/^$/d' | sort -u)
    clients=$(printf '%s\n' "$raw_clients" | filter_ipv4)
    [ "$raw_clients" = "$clients" ] || return 1
    default=$(nvram get vpnc_dgw)
    routes=$(lists "$REMOTE_NETWORK_LIST") || return 1
    routes="$routes $(nvram get vpnc_wg_peer_allowedips | tr ', ' '\n\n' | filter_ipv4)"
    excluded=$(exclusions) || return 1
    # This uses no IPSet; existing NEWIFI3 IPSET=n remains unchanged.
    {
        echo '*mangle'
        echo ':vpnc_wireguard - [0:0]'
        echo ':vpnc_wireguard_remote - [0:0]'
        echo '-A PREROUTING -i br0 -j vpnc_wireguard'
        echo '-A PREROUTING -i wg1 -j vpnc_wireguard'
        for i in $excluded; do echo "-A vpnc_wireguard -d $i -j RETURN"; done
        for i in 53 123; do
            echo "-A vpnc_wireguard -p udp --dport $i -j RETURN"
        done
        echo '-A vpnc_wireguard -p tcp --dport 53 -j RETURN'
        if [ -n "$clients" ]; then
            for i in $clients; do echo "-A vpnc_wireguard -s $i -j vpnc_wireguard_remote"; done
        else
            echo '-A vpnc_wireguard -j vpnc_wireguard_remote'
        fi
        if [ "$default" = 1 ]; then
            echo "-A vpnc_wireguard_remote -j MARK --set-mark $FWMARK"
        else
            for i in $routes; do
                [ "$i" = 0.0.0.0/0 ] && continue
                echo "-A vpnc_wireguard_remote -d $i -j MARK --set-mark $FWMARK"
            done
        fi
        echo COMMIT
    } | iptables-restore -n || { stop_fw; return 1; }
    # IPv4 client selectors do not implicitly select IPv6 clients.
    if [ -z "$clients" ] && ip -6 addr show dev "$IF_NAME" scope global | grep -q 'inet6 '; then
        ip6tables -t mangle -N vpnc_wireguard || { stop_fw; return 1; }
        ip6tables -t mangle -A PREROUTING -i br0 -j vpnc_wireguard || { stop_fw; return 1; }
        # Keep LAN prefixes local, including globally routed and ULA networks.
        for i in ::/128 ::1/128 fe80::/10 ff00::/8 \
            $(ip -6 route show table main dev br0 | awk '$1 ~ /:/ {print $1}'); do
            ip6tables -t mangle -A vpnc_wireguard -d "$i" -j RETURN || { stop_fw; return 1; }
        done
        for i in $(nvram get vpnc_wg_peer_allowedips | tr ', ' '\n\n'); do
            case "$i" in
                ::/0) [ "$default" = 1 ] || continue;;
                *:*) :;;
                *) continue;;
            esac
            ip6tables -t mangle -A vpnc_wireguard -d "$i" -j MARK --set-mark "$FWMARK" || { stop_fw; return 1; }
        done
    fi
    return 0
}

update_endpoint_rule()
{
    local endpoint family old_family old_endpoint
    endpoint=$("$WG" show "$IF_NAME" endpoints | awk '{print $2; exit}' | sed 's/:[0-9]*$//; s/[][]//g')
    [ -n "$endpoint" ] && [ "$endpoint" != '(none)' ] || return 1
    family=4; case "$endpoint" in *:*) family=6;; esac
    old_family=; old_endpoint=
    [ ! -f "$ENDPOINT_STATE" ] || read -r old_family old_endpoint < "$ENDPOINT_STATE"
    [ "$family $endpoint" != "$old_family $old_endpoint" ] || return 0
    # Install the new exception first: encrypted packets carry FWMARK too.
    ip -$family rule add to "$endpoint" table main pref "$PREF_MAIN" || return 1
    if [ -n "$old_endpoint" ]; then
        ip -$old_family rule del to "$old_endpoint" table main pref "$PREF_MAIN" 2>/dev/null
    fi
    printf '%s %s\n' "$family" "$endpoint" > "$ENDPOINT_STATE"
}

stop_wg()
{
    # Other VPN lifecycles also call stop: do not touch their DNS or routing.
    [ -f "$ACTIVE_STATE" ] || return 0
    set_state 0
    stop_fw
    local family
    for family in 4 6; do
        while ip -$family rule del pref "$PREF_WG" 2>/dev/null; do :; done
        while ip -$family rule del pref "$PREF_MAIN" 2>/dev/null; do :; done
        ip -$family route flush table "$TABLE" 2>/dev/null
    done
    rm -f "$ENDPOINT_STATE"
    if [ -f "$ACTIVE_STATE" ]; then
        ip link del "$IF_NAME"
        wg_log "client stopped"
        wg_post vpnc stop
    fi
    rm -f "$ACTIVE_STATE"
    if [ -n "$(nvram get vpnc_dns_t)" ]; then
        nvram unset vpnc_dns_t
        update_resolvconf
    fi
    return 0
}

start_wg()
{
    is_started && return 0
    local addr mtu endpoint port private public allowed psk keepalive family i dns
    addr=$(nvram get vpnc_wg_if_addr | tr ', ' '\n\n')
    mtu=$(nvram get vpnc_wg_mtu); mtu=${mtu:-1280}
    endpoint=$(nvram get vpnc_wg_peer_endpoint)
    port=$(nvram get vpnc_wg_peer_port)
    private=$(nvram get vpnc_wg_if_private)
    public=$(nvram get vpnc_wg_peer_public)
    allowed=$(nvram get vpnc_wg_peer_allowedips)
    psk=$(nvram get vpnc_wg_if_preshared)
    keepalive=$(nvram get vpnc_wg_peer_keepalive); keepalive=${keepalive:-25}
    [ -n "$addr" ] && [ -n "$private" ] && [ -n "$public" ] && [ -n "$endpoint" ] && [ -n "$allowed" ] || return 1
    # Reject line injection from NVRAM before writing keys/endpoints as INI data.
    for i in "$private" "$public" "$endpoint" "$port" "$allowed" "$psk" "$keepalive"; do
        wg_single_line "$i" || return 1
    done
    wg_key_valid "$private" && wg_key_valid "$public" || return 1
    [ -z "$psk" ] || wg_key_valid "$psk" || return 1
    wg_host_valid "$endpoint" && wg_number "$port" 1 65535 && wg_number "$mtu" 1280 1420 && wg_number "$keepalive" 0 65535 || return 1
    modprobe -q "$MODULE" || return 1
    ip link add dev "$IF_NAME" type "$MODULE" || return 1
    : > "$ACTIVE_STATE" || { ip link del "$IF_NAME"; return 1; }
    ip link set dev "$IF_NAME" mtu "$mtu" || return 1
    for i in $addr; do
        family=4
        case "$i" in *:*) family=6; sysctl -q "net.ipv6.conf.$IF_NAME.disable_ipv6=0" || return 1;; esac
        ip -$family addr add "$i" dev "$IF_NAME" || return 1
    done
    (
        echo '[Interface]'
        echo "PrivateKey = $private"
        echo "FwMark = $FWMARK"
        wg_awg_conf vpnc || exit 1
        echo '[Peer]'
        echo "PublicKey = $public"
        [ -z "$psk" ] || echo "PresharedKey = $psk"
        echo "Endpoint = $(wg_endpoint "$endpoint" "$port")"
        echo "AllowedIPs = $allowed"
        echo "PersistentKeepalive = $keepalive"
    ) > "$CONF" || return 1
    # wg can include a malformed secret key in its diagnostics.
    "$WG" setconf "$IF_NAME" "$CONF" 2>/dev/null || return 1
    rm -f "$CONF"
    ip link set "$IF_NAME" up || return 1
    sysctl -q net.ipv4.conf.all.src_valid_mark=1 || return 1
    update_endpoint_rule || return 1
    # Preserve WAN routes and local admin access; only forwarded traffic is marked.
    for family in 4 6; do
        ip -$family addr show dev "$IF_NAME" scope global | grep -q 'inet' || continue
        ip -$family rule add fwmark "$FWMARK" table "$TABLE" pref "$PREF_WG" || return 1
        ip -$family route replace default dev "$IF_NAME" table "$TABLE" || return 1
    done
    start_fw || return 1
    if [ "$(nvram get vpnc_pdns)" != 0 ] && [ -n "$(nvram get vpnc_wg_if_dns)" ]; then
        dns=$(nvram get vpnc_wg_if_dns | tr ',' ' ')
        wg_single_line "$dns" || return 1
        for i in $dns; do
            family=4
            case "$i" in *:*) family=6;; *) wg_ipv4 "$i" || return 1;; esac
            ip -$family addr show dev "$IF_NAME" scope global | grep -q 'inet' || return 1
            # Router-originated resolver traffic is not marked in PREROUTING.
            ip -$family rule add to "$i" table "$TABLE" pref "$PREF_WG" || return 1
        done
        nvram settmp "vpnc_dns_t=$dns"
        update_resolvconf
    fi
    set_state 2
    wg_log "client started, interface: $IF_NAME, endpoint: $endpoint:$port"
    wg_post vpnc start
    return 0
}

watchdog_wg()
{
    [ "$(nvram get vpnc_enable)" = 1 ] && [ "$(nvram get vpnc_type)" = 3 ] || return 0
    if ! is_started; then
        start_wg || { stop_wg; return 1; }
    fi
    local last now endpoint
    update_endpoint_rule || return 1
    last=$("$WG" show "$IF_NAME" latest-handshakes | awk '{print $2; exit}')
    now=$(date +%s)
    if [ "${last:-0}" -gt 0 ] && [ "$((now - last))" -lt 300 ]; then
        [ "$(nvram get vpnc_state_t)" = 1 ] || wg_log 'client successfully connected'
        set_state 1
    else
        set_state 2
        # Re-resolve dynamic endpoints and trigger a handshake without blocking rc.
        endpoint=$(nvram get vpnc_wg_peer_endpoint)
        if "$WG" set "$IF_NAME" peer "$(nvram get vpnc_wg_peer_public)" \
            endpoint "$(wg_endpoint "$endpoint" "$(nvram get vpnc_wg_peer_port)")" 2>/dev/null; then
            update_endpoint_rule || return 1
        fi
        ping -c 1 -W 1 -I "$IF_NAME" 255.255.255.255 >/dev/null 2>&1
    fi
    wg_post vpnc watchdog
    return 0
}

case "$1" in
    start) start_wg || { stop_wg; wg_log 'client startup failed'; exit 1; };;
    stop) stop_wg;;
    restart) stop_wg; start_wg || { stop_wg; exit 1; };;
    update) start_fw || exit 1; wg_post vpnc update;;
    reload) stop_fw; start_fw || exit 1; wg_post vpnc reload;;
    watchdog) watchdog_wg;;
    *) echo "Usage: $0 {start|stop|restart|update|reload|watchdog}" >&2; exit 1;;
esac
