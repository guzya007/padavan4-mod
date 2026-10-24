<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - DoH</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="shortcut icon" href="images/favicon.ico">
<link rel="stylesheet" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" href="/bootstrap/css/main.css">
<link rel="stylesheet" href="/bootstrap/css/engage.itoggle.css">
<script src="/jquery.js"></script>
<script src="/bootstrap/js/bootstrap.min.js"></script>
<script src="/bootstrap/js/engage.itoggle.min.js"></script>
<script src="/state.js"></script>
<script src="/general.js"></script>
<script src="/itoggle.js"></script>
<script src="/popup.js"></script>
<script>
var $j = jQuery.noConflict();

function initial() {
	show_banner(1);
	show_menu(5,21,1);
	show_footer();
	load_body();
	init_itoggle('doh_enable', change_doh_enabled);
	change_doh_enabled();
	updatePorts();
}

function change_doh_enabled() {
	showhide_div('doh_settings', document.form.doh_enable[0].checked);
}

function updatePorts() {
	var port = Number(document.form.doh_listen_port.value);
	var addr = '127.0.0.1';
	if (document.form.doh_listen_mode.value == '1') addr = document.getElementById('doh_lan').text;
	if (document.form.doh_listen_mode.value == '2') addr = '0.0.0.0';
	for (var i = 0; i < 4; i++) $j('#doh_port' + i).text(addr + ':' + (port + i));
}

function validForm() {
	if (!document.form.doh_enable[0].checked) return true;
	if (!validate_range(document.form.doh_listen_port, 1024, 65530)) return false;
	var bootstrap = document.form.doh_bootstrap_dns;
	bootstrap.value = $j.trim(bootstrap.value).replace(/\s+/g, '');
	var ips = bootstrap.value.split(',');
	for (var i = 0; i < ips.length; i++) {
		if (!/^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/.test(ips[i])) {
			alert('<#DoH_Invalid_Bootstrap#>'); bootstrap.focus(); return false;
		}
	}
	var count = 0;
	for (var j = 0; j < 4; j++) {
		var input = document.form['doh_server' + j];
		input.value = $j.trim(input.value);
		if (!input.value) continue;
		var url = document.createElement('a');
		url.href = input.value;
		if (!/^https:\/\/[^\s<>"'`\\]+$/.test(input.value) || url.protocol != 'https:' || !url.hostname) {
			alert('<#DoH_Invalid_URL#>'); input.focus(); return false;
		}
		count++;
	}
	if (!count) { alert('<#DoH_Empty#>'); return false; }
	return true;
}

function applyRule() {
	if (!found_app_doh() || !validForm()) return;
	showLoading();
	document.form.action_mode.value = ' Apply ';
	document.form.current_page.value = '/Advanced_Services_DoH.asp';
	document.form.submit();
}

function done_validating(action) { refreshpage(); }
</script>
</head>
<body onload="initial();" onunload="return unload_body();">
<div class="wrapper">
	<div class="container-fluid" style="padding-right:0"><div class="row-fluid">
		<div class="span3"><center><div id="logo"></div></center></div>
		<div class="span9"><div id="TopBanner"></div></div>
	</div></div>
	<div id="Loading" class="popup_bg"></div>
	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
	<form method="post" name="form" action="/start_apply.htm" target="hidden_frame">
		<input type="hidden" name="current_page" value="Advanced_Services_DoH.asp">
		<input type="hidden" name="next_page" value="">
		<input type="hidden" name="next_host" value="">
		<input type="hidden" name="sid_list" value="LANHostConfig;">
		<input type="hidden" name="group_id" value="">
		<input type="hidden" name="action_mode" value="">
		<input type="hidden" name="action_script" value="">
		<div class="container-fluid"><div class="row-fluid">
			<div class="span3"><div class="well sidebar-nav side_nav" style="padding:0">
				<ul id="mainMenu" class="clearfix"></ul>
				<ul class="clearfix"><li><div id="subMenu" class="accordion"></div></li></ul>
			</div></div>
			<div class="span9"><div class="box well grad_colour_dark_blue">
				<h2 class="box_head round_top">DNS-over-HTTPS (DoH)</h2>
				<div class="round_bottom"><div class="row-fluid">
					<div id="tabMenu" class="submenuBlock"></div>
					<div class="alert alert-info" style="margin:10px"><#DoH_Info#></div>
					<table class="table">
						<tr><th width="40%"><#DoH_Enable#></th><td>
							<div class="main_itoggle"><div id="doh_enable_on_of">
								<input type="checkbox" id="doh_enable_fake" <% nvram_match_x("", "doh_enable", "1", "value=1 checked"); %><% nvram_match_x("", "doh_enable", "0", "value=0"); %>>
							</div></div>
							<div style="position:absolute;margin-left:-10000px">
								<input type="radio" name="doh_enable" id="doh_enable_1" value="1" <% nvram_match_x("", "doh_enable", "1", "checked"); %>><#checkbox_Yes#>
								<input type="radio" name="doh_enable" id="doh_enable_0" value="0" <% nvram_match_x("", "doh_enable", "0", "checked"); %>><#checkbox_No#>
							</div>
						</td></tr>
						<tbody id="doh_settings">
							<tr><th><#DoH_Mode#></th><td><select name="doh_mode">
								<option value="1" <% nvram_match_x("", "doh_mode", "1", "selected"); %>><#DoH_Mode_DNSMasq#> (*)</option>
								<option value="0" <% nvram_match_x("", "doh_mode", "0", "selected"); %>><#DoH_Mode_Standalone#></option>
							</select></td></tr>
							<tr><th><#DoH_Listen#></th><td><select name="doh_listen_mode" onchange="updatePorts();">
								<option value="0" <% nvram_match_x("", "doh_listen_mode", "0", "selected"); %>>127.0.0.1 (*)</option>
								<option id="doh_lan" value="1" <% nvram_match_x("", "doh_listen_mode", "1", "selected"); %>><% nvram_get_x("", "lan_ipaddr"); %></option>
								<option value="2" <% nvram_match_x("", "doh_listen_mode", "2", "selected"); %>>0.0.0.0</option>
							</select></td></tr>
							<tr><th><#DoH_Port#></th><td><input name="doh_listen_port" maxlength="5" value="<% nvram_get_x("", "doh_listen_port"); %>" onchange="updatePorts();"> <span class="help-inline">1024–65530</span></td></tr>
							<tr><th><#DoH_Bootstrap#></th><td><input name="doh_bootstrap_dns" maxlength="128" value="<% nvram_get_x("", "doh_bootstrap_dns"); %>"></td></tr>
							<tr><td colspan="2"><#DoH_Resolvers#></td></tr>
							<tr><th id="doh_port0"></th><td><input class="span12" name="doh_server0" list="doh_presets" maxlength="256" value="<% nvram_get_x("", "doh_server0"); %>"></td></tr>
							<tr><th id="doh_port1"></th><td><input class="span12" name="doh_server1" list="doh_presets" maxlength="256" value="<% nvram_get_x("", "doh_server1"); %>"></td></tr>
							<tr><th id="doh_port2"></th><td><input class="span12" name="doh_server2" list="doh_presets" maxlength="256" value="<% nvram_get_x("", "doh_server2"); %>"></td></tr>
							<tr><th id="doh_port3"></th><td><input class="span12" name="doh_server3" list="doh_presets" maxlength="256" value="<% nvram_get_x("", "doh_server3"); %>"></td></tr>
						</tbody>
					</table>
					<datalist id="doh_presets">
						<option value="https://dns.google/dns-query">Google</option>
						<option value="https://cloudflare-dns.com/dns-query">Cloudflare</option>
						<option value="https://dns.quad9.net/dns-query">Quad9</option>
						<option value="https://dns.adguard-dns.com/dns-query">AdGuard</option>
						<option value="https://doh.opendns.com/dns-query">OpenDNS</option>
						<option value="https://common.dot.dns.yandex.net/dns-query">Yandex</option>
					</datalist>
					<div style="text-align:center;padding:10px"><input class="btn btn-primary" type="button" value="<#CTL_apply#>" onclick="applyRule();"></div>
				</div></div>
			</div></div>
		</div></div>
	</form>
	<div id="footer"></div>
</div>
</body>
</html>
