<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - D2K</title>
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
<% login_state_hook(); %>
var savedPanelURL = '';
var savedEnabled = false;
var d2kApplying = false;

function panelURL(config, host) {
	if (!/^\d+\.\d+\.\d+\.\d+$/.test(host)) return '';
	var listen = '0.0.0.0:8090';
	var lines = config.split(/\r?\n/);
	for (var i = 0; i < lines.length; i++) {
		var m = lines[i].match(/^\s*PANEL_LISTEN\s*=\s*(?:"([^"]*)"|'([^']*)'|([^#\s]*))\s*(?:#.*)?$/);
		if (m) listen = m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3]);
	}
	var parts = listen.split(':');
	if (parts.length != 2 || (parts[0] != '0.0.0.0' && parts[0] != host)) return '';
	if (!/^\d+$/.test(parts[1]) || Number(parts[1]) < 1 || Number(parts[1]) > 65535) return '';
	return 'http://' + host + ':' + Number(parts[1]) + '/';
}

function initial() {
	show_banner(1);
	show_menu(5,21,found_app_doh() ? 2 : 1);
	show_footer();
	load_body();
	savedEnabled = document.form.d2k_enable[0].checked;
	savedPanelURL = panelURL(document.form['d2kconf.config'].value, document.getElementById('d2k_lan').value);
	init_itoggle('d2k_enable', change_d2k_enabled);
	change_d2k_enabled();
}

function change_d2k_enabled() {
	var enabled = document.form.d2k_enable[0].checked;
	showhide_div('d2k_settings', enabled);
	document.form['d2kconf.config'].disabled = !enabled || !login_safe();
	document.getElementById('d2k_open').disabled = !enabled || !savedEnabled || !savedPanelURL;
}

function openPanel() {
	if (savedEnabled && savedPanelURL) {
		var panel = window.open(savedPanelURL, '_blank');
		if (panel) panel.opener = null;
	}
}

function applyRule() {
	if (d2kApplying || !login_safe() || !found_app_d2k()) return;
	d2kApplying = true;
	showLoading();
	document.form.action_mode.value = ' Apply ';
	document.form.current_page.value = '/Advanced_Services_D2K.asp';
	document.form.submit();
}

function d2kApplyWait(seconds) {
	var started = Date.now(), minimum = Math.max(1, seconds) * 1000;
	var finished = false;
	// Unlike the shared timer, never display "complete" while rc is busy.
	function poll() {
		var elapsed = Date.now() - started;
		if (elapsed >= 60000) {
			finished = true;
			d2kApplying = false;
			hideLoading();
			document.documentElement.style.overflow = '';
			alert('<#D2K_ApplyTimeout#>');
			return;
		}
		var progress = Math.min(95, Math.round(elapsed * 100 / minimum));
		document.getElementById('proceeding_main_txt').textContent = '<#D2K_Applying#>';
		document.getElementById('proceeding_txt').textContent = progress + '%';
		document.getElementById('proceeding_bar').style.width = progress + '%';
		$j.ajax({type: 'post', url: '/apply.cgi', dataType: 'json', timeout: 3000,
			data: {action_mode: ' D2K_ApplyStatus '},
			success: function(status) {
				if (status && status.pending === false && Date.now() - started >= minimum) {
					finished = true;
					location.reload();
				}
			},
			complete: function() { if (!finished) setTimeout(poll, 1000); }
		});
	}
	poll();
}

function done_validating(action) { refreshpage(); }
</script>
</head>
<body onload="initial();" onunload="return unload_body();">
<div class="wrapper">
	<div class="container-fluid" style="padding-right:0">
		<div class="row-fluid">
			<div class="span3"><center><div id="logo"></div></center></div>
			<div class="span9"><div id="TopBanner"></div></div>
		</div>
	</div>
	<div id="Loading" class="popup_bg"></div>
	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
	<form method="post" name="form" action="/start_apply.htm" target="hidden_frame">
		<input type="hidden" name="current_page" value="Advanced_Services_D2K.asp">
		<input type="hidden" name="next_page" value="">
		<input type="hidden" name="next_host" value="">
		<input type="hidden" name="sid_list" value="LANHostConfig;">
		<input type="hidden" name="group_id" value="">
		<input type="hidden" name="action_mode" value="">
		<input type="hidden" name="action_script" value="">
		<input type="hidden" id="d2k_lan" value="<% nvram_get_x("", "lan_ipaddr"); %>">
		<div class="container-fluid"><div class="row-fluid">
			<div class="span3"><div class="well sidebar-nav side_nav" style="padding:0">
				<ul id="mainMenu" class="clearfix"></ul>
				<ul class="clearfix"><li><div id="subMenu" class="accordion"></div></li></ul>
			</div></div>
			<div class="span9"><div class="box well grad_colour_dark_blue">
				<h2 class="box_head round_top">D2K</h2>
				<div class="round_bottom"><div class="row-fluid">
					<div id="tabMenu" class="submenuBlock"></div>
					<div class="alert alert-info" style="margin:10px"><#D2K_Info#></div>
					<table class="table">
						<tr><th width="50%"><#D2K_Enable#></th><td>
							<div class="main_itoggle"><div id="d2k_enable_on_of">
								<input type="checkbox" id="d2k_enable_fake" <% nvram_match_x("", "d2k_enable", "1", "value=1 checked"); %><% nvram_match_x("", "d2k_enable", "0", "value=0"); %>>
							</div></div>
							<div style="position:absolute;margin-left:-10000px">
								<input type="radio" name="d2k_enable" id="d2k_enable_1" value="1" <% nvram_match_x("", "d2k_enable", "1", "checked"); %>><#checkbox_Yes#>
								<input type="radio" name="d2k_enable" id="d2k_enable_0" value="0" <% nvram_match_x("", "d2k_enable", "0", "checked"); %>><#checkbox_No#>
							</div>
						</td></tr>
						<tbody id="d2k_settings">
							<tr><td colspan="2">
								<div class="alert"><#D2K_Panel_Warning#></div>
								<button class="btn btn-info" type="button" id="d2k_open" onclick="openPanel();"><#D2K_Open#></button>
								<p class="help-block" style="margin-top:10px"><#D2K_Apply_First#></p>
							</td></tr>
							<tr><td colspan="2">
								<a href="javascript:void(0)" onclick="$j('#d2k_config').toggle();"><#D2K_Config#> <i class="icon-chevron-down"></i></a>
								<div id="d2k_config" style="display:none;margin-top:10px">
									<textarea class="span12" rows="22" maxlength="16384" spellcheck="false" wrap="off" name="d2kconf.config" style="font-family:monospace;resize:vertical"><% nvram_dump("d2kconf.config", ""); %></textarea>
								</div>
							</td></tr>
						</tbody>
					</table>
					<div style="text-align:center;padding:10px"><input class="btn btn-primary" type="button" value="<#CTL_apply#>" onclick="applyRule();"></div>
				</div></div>
			</div></div>
		</div></div>
	</form>
	<div id="footer"></div>
</div>
</body>
</html>
