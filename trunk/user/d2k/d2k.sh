#!/bin/sh
# Padavan lifecycle wrapper for the upstream D2K service.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
export D2K_DIR=/tmp/d2k D2K_RUNTIME_DIR=/tmp/d2k
export D2K_RELEASE=/usr/share/d2k D2K_CONFIG=/etc/storage/d2k/config
export D2K_MODULES_DIR=/lib/modules
export D2K_FAKE_DIR=/usr/share/d2k/files/fake
export D2K_TG_CA_BUNDLE=/usr/share/d2k/files/tg-roots.pem
export INIT_SCRIPT=/usr/bin/d2k.sh INIT=/usr/bin/d2k.sh
export FW_BACKEND=iptables D2K_FW=iptables
SERVICE=$D2K_RELEASE/d2k-service

fail() {
	logger -t d2k "$*"
	echo "d2k: $*" >&2
	exit 1
}

init_storage() {
	( umask 077
	  mkdir -p /etc/storage/d2k || exit 1
	  [ -f "$D2K_CONFIG" ] || cp "$D2K_RELEASE/config.default" "$D2K_CONFIG"
	) || fail "Cannot initialize $D2K_CONFIG"
	chmod 700 /etc/storage/d2k
	chmod 600 "$D2K_CONFIG"
}

load_modules() {
	# Load NFQUEUE before d2kd; upstream waits for its queue before loading modules.
	for m in nfnetlink nfnetlink_queue xt_NFQUEUE iptable_mangle ip6table_mangle \
		xt_connbytes xt_addrtype xt_comment nf_conntrack_netlink; do
		[ -d "/sys/module/$m" ] || modprobe -q "$m" 2>/dev/null
	done
	[ -e /proc/net/netfilter/nfnetlink_queue ] || fail "NFQUEUE is unavailable"
	if [ -x /usr/sbin/d2ktg ]; then
		modprobe -q ipt_REDIRECT 2>/dev/null
	fi
	return 0
}

enabled() {
	[ "$(nvram get d2k_enable)" = 1 ] && [ "$(nvram get sw_mode)" != 3 ]
}

case "$1" in
config)
	init_storage
	exit 0
	;;
save)
	exec /sbin/mtd_storage.sh save
	;;
start|restart|engine-start|engine-restart|reapply|heal|clear-found)
	if ! enabled; then
		case "$1" in
		restart) set -- stop ;;
		*) exit 0 ;;
		esac
	fi
	;;
telegram-enable|telegram-restart|telegram-reapply|tg-heal)
	enabled || fail "Enable D2K in the router settings first"
	[ -x /usr/sbin/d2ktg ] || fail "Telegram tunnel is not included in this firmware"
	;;
stop|status|log-tick|engine-stop|telegram-disable|tg-stop-rules|ppe-ensure) ;;
update-*) fail "D2K is updated with the firmware, not through Entware" ;;
dns-*|ppe-remove|ppe-status) fail "This Keenetic helper is not available on Padavan" ;;
*) fail "Usage: $0 {config|start|stop|restart|status|reapply|heal|engine-start|engine-stop|engine-restart|clear-found|telegram-enable|telegram-disable|telegram-restart|telegram-reapply|save}" ;;
esac

init_storage
( umask 077; mkdir -p "$D2K_DIR/run" "$D2K_DIR/log" "$D2K_DIR/state" ) || fail "Cannot initialize $D2K_DIR"
case "$1" in
stop|status|log-tick|engine-stop|telegram-disable|tg-stop-rules|ppe-ensure) ;;
*) load_modules ;;
esac
case "$1" in
telegram-enable|telegram-disable)
	# The upstream panel changes the config in tmpfs; persist explicit toggles.
	"$SERVICE" "$1" || exit $?
	exec /sbin/mtd_storage.sh save
	;;
esac
exec "$SERVICE" "$1"
