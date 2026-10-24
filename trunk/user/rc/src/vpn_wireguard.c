/* Native WireGuard/AmneziaWG VPN integration, based on padavan-ng.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
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
	/* Restore software acceleration after the client is disabled or changed. */
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

#if defined(USE_IPSET)
static int wg_domain_valid(const char *domain)
{
	const unsigned char *p = (const unsigned char *)domain;
	int label = 0, dots = 0, letters = 0;
	if (!*p || strlen(domain) > 253)
		return 0;
	for (; *p; p++) {
		if (*p == '.') {
			if (!label || p[-1] == '-') return 0;
			label = 0;
			dots++;
		} else {
			if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
			      (*p >= '0' && *p <= '9') || (*p == '-' && label))) return 0;
			if (++label > 63) return 0;
			if (*p < '0' || *p > '9') letters = 1;
		}
	}
	return dots && letters && label && p[-1] != '-';
}

void wireguard_dnsmasq_config(FILE *config)
{
	FILE *list = fopen("/etc/storage/vpnc_domains.list", "r");
	char line[1024], *domain, *end;
	int invalid = 0, ch;
	if (!list) return;
	/* Keep DNS learning independent of tunnel availability and client selection.
	 * Only wgc.sh consumes this reserved IPv4 set. Never flush foreign sets. */
	if (eval("/sbin/ipset", "-exist", "create", "wgc.domains", "hash:ip", "family", "inet", "timeout", "21600") ||
	    eval("/sbin/ipset", "flush", "wgc.domains")) {
		logmessage("WireGuard", "Cannot prepare domain routing IPSet");
		/* Keep valid directives: wgc.sh retries set creation on VPN start.
		 * A transient module failure must not remove DNS learning until reboot. */
	}
	while (fgets(line, sizeof(line), list)) {
		if (!strchr(line, '\n') && !feof(list)) {
			while ((ch = fgetc(list)) != '\n' && ch != EOF) { }
			/* Long comments do not invalidate a complete domain before '#'. */
			if (!strchr(line, '#')) { invalid = 1; continue; }
		}
		end = strchr(line, '#');
		if (end) *end = '\0';
		domain = line;
		while (isspace((unsigned char)*domain)) domain++;
		end = domain + strlen(domain);
		while (end > domain && isspace((unsigned char)end[-1])) *--end = '\0';
		if (end == domain) continue;
		if (end[-1] == '.') *--end = '\0';
		if (!wg_domain_valid(domain)) { invalid = 1; continue; }
		/* Strict validation prevents directives, wildcards or set-name injection. */
		fprintf(config, "ipset=/%s/wgc.domains\n", domain);
	}
	if (invalid || ferror(list))
		logmessage("WireGuard", "Invalid entries in domain routing list were ignored");
	fclose(list);
}
#endif
