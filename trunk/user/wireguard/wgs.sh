#!/bin/sh
# padavan-ng native VPN server, adapted for Padavan 4.4 and AWG 3.1.
# SPDX-License-Identifier: GPL-2.0-or-later
. /usr/bin/wg-common.sh
IF_NAME=wg1
CONF="/tmp/wg1.conf.$$"
EXPORT_CONF=/tmp/client-wg.conf
ACTIVE_STATE=/var/run/wgs.active
trap 'rm -f "$CONF"' EXIT
mkdir -p /var/lock
exec 9>/var/lock/wgs.lock
flock 9 || exit 1

is_started() { [ -f "$ACTIVE_STATE" ] && ip link show "$IF_NAME" >/dev/null 2>&1; }
stop_wg()
{
    if [ -f "$ACTIVE_STATE" ]; then
        ip link del "$IF_NAME"
        wg_log 'server stopped'
        wg_post vpns stop
    fi
    rm -f "$ACTIVE_STATE"
    return 0
}

start_wg()
{
    is_started && return 0
    local private public net addr mtu port max i key peer octet rnet rmsk prefix allowed
    private=$(nvram get vpns_wg_private)
    if [ -z "$private" ]; then
        private=$("$WG" genkey) || return 1
    fi
    wg_key_valid "$private" || return 1
    public=$(printf '%s\n' "$private" | "$WG" pubkey 2>/dev/null) || return 1
    # Never regenerate keys during stop/status/export, or log them.
    if [ "$private" != "$(nvram get vpns_wg_private)" ] || [ "$public" != "$(nvram get vpns_wg_public)" ]; then
        nvram set "vpns_wg_private=$private" && nvram set "vpns_wg_public=$public" && nvram commit || return 1
    fi
    net=$(nvram get vpns_vnet)
    addr="${net%.*}.1"
    mtu=$(nvram get vpns_wg_mtu); mtu=${mtu:-1280}
    port=$(nvram get vpns_wg_port); port=${port:-51820}
    max=$(nvram get vpns_num_x); max=${max:-0}
    wg_number "$max" 0 50 && wg_number "$mtu" 1280 1420 && wg_number "$port" 1 65535 && wg_ipv4 "$net" || return 1
    (
        echo '[Interface]'
        echo "PrivateKey = $private"
        echo "ListenPort = $port"
        wg_awg_conf vpns || exit 1
        i=0
        while [ "$i" -lt "$max" ]; do
            key=$(nvram get "vpns_pass_x$i")
            wg_key_valid "$key" || exit 1
            peer=$(printf '%s\n' "$key" | "$WG" pubkey 2>/dev/null) || exit 1
            octet=$(nvram get "vpns_addr_x$i")
            wg_number "$octet" 2 254 || exit 1
            echo '[Peer]'
            echo "PublicKey = $peer"
            allowed="${net%.*}.$octet/32"
            rnet=$(nvram get "vpns_rnet_x$i")
            rmsk=$(nvram get "vpns_rmsk_x$i")
            if [ -n "$rnet" ] && [ -n "$rmsk" ]; then
                wg_ipv4 "$rnet" || exit 1
                prefix=$(wg_prefix "$rmsk") || exit 1
                allowed="$allowed, $rnet/$prefix"
            fi
            echo "AllowedIPs = $allowed"
            i=$((i + 1))
        done
    ) > "$CONF" || return 1
    modprobe -q "$MODULE" || return 1
    ip link add dev "$IF_NAME" type "$MODULE" || return 1
    : > "$ACTIVE_STATE" || { ip link del "$IF_NAME"; return 1; }
    ip link set dev "$IF_NAME" mtu "$mtu" || return 1
    ip addr add "$addr/24" dev "$IF_NAME" || return 1
    "$WG" setconf "$IF_NAME" "$CONF" 2>/dev/null || return 1
    rm -f "$CONF"
    ip link set "$IF_NAME" up || return 1
    "$WG" show "$IF_NAME" allowed-ips | cut -f2- | tr ', ' '\n\n' | while read -r rnet; do
        [ -z "$rnet" ] || ip route add "$rnet" dev "$IF_NAME" metric 1 || exit 1
    done || return 1
    wg_log "server started, interface: $IF_NAME, address: $addr, port: $port"
    wg_post vpns start
    return 0
}

export_wg()
{
    local max i net endpoint port key public octet mtu
    max=$(nvram get vpns_num_x); max=${max:-0}
    net=$(nvram get vpns_vnet)
    endpoint=$(nvram get vpns_wg_ext_addr)
    if [ -z "$endpoint" ] && [ "$(nvram get ddns_enable_x)" = 1 ]; then
        endpoint=$(nvram get ddns_hostname_x)
    fi
    [ -n "$endpoint" ] || endpoint=$(nvram get wan0_ipaddr)
    port=$(nvram get vpns_wg_port); port=${port:-51820}
    public=$(nvram get vpns_wg_public)
    mtu=$(nvram get vpns_wg_mtu); mtu=${mtu:-1280}
    wg_number "$max" 0 50 && wg_number "$port" 1 65535 && wg_number "$mtu" 1280 1420 && wg_ipv4 "$net" || return 1
    wg_host_valid "$endpoint" && wg_key_valid "$public" || return 1
    i=0
    while [ "$i" -lt "$max" ]; do
        if [ "$(nvram get vpns_user_x$i)" = "$1" ]; then
            key=$(nvram get "vpns_pass_x$i")
            octet=$(nvram get "vpns_addr_x$i")
            wg_key_valid "$key" && wg_number "$octet" 2 254 || return 1
            (
                echo '[Interface]'
                echo "PrivateKey = $key"
                echo "Address = ${net%.*}.$octet/32"
                echo "DNS = $(nvram get lan_ipaddr)"
                echo "MTU = $mtu"
                wg_awg_conf vpns || exit 1
                echo '[Peer]'
                echo "PublicKey = $public"
                echo "Endpoint = $(wg_endpoint "$endpoint" "$port")"
                echo 'PersistentKeepalive = 25'
                echo 'AllowedIPs = 0.0.0.0/0'
            ) > "$CONF" || return 1
            mv -f "$CONF" "$EXPORT_CONF"
            return $?
        fi
        i=$((i + 1))
    done
    return 1
}

list_wg()
{
    # No private keys: machine-readable per-peer handshake/traffic status.
    "$WG" show "$IF_NAME" dump | awk 'NR>1 { print $4, $3, $5, $6, $7 }'
}

case "$1" in
    start) start_wg || { stop_wg; wg_log 'server startup failed'; exit 1; };;
    stop) stop_wg;;
    restart) stop_wg; start_wg || { stop_wg; exit 1; };;
    export)
        if [ -n "$3" ]; then
            case "$3" in /tmp/client-wg.*) EXPORT_CONF="$3";; *) exit 1;; esac
            case "${3#/tmp/client-wg.}" in ''|*/*|*[!a-zA-Z0-9._-]*) exit 1;; esac
        fi
        export_wg "$2";;
    status) is_started;;
    list) list_wg;;
    *) echo "Usage: $0 {start|stop|restart|status|list|export <client>}" >&2; exit 1;;
esac
