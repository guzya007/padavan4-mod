#!/bin/sh
# Native VPN configuration shared with padavan-ng. SPDX-License-Identifier: GPL-2.0-or-later
umask 077
WG=/usr/bin/wg
export WG_ENDPOINT_RESOLUTION_RETRIES=0
MODULE=wireguard
[ -f "/lib/modules/$(uname -r)/kernel/net/amneziawg/amneziawg.ko" ] && MODULE=amneziawg

wg_log() { logger -t "$MODULE" "$*"; }
wg_single_line() { [ "$(printf '%s' "$1" | tr -d '\r\n')" = "$1" ]; }
wg_key_valid() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; }
wg_number()
{
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ "${#1}" -le 5 ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}
wg_host_valid()
{
    case "$1" in ''|*[!a-zA-Z0-9._:%-]*) return 1;; esac
}
wg_ipv4()
{
    printf '%s\n' "$1" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1}'
}
wg_prefix()
{
    wg_ipv4 "$1" || return 1
    printf '%s\n' "$1" | awk -F. '{ n=0; zero=0; for(i=1;i<=4;i++) { v=$i; for(b=128;b>=1;b/=2) { bit=int(v/b); v%=b; if(bit && zero) exit 1; if(bit) n++; else zero=1 } } print n }'
}

wg_awg_conf()
{
    [ "$MODULE" = amneziawg ] || return 0
    local key value
    for key in jc jmin jmax i1 i2 i3 i4 i5 h1 h2 h3 h4 s1 s2 s3 s4 \
        contentpaddingaddition headerprotectionkey rekeyaftertime rekeytimeout \
        rejectaftertime keepalivetimeout maxhandshakeattempts randomtrailers disablecookies; do
        value=$(nvram get "${1}_awg_$key")
        [ -n "$value" ] || continue
        # NVRAM data is configuration, never shell code or extra INI sections.
        wg_single_line "$value" || return 1
        printf '%s = %s\n' "$key" "$value"
    done
}

wg_endpoint()
{
    local host="$1"
    host=${host#[}; host=${host%]}
    case "$host" in *:*) host="[$host]";; esac
    printf '%s:%s\n' "$host" "$2"
}

wg_post()
{
    local script="/etc/storage/${1}_post_script.sh"
    [ -s "$script" ] && [ -x "$script" ] || return 0
    if [ "$1" = vpnc ]; then
        # Preserve padavan-ng's public event context without exporting secrets.
        MODULE="$MODULE" WG="$WG" IF_NAME="$IF_NAME" \
        IF_ADDR="$(nvram get vpnc_wg_if_addr | tr ', ' '\n\n')" \
        IF_MTU="$(nvram get vpnc_wg_mtu)" \
        IF_DNS="$(nvram get vpnc_wg_if_dns | tr ',' ' ')" \
        PEER_PORT="$(nvram get vpnc_wg_peer_port)" \
        PEER_ENDPOINT="$(nvram get vpnc_wg_peer_endpoint)" \
        PEER_ALLOWEDIPS="$(nvram get vpnc_wg_peer_allowedips | tr ',' '\n')" \
        NV_CLIENTS_LIST="$(nvram get vpnc_clients_allowed | tr ', ' '\n\n')" \
        TABLE="$TABLE" FWMARK="$FWMARK" PREF_LOCAL="$PREF_LOCAL" \
        PREF_WG="$PREF_WG" PREF_MAIN="$PREF_MAIN" DOMAIN_IPSET="$DOMAIN_IPSET" \
        "$script" "$2"
        return $?
    fi
    MODULE="$MODULE" WG="$WG" IF_NAME="$IF_NAME" "$script" "$2"
}
