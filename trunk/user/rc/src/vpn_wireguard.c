/* Native WireGuard/AmneziaWG VPN integration, based on padavan-ng.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <stdio.h>
#include <stdlib.h>
#include "rc.h"

int start_wireguard_server(void)
{
	int ret = eval("/usr/bin/wgs.sh", "start");
	if (!ret)
		set_vpn_balancing(IFNAME_SERVER_WG, 1);
	return ret;
}

void stop_wireguard_server(void)
{
	eval("/usr/bin/wgs.sh", "stop");
}

int is_enabled_wireguard_client(void)
{
	return nvram_match("vpnc_enable", "1") && nvram_match("vpnc_type", "3");
}

int start_wireguard_client(void)
{
	int ret;
	reload_nat_modules();
	ret = eval("/usr/bin/wgc.sh", "start");
	if (!ret)
		set_vpn_balancing(IFNAME_CLIENT_WG, 0);
	return ret;
}

void stop_wireguard_client(void)
{
	eval("/usr/bin/wgc.sh", "stop");
	/* Re-enable acceleration only after the client is disabled or changed. */
	if (!is_enabled_wireguard_client())
		reload_nat_modules();
}

void update_wireguard_client(void)
{
	if (is_enabled_wireguard_client())
		eval("/usr/bin/wgc.sh", "update");
}

void watchdog_wireguard_client(void)
{
	if (is_enabled_wireguard_client())
		/* eval clears the timer handler's signal mask before starting the shell.
		 * Wait only for the launcher; init reaps the background worker. */
		eval("/bin/sh", "-c", "/usr/bin/wgc.sh watchdog &");
}

int wg_resolvconf_main(int argc, char **argv)
{
	return update_resolvconf(0, 0);
}
