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
	# Translate only comments shipped by the first Padavan version. Never source
	# or replace the user's values; the new header makes this migration one-shot.
	if grep -qxF '# D2K: /etc/storage/d2k/config. Existing settings are never overwritten.' "$D2K_CONFIG"; then
		( umask 077
		  awk '
		  BEGIN {
		    ru["# D2K: /etc/storage/d2k/config. Existing settings are never overwritten."] = "# D2K: /etc/storage/d2k/config. Сохранённые настройки не перезаписываются."
		    ru["# Apply in the router UI saves this file with the other storage settings."] = "# Кнопка «Применить» сохраняет этот файл вместе с остальными настройками."
		    ru["# After editing over SSH: /usr/bin/d2k.sh save"] = "# После редактирования через SSH: /usr/bin/d2k.sh save"
		    ru["# Use literal KEY=value assignments, not shell commands or substitutions."] = "# Используйте строки КЛЮЧ=значение, без команд оболочки и подстановок."
		    ru["# No authentication! The firmware restricts the listener to the LAN bridge."] = "# Пароля нет! Прошивка ограничивает доступ к панели мостом локальной сети LAN."
		    ru["# Volatile state avoids wearing out / overflowing the flash settings partition."] = "# Состояние хранится в ОЗУ, чтобы избежать износа и переполнения flash-памяти."
		    ru["# Optional Telegram tunnel. Uses the upstream third-party relay, not direct DPI"] = "# Необязательный туннель Telegram через сторонний ретранслятор, не прямой"
		    ru["# bypass. Disabled until explicitly enabled by the owner in the D2K panel."] = "# обход DPI. Выключен до явного включения владельцем в панели D2K."
		    ru["# Other settings use upstream defaults (PROBE_MARK, FLOWS, PORTS, CONNBYTES,"] = "# Остальные параметры используют значения D2K по умолчанию: PROBE_MARK, FLOWS,"
		    ru["# HTTP_KEEPALIVE_PORTS, VOICE_PORTS, LOGMAX, LOGKEEP, STATS_SEC)."] = "# PORTS, CONNBYTES, HTTP_KEEPALIVE_PORTS, VOICE_PORTS, LOGMAX, LOGKEEP, STATS_SEC."
		  }
		  { print ($0 in ru) ? ru[$0] : $0 }
		  ' "$D2K_CONFIG" > "$D2K_CONFIG.new.$$" &&
		  mv -f "$D2K_CONFIG.new.$$" "$D2K_CONFIG"
		) || { rm -f "$D2K_CONFIG.new.$$"; fail "Cannot translate D2K comments"; }
	fi
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
	# Persist the requested setting even if the service cannot start. Do not
	# report success when either the service or the flash save failed.
	"$SERVICE" "$1"
	rc=$?
	/sbin/mtd_storage.sh save || exit 1
	exit "$rc"
	;;
esac
exec "$SERVICE" "$1"
