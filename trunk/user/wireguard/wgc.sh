#!/bin/sh
# padavan-ng native VPN client, adapted for Padavan 4.4 and BusyBox ash.
# SPDX-License-Identifier: GPL-2.0-or-later
. /usr/bin/wg-common.sh
IF_NAME=wg0
TABLE=51
FWMARK=51820
PREF_LOCAL=5180
PREF_WG=5182
PREF_MAIN=5181
CONF="/tmp/wg0.conf.$$"
REMOTE_NETWORK_LIST=/etc/storage/vpnc_remote_network.list
EXCLUDE_NETWORK_LIST=/etc/storage/vpnc_exclude_network.list
DOMAIN_LIST=/etc/storage/vpnc_domains.list
DOMAIN_IPSET=wgc.domains
ENDPOINT_STATE=/var/run/wgc.endpoint
ACTIVE_STATE=/var/run/wgc.active
LOCAL_RULE="^$PREF_LOCAL:[[:space:]]+from all fwmark (0xca6c|$FWMARK) lookup (main|254) suppress_prefixlength 0[[:space:]]*$"
trap 'rm -f "$CONF"' EXIT

mkdir -p /var/lock
exec 9>/var/lock/wgc_watchdog.lock
if [ "$1" = watchdog ]; then flock -n 9; else flock 9; fi || exit 1

is_started() { [ -f "$ACTIVE_STATE" ] && ip link show "$IF_NAME" 2>/dev/null | grep -Eq '<([^>]*,)?UP(,|>)'; }
set_state() { nvram settmp "vpnc_state_t=$1"; }
set_error()
{
    nvram settmp "vpnc_wg_error_t=$WG_STAGE"
    set_state 3
    # Never include configuration values or tool stderr (which can contain keys).
    wg_log "client failed at stage: $WG_STAGE"
}
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
    local i clients raw_clients default routes excluded domains
    raw_clients=$(nvram get vpnc_clients_allowed | tr ',[:space:]' '\n' | sed '/^$/d' | sort -u)
    clients=$(printf '%s\n' "$raw_clients" | filter_ipv4)
    [ "$raw_clients" = "$clients" ] || return 1
    default=$(nvram get vpnc_dgw)
    routes=$(lists "$REMOTE_NETWORK_LIST") || return 1
    routes="$routes $(nvram get vpnc_wg_peer_allowedips | tr ', ' '\n\n' | filter_ipv4)"
    excluded=$(exclusions) || return 1
    domains=
    if [ "$default" != 1 ] && [ -s "$DOMAIN_LIST" ] && grep -q '^[[:space:]]*[^#[:space:]]' "$DOMAIN_LIST"; then
        # DNSMasq populates this set from DNS replies, including subdomains.
        # IP/CIDR selectors still work on builds without IPSet.
        [ -x /sbin/ipset ] || return 1
        /sbin/ipset -exist create "$DOMAIN_IPSET" hash:ip family inet timeout 21600 || return 1
        domains=1
    fi
    {
        echo '*mangle'
        echo ':vpnc_wireguard - [0:0]'
        echo ':vpnc_wireguard_remote - [0:0]'
        echo '-A PREROUTING -i br0 -j vpnc_wireguard'
        echo '-A PREROUTING -i wg1 -j vpnc_wireguard'
        for i in $excluded; do echo "-A vpnc_wireguard -d $i -j RETURN"; done
        # Router/LAN DNS stays local via the exclusions above. Direct external
        # DNS and NTP from selected clients follow the same policy as other data.
        if [ -n "$clients" ]; then
            for i in $clients; do echo "-A vpnc_wireguard -s $i -j vpnc_wireguard_remote"; done
        else
            echo '-A vpnc_wireguard -j vpnc_wireguard_remote'
        fi
        if [ "$default" = 1 ]; then
            echo "-A vpnc_wireguard_remote -j MARK --set-mark $FWMARK"
        else
            [ -z "$domains" ] || echo "-A vpnc_wireguard_remote -m set --match-set $DOMAIN_IPSET dst -j MARK --set-mark $FWMARK"
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

ensure_routes()
{
    local family rules default
    for family in 4 6; do
        ip -$family addr show dev "$IF_NAME" scope global 2>/dev/null | grep -q 'inet' || continue
        rules=$(ip -$family rule show) || return 1
        # Retain connected/static routes before the marked VPN default. This
        # also makes strict LAN reverse-path validation resolve back to br0.
        if ! printf '%s\n' "$rules" | grep -Eq "$LOCAL_RULE"; then
            # Do not replace another service's rule using our reserved preference.
            printf '%s\n' "$rules" | grep -q "^$PREF_LOCAL:" && return 1
            ip -$family rule add fwmark "$FWMARK" table main suppress_prefixlength 0 pref "$PREF_LOCAL" || return 1
        fi
        if ! printf '%s\n' "$rules" | grep -Eq "^$PREF_WG:[[:space:]]+from all fwmark (0xca6c|$FWMARK) lookup $TABLE[[:space:]]*$"; then
            ip -$family rule add fwmark "$FWMARK" table "$TABLE" pref "$PREF_WG" || return 1
        fi
        default=0.0.0.0/0; [ "$family" != 6 ] || default=::/0
        if ! ip -$family route show table "$TABLE" exact "$default" | grep -q "^default dev $IF_NAME\([[:space:]]\|$\)"; then
            ip -$family route replace default dev "$IF_NAME" table "$TABLE" || return 1
        fi
    done
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
    if [ "$family $endpoint" = "$old_family $old_endpoint" ] &&
        ip -$family rule show to "$endpoint" table main pref "$PREF_MAIN" | grep -q .; then
        return 0
    fi
    # Install the new exception first: encrypted packets carry FWMARK too.
    ip -$family rule add to "$endpoint" table main pref "$PREF_MAIN" || return 1
    if [ -n "$old_endpoint" ] && [ "$family $endpoint" != "$old_family $old_endpoint" ]; then
        ip -$old_family rule del to "$old_endpoint" table main pref "$PREF_MAIN" 2>/dev/null
    fi
    printf '%s %s\n' "$family" "$endpoint" > "$ENDPOINT_STATE"
}

stop_wg()
{
    # Other VPN lifecycles also call stop: do not touch their DNS or routing.
    if [ ! -f "$ACTIVE_STATE" ]; then
        # A failed native start may have no interface left to clean up.
        if [ "$(nvram get vpnc_state_t)" = 3 ] && [ -n "$(nvram get vpnc_wg_error_t)" ]; then
            set_state 0
            nvram unset vpnc_wg_error_t
        fi
        return 0
    fi
    set_state 0
    nvram unset vpnc_wg_error_t
    stop_fw
    local family endpoint
    for family in 4 6; do
        if ip -$family rule show 2>/dev/null | grep -Eq "$LOCAL_RULE"; then
            ip -$family rule del fwmark "$FWMARK" table main suppress_prefixlength 0 pref "$PREF_LOCAL" 2>/dev/null
        fi
        while ip -$family rule del fwmark "$FWMARK" table "$TABLE" pref "$PREF_WG" 2>/dev/null; do :; done
        ip -$family route flush table "$TABLE" 2>/dev/null
    done
    if [ -f "$ENDPOINT_STATE" ]; then
        read -r family endpoint < "$ENDPOINT_STATE"
        ip -$family rule del to "$endpoint" table main pref "$PREF_MAIN" 2>/dev/null
    fi
    for endpoint in $(nvram get vpnc_dns_t); do
        family=4; case "$endpoint" in *:*) family=6;; esac
        while ip -$family rule del to "$endpoint" table "$TABLE" pref "$PREF_WG" 2>/dev/null; do :; done
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
    # Clean stale policy/DNS state if our interface disappeared or went down.
    [ ! -f "$ACTIVE_STATE" ] || stop_wg
    local addr mtu endpoint port private public allowed psk keepalive family i dns
    WG_STAGE=config
    nvram unset vpnc_wg_error_t
    set_state 2
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
    WG_STAGE=module
    modprobe -q "$MODULE" || return 1
    WG_STAGE=interface
    ip link add dev "$IF_NAME" type "$MODULE" || return 1
    : > "$ACTIVE_STATE" || { ip link del "$IF_NAME"; return 1; }
    ip link set dev "$IF_NAME" mtu "$mtu" || return 1
    WG_STAGE=address
    for i in $addr; do
        family=4
        case "$i" in *:*) family=6; sysctl -q -w "net.ipv6.conf.$IF_NAME.disable_ipv6=0" || return 1;; esac
        ip -$family addr add "$i" dev "$IF_NAME" || return 1
    done
    WG_STAGE=config
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
    WG_STAGE=setconf
    "$WG" setconf "$IF_NAME" "$CONF" 2>/dev/null || return 1
    rm -f "$CONF"
    WG_STAGE=link_up
    ip link set "$IF_NAME" up || return 1
    WG_STAGE=sysctl
    sysctl -q -w net.ipv4.conf.all.src_valid_mark=1 || return 1
    # Replies arrive from the tunnel, but their reverse route can use WAN.
    # Use loose validation only here; retain strict filtering on LAN and WAN.
    sysctl -q -w "net.ipv4.conf.$IF_NAME.rp_filter=2" || return 1
    WG_STAGE=endpoint
    update_endpoint_rule || return 1
    # Preserve WAN routes and local admin access; only forwarded traffic is marked.
    WG_STAGE=routes
    ensure_routes || return 1
    WG_STAGE=firewall
    start_fw || return 1
    WG_STAGE=dns
    if [ "$(nvram get vpnc_pdns)" != 0 ] && [ -n "$(nvram get vpnc_wg_if_dns)" ]; then
        dns=$(nvram get vpnc_wg_if_dns | tr ',' ' ')
        wg_single_line "$dns" || return 1
        for i in $dns; do
            family=4
            case "$i" in *:*) family=6;; *) wg_ipv4 "$i" || return 1;; esac
            ip -$family addr show dev "$IF_NAME" scope global | grep -q 'inet' || return 1
        done
        # Record all destinations before installation so failed starts clean up
        # even a partially installed DNS policy. Only publish after success.
        nvram settmp "vpnc_dns_t=$dns"
        for i in $dns; do
            family=4; case "$i" in *:*) family=6;; esac
            # Router-originated resolver traffic is not marked in PREROUTING.
            ip -$family rule add to "$i" table "$TABLE" pref "$PREF_WG" || return 1
        done
        update_resolvconf
    fi
    set_state 2
    wg_log "client started, interface: $IF_NAME, endpoint: $endpoint:$port"
    wg_post vpnc start
    return 0
}

start_client()
{
    start_wg && return 0
    stop_wg
    set_error
    return 1
}

watchdog_wg()
{
    [ "$(nvram get vpnc_enable)" = 1 ] && [ "$(nvram get vpnc_type)" = 3 ] || return 0
    if ! is_started; then
        start_client || return 1
    fi
    local last now endpoint family
    WG_STAGE=endpoint
    update_endpoint_rule || { set_error; return 1; }
    WG_STAGE=routes
    ensure_routes || { set_error; return 1; }
    WG_STAGE=dns
    for endpoint in $(nvram get vpnc_dns_t); do
        family=4; case "$endpoint" in *:*) family=6;; esac
        if ! ip -$family rule show to "$endpoint" table "$TABLE" pref "$PREF_WG" | grep -q .; then
            ip -$family rule add to "$endpoint" table "$TABLE" pref "$PREF_WG" || { set_error; return 1; }
        fi
    done
    WG_STAGE=firewall
    start_fw || { set_error; return 1; }
    nvram unset vpnc_wg_error_t
    last=$("$WG" show "$IF_NAME" latest-handshakes | awk '{print $2; exit}')
    now=$(date +%s)
    if [ "${last:-0}" -gt 0 ] && [ "$last" -le "$now" ] && [ "$((now - last))" -lt 300 ]; then
        [ "$(nvram get vpnc_state_t)" = 1 ] || wg_log 'client successfully connected'
        set_state 1
    else
        set_state 2
        # Re-resolve dynamic endpoints. Keepalive/client traffic triggers the
        # handshake; a broadcast ping is unnecessary and can hold the lock.
        endpoint=$(nvram get vpnc_wg_peer_endpoint)
        if "$WG" set "$IF_NAME" peer "$(nvram get vpnc_wg_peer_public)" \
            endpoint "$(wg_endpoint "$endpoint" "$(nvram get vpnc_wg_peer_port)")" 2>/dev/null; then
            WG_STAGE=endpoint
            update_endpoint_rule || { set_error; return 1; }
        fi
    fi
    wg_post vpnc watchdog
    return 0
}

case "$1" in
    start) start_client || exit 1;;
    stop) stop_wg;;
    restart) stop_wg; start_client || exit 1;;
    update) WG_STAGE=firewall; start_fw || { set_error; exit 1; }; wg_post vpnc update;;
    reload) WG_STAGE=firewall; stop_fw; start_fw || { set_error; exit 1; }; wg_post vpnc reload;;
    watchdog) watchdog_wg;;
    *) echo "Usage: $0 {start|stop|restart|update|reload|watchdog}" >&2; exit 1;;
esac
