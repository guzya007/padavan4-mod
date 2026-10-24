#!/bin/sh
# One local proxy per upstream, as in padavan-ng. DNSMasq owns the DNS cache.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
BIN=/usr/sbin/https_dns_proxy

stop_service() {
	killall -q https_dns_proxy 2>/dev/null
	# Termination is asynchronous; do not race a new listener against old sockets.
	i=0
	while pidof https_dns_proxy >/dev/null && [ "$i" -lt 3 ]; do
		sleep 1
		i=$((i + 1))
	done
	if pidof https_dns_proxy >/dev/null; then
		killall -q -9 https_dns_proxy 2>/dev/null
	fi
	return 0
}

start_service() {
	[ "$(nvram get doh_enable)" = 1 ] || return 0
	[ "$(nvram get sw_mode)" != 3 ] || return 0
	pidof https_dns_proxy >/dev/null && return 0
	port=$(nvram get doh_listen_port)
	case "$port" in ''|*[!0-9]*) return 1 ;; esac
	while [ "${port#0}" != "$port" ]; do port=${port#0}; done
	[ -n "$port" ] && [ "${#port}" -le 5 ] || return 1
	[ "$port" -ge 1024 ] && [ "$port" -le 65530 ] || return 1
	addr=127.0.0.1
	case "$(nvram get doh_listen_mode)" in
	1) addr=$(nvram get lan_ipaddr) ;;
	2) addr=0.0.0.0 ;;
	esac
	bootstrap=$(nvram get doh_bootstrap_dns)
	# Do not resolve upstream names through ourselves during bootstrap.
	[ -n "$bootstrap" ] || bootstrap=1.1.1.1,8.8.8.8
	started=0
	for i in 0 1 2 3; do
		server=$(nvram get "doh_server$i")
		case "$server" in https://?*) ;; *) continue ;; esac
		if "$BIN" -p "$((port + i))" -r "$server" -b "$bootstrap" \
			-a "$addr" -u nobody -g nogroup -4 -d; then
			started=$((started + 1))
		fi
	done
	[ "$started" -gt 0 ] || return 1
	logger -t https_dns_proxy "Started $started resolver(s) on $addr:$port"
}

case "$1" in
start) start_service ;;
stop) stop_service ;;
restart) stop_service; start_service ;;
*) echo "Usage: $0 {start|stop|restart}" >&2; exit 1 ;;
esac
