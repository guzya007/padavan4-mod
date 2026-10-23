/* Native VPN type 3 UI, using padavan-ng's NVRAM names and AWG 3.1 parameters. */
var wgRole, wgStatusTimer;
var wgAwgFields = ['jc', 'jmin', 'jmax', 'i1', 'i2', 'i3', 'i4', 'i5',
    'h1', 'h2', 'h3', 'h4', 's1', 's2', 's3', 's4', 'contentpaddingaddition',
    'headerprotectionkey', 'rekeyaftertime', 'rekeytimeout', 'rejectaftertime',
    'keepalivetimeout', 'maxhandshakeattempts', 'randomtrailers', 'disablecookies'];

function wg_input(table, name, label, type) {
    var row = document.createElement('tr');
    var th = document.createElement('th');
    th.style.width = '50%';
    th.textContent = label;
    row.appendChild(th);
    var td = document.createElement('td');
    var input = document.createElement(type === 'textarea' ? 'textarea' : 'input');
    input.name = name;
    input.className = 'input';
    if (type !== 'file') input.value = wgSettings[name] || '';
    if (type === 'textarea' && !Object.prototype.hasOwnProperty.call(wgSettings, name))
        input.setAttribute('data-wg-unloaded', '1');
    input.style.width = '95%';
    if (type === 'textarea') input.rows = 5;
    else {
        input.type = type || 'text';
        input.maxLength = name.match(/_i[1-5]$/) ? 3072 : 1024;
        input.autocomplete = 'off';
        input.spellcheck = false;
    }
    td.appendChild(input);
    row.appendChild(td);
    table.appendChild(row);
    return input;
}

function wg_button(input, label, handler) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'btn';
    button.textContent = label;
    button.onclick = handler;
    input.parentNode.appendChild(button);
}

function wg_key(action, key, callback) {
    if (!login_safe()) return;
    $j.post('/apply.cgi', {action_mode: ' wg_action ', action: action, privkey: key || ''}, function(response) {
        callback($j.trim(response));
    });
}

function wg_generate(name, action) {
    wg_key(action || 'genkey', '', function(key) {
        document.form.elements[name].value = key;
        wg_public(name);
    });
}

function wg_public(name) {
    if (!/private$/.test(name)) return;
    var publicName = name.replace(/private$/, 'public');
    if (!document.form.elements[publicName]) return;
    var key = document.form.elements[name].value;
    if (!/^[A-Za-z0-9+/]{43}=$/.test(key)) {
        document.form.elements[publicName].value = '';
        return;
    }
    wg_key('pubkey', key, function(publicKey) {
        document.form.elements[publicName].value = publicKey;
    });
}

function wg_init(role) {
    wgRole = role;
    if (!found_app_wg()) {
        $j('select[name="' + role + '_type"] option[value="3"]').remove();
        return;
    }
    $j('select[name="' + role + '_type"] option[value="3"]').text(found_app_awg() ? 'AmneziaWG' : 'WireGuard');
    var table = document.createElement('table');
    table.className = 'table';
    table.id = 'tbl_' + role + '_wg';
    table.style.display = 'none';
    var privateName = role + (role === 'vpnc' ? '_wg_if_private' : '_wg_private');
    if (role === 'vpnc') {
        var file = wg_input(table, 'wg_import_file', '<#AWG_Import#>', 'file');
        file.accept = '.conf';
        file.removeAttribute('name');
        wg_button(file, '<#AWG_Import#>', function() { wg_import(file); });
        wg_input(table, 'vpnc_wg_if_addr', '<#AWG_Address#>');
    }
    var privateInput = wg_input(table, privateName, '<#AWG_Private#>', 'password');
    privateInput.maxLength = 44;
    privateInput.onchange = function() { wg_public(privateName); };
    wg_button(privateInput, '<#AWG_Generate#>', function() { wg_generate(privateName); });
    wg_button(privateInput, '<#CTL_show_pass#>', function() {
        privateInput.type = privateInput.type === 'password' ? 'text' : 'password';
    });
    var publicInput = wg_input(table, privateName.replace(/private$/, 'public'), '<#AWG_Public#>');
    publicInput.readOnly = true;
    if (role === 'vpnc') {
        var psk = wg_input(table, 'vpnc_wg_if_preshared', '<#AWG_Preshared#>', 'password');
        psk.maxLength = 44;
        wg_button(psk, '<#AWG_Generate#>', function() { wg_generate('vpnc_wg_if_preshared', 'genpsk'); });
        wg_input(table, 'vpnc_wg_peer_public', '<#AWG_PeerPublic#>').maxLength = 44;
        wg_input(table, 'vpnc_wg_peer_endpoint', '<#AWG_Endpoint#>');
        wg_input(table, 'vpnc_wg_peer_port', '<#OVPN_Port#>');
        wg_input(table, 'vpnc_wg_peer_keepalive', 'PersistentKeepalive');
        wg_input(table, 'vpnc_wg_peer_allowedips', 'AllowedIPs');
        wg_input(table, 'vpnc_wg_if_dns', 'DNS');
        wg_input(table, 'vpnc_clients_allowed', '<#AWG_Clients#>');
        wg_input(table, 'scripts.vpnc_remote_network.list', '<#AWG_RemoteNetworks#>', 'textarea');
        wg_input(table, 'scripts.vpnc_exclude_network.list', '<#AWG_ExcludeNetworks#>', 'textarea');
        wg_input(table, 'scripts.vpnc_post_script.sh', '<#AWG_PostScript#>', 'textarea');
    } else {
        wg_input(table, 'vpns_wg_port', '<#OVPN_Port#>');
        wg_input(table, 'vpns_wg_ext_addr', '<#AWG_Endpoint#>');
        wg_input(table, 'scripts.vpns_post_script.sh', '<#AWG_PostScript#>', 'textarea');
        var keyCell = document.form.vpns_pass_x_0;
        keyCell.maxLength = 44;
        wg_button(keyCell, '<#AWG_Generate#>', function() { wg_generate('vpns_pass_x_0'); });
        keyCell.parentNode.lastChild.id = 'wg_client_genkey';
    }
    wg_input(table, role + '_wg_mtu', 'MTU');
    if (found_app_awg()) {
        var section = document.createElement('tr');
        var cell = document.createElement('th');
        cell.colSpan = 2;
        cell.textContent = 'AmneziaWG 3.1 — <#AWG_ConfigHint#>';
        section.appendChild(cell);
        table.appendChild(section);
        wgAwgFields.forEach(function(field) { wg_input(table, role + '_awg_' + field, field); });
    }
    var base = document.getElementById(role === 'vpnc' ? 'tbl_vpnc_config' : 'tbl_vpn_config');
    base.parentNode.insertBefore(table, base.nextSibling);
    // File contents are JSON-escaped by httpd; do not expose them via innerHTML.
    Object.keys(wgSettings).forEach(function(name) {
        if (document.form.elements[name]) document.form.elements[name].value = wgSettings[name];
    });
    if (!login_safe()) $j(table).find('input, textarea, button').prop('disabled', true);
    var status = document.createElement('pre');
    status.id = 'wg_status';
    status.textContent = '<#Nodata#>';
    table.parentNode.insertBefore(status, table.nextSibling);
    wgStatusTimer = setTimeout(wg_refresh_status, 1000);
}

function wg_toggle(role, enabled, selected) {
    if (!found_app_wg()) return;
    var active = enabled && selected;
    $j('#tbl_' + role + '_wg, #wg_status').toggle(!!active);
    $j('#tbl_' + role + '_wg').find('input, textarea').each(function() {
        this.disabled = !active || !login_safe() || this.getAttribute('data-wg-unloaded') === '1';
    });
    if (role === 'vpns') $j('#wg_client_genkey').toggle(!!selected);
}

function wg_valid(role) {
    if (!login_safe()) return false;
    var keyName = role + (role === 'vpnc' ? '_wg_if_private' : '_wg_private');
    var key = document.form.elements[keyName];
    if ((role === 'vpnc' || key.value) && !/^[A-Za-z0-9+/]{43}=$/.test(key.value)) {
        alert('<#AWG_InvalidKey#>'); key.focus(); return false;
    }
    var mtu = document.form.elements[role + '_wg_mtu'];
    if (!validate_range(mtu, 1280, 1420)) return false;
    if (role === 'vpnc') {
        if (!wg_valid_ipv4_list(document.form.vpnc_clients_allowed.value)) {
            alert('<#AWG_InvalidConfig#>'); document.form.vpnc_clients_allowed.focus(); return false;
        }
        var lists = ['scripts.vpnc_remote_network.list', 'scripts.vpnc_exclude_network.list'];
        for (var l = 0; l < lists.length; l++) {
            var networks = document.form.elements[lists[l]];
            if (!networks.disabled && !wg_valid_ipv4_list(networks.value.replace(/#.*$/gm, ''))) {
                alert('<#AWG_InvalidConfig#>'); networks.focus(); return false;
            }
        }
        if (!validate_range(document.form.vpnc_wg_peer_port, 1, 65535) ||
            !validate_range(document.form.vpnc_wg_peer_keepalive, 0, 65535)) return false;
        if (!/^[A-Za-z0-9+/]{43}=$/.test(document.form.vpnc_wg_peer_public.value) ||
            (document.form.vpnc_wg_if_preshared.value && !/^[A-Za-z0-9+/]{43}=$/.test(document.form.vpnc_wg_if_preshared.value))) {
            alert('<#AWG_InvalidKey#>'); return false;
        }
        if (!document.form.vpnc_wg_if_addr.value || !document.form.vpnc_wg_peer_endpoint.value ||
            !document.form.vpnc_wg_peer_allowedips.value) { alert('<#JS_fieldblank#>'); return false; }
    } else if (!validate_range(document.form.vpns_wg_port, 1, 65535)) return false;
    if (found_app_awg()) {
        var jc = document.form.elements[role + '_awg_jc'];
        var jmin = document.form.elements[role + '_awg_jmin'];
        var jmax = document.form.elements[role + '_awg_jmax'];
        if (!validate_range(jc, 0, 128) || !validate_range(jmin, 0, 1024) ||
            !validate_range(jmax, parseInt(jmin.value, 10), 1024)) return false;
        for (var n = 0; n < wgAwgFields.length; n++) {
            var field = wgAwgFields[n], input = document.form.elements[role + '_awg_' + field];
            var value = input.value.trim(), max = /^h[1-4]$/.test(field) ? 4294967295 : 65535;
            if (/^i[1-5]$/.test(field)) continue;
            if (field === 'headerprotectionkey') {
                if (!value || /^[A-Za-z0-9+/]{43}=$/.test(value)) continue;
            } else if (/^(randomtrailers|disablecookies)$/.test(field)) {
                if (/^[01]$/.test(value)) continue;
            } else {
                var range = value.match(/^(\d+)(?:-(\d+))?$/);
                if (range && +range[1] <= max && (!range[2] || (+range[2] >= +range[1] && +range[2] <= max))) continue;
            }
            alert('<#AWG_InvalidConfig#>'); input.focus(); return false;
        }
    }
    return true;
}

function wg_valid_ipv4_list(value) {
    return value.split(/[\s,]+/).every(function(network) {
        if (!network) return true;
        var pair = network.split('/'), octets = pair[0].split('.');
        return pair.length <= 2 && (pair.length === 1 || (/^\d+$/.test(pair[1]) && +pair[1] <= 32)) &&
            octets.length === 4 && octets.every(function(octet) { return /^\d{1,3}$/.test(octet) && +octet <= 255; });
    });
}

function wg_parse_conf(text) {
    var result = {interface: {}, peer: {}}, section = '', peers = 0;
    text.split(/\r?\n/).forEach(function(line) {
        line = line.replace(/#.*$/, '').trim();
        if (!line || /^[#;]/.test(line)) return;
        if (/^\[Interface\]$/i.test(line)) { section = 'interface'; return; }
        if (/^\[Peer\]$/i.test(line)) { section = 'peer'; peers++; return; }
        var pair = line.match(/^([A-Za-z0-9]+)\s*=\s*(.*)$/);
        if (!pair || !section) throw new Error('<#AWG_InvalidConfig#>');
        var name = pair[1].toLowerCase();
        if (!found_app_awg() && wgAwgFields.indexOf(name) >= 0)
            throw new Error('<#AWG_UnsupportedConfig#>');
        if (/^(preup|postup|predown|postdown|table|saveconfig)$/.test(name))
            throw new Error('<#AWG_UnsupportedConfig#>');
        var supported = section === 'interface' ?
            ['privatekey', 'address', 'dns', 'mtu'].concat(wgAwgFields) :
            ['publickey', 'presharedkey', 'endpoint', 'allowedips', 'persistentkeepalive', 'advancedsecurity'];
        if (supported.indexOf(name) < 0 || (name === 'advancedsecurity' && !/^(1|on|true)$/i.test(pair[2].trim())))
            throw new Error('<#AWG_UnsupportedConfig#>');
        result[section][name] = pair[2].trim();
    });
    if (peers !== 1 || !result.interface.privatekey || !result.interface.address ||
        !result.peer.publickey || !result.peer.endpoint || !result.peer.allowedips)
        throw new Error('<#AWG_InvalidConfig#>');
    return result;
}

function wg_apply_conf(config, defaults) {
    var i = config.interface, p = config.peer;
    var endpoint = p.endpoint.match(/^(\[[^\]]+\]|[^:]+):(\d+)$/);
    if (!endpoint) throw new Error('<#AWG_InvalidConfig#>');
    var values = {
        vpnc_wg_if_addr: i.address, vpnc_wg_if_private: i.privatekey,
        vpnc_wg_if_preshared: p.presharedkey || '', vpnc_wg_if_dns: i.dns || '',
        vpnc_wg_mtu: i.mtu || '1280', vpnc_wg_peer_public: p.publickey,
        vpnc_wg_peer_endpoint: endpoint[1].replace(/^\[|\]$/g, ''),
        vpnc_wg_peer_port: endpoint[2], vpnc_wg_peer_keepalive: p.persistentkeepalive || '25',
        vpnc_wg_peer_allowedips: p.allowedips
    };
    if (found_app_awg()) wgAwgFields.forEach(function(field) {
        values['vpnc_awg_' + field] = Object.prototype.hasOwnProperty.call(i, field) ? i[field] : (defaults[field] || '');
        if (field === 'randomtrailers' || field === 'disablecookies')
            values['vpnc_awg_' + field] = /^(1|on|true)$/i.test(values['vpnc_awg_' + field]) ? '1' : '0';
    });
    Object.keys(values).forEach(function(name) { document.form.elements[name].value = values[name]; });
    wg_public('vpnc_wg_if_private');
}

function wg_import(input) {
    if (!input.files.length || !login_safe()) return;
    if (input.files[0].size > 65536) { alert('<#AWG_InvalidConfig#>'); return; }
    var reader = new FileReader();
    reader.onload = function(event) {
        try {
            var config = wg_parse_conf(event.target.result);
            $j.getJSON('/amneziawg.json', function(defaults) {
                try { wg_apply_conf(config, defaults[0]); } catch (error) { alert(error.message); }
            }).fail(function() { alert('<#AWG_InvalidConfig#>'); });
        } catch (error) { alert(error.message); }
    };
    reader.readAsText(input.files[0]);
}

function wg_refresh_status() {
    clearTimeout(wgStatusTimer);
    if (login_safe() && document.getElementById('wg_status') && document.form.elements[wgRole + '_type'].value === '3') {
        $j.post('/apply.cgi', {action_mode: ' wg_action ', action: 'status', iface: wgRole === 'vpnc' ? 'wg0' : 'wg1'}, function(response) {
            document.getElementById('wg_status').textContent = response || '<#Nodata#>';
        });
        if (wgRole === 'vpns' && window.location.hash === '#cli') wg_refresh_clients();
    }
    wgStatusTimer = setTimeout(wg_refresh_status, 5000);
}

function wg_refresh_clients() {
    var table = document.querySelector('#wnd_vpns_cli table');
    var labels = ['<#VPNS_CName#>', '<#AWG_Address#>', '<#AWG_Endpoint#>', '<#AWG_Handshake#>', 'RX', 'TX'];
    var header = table.rows[0];
    header.textContent = '';
    labels.forEach(function(label) { var th = document.createElement('th'); th.textContent = label; header.appendChild(th); });
    $j.ajax({type: 'post', url: '/apply.cgi', dataType: 'json',
        data: {action_mode: ' wg_action ', action: 'clients'}, success: function(clients) {
            $j(table).find('tr.client').remove();
            if (!clients.length) {
                var row = table.insertRow(); row.className = 'client';
                var cell = row.insertCell(); cell.colSpan = 6; cell.textContent = '<#Nodata#>';
            }
            clients.forEach(function(client) {
                var row = table.insertRow(); row.className = 'client';
                var handshake = client[3] ? new Date(client[3] * 1000).toLocaleString() : '<#Nodata#>';
                [client[2], client[0], client[1], handshake, client[4], client[5]].forEach(function(value) {
                    row.insertCell().textContent = value;
                });
            });
        }
    });
}

function wg_restore_client_headers() {
    var table = document.querySelector('#wnd_vpns_cli table');
    var labels = ['<#IPLocal#>', '<#IPRemote#>', '<#VPNS_CName#>', '<#RouterConfig_GWStaticIF_itemname#>'];
    table.rows[0].textContent = '';
    labels.forEach(function(label) { var th = document.createElement('th'); th.textContent = label; table.rows[0].appendChild(th); });
}

function wg_export_client(index) {
    if (!login_safe()) return;
    $j.post('/apply.cgi', {action_mode: ' ExportWGConf ', common_name: ACLList[index][0]}, function(config) {
        if (!config) { alert('<#AWG_InvalidConfig#>'); return; }
        var box = document.getElementById('wg_export_' + index);
        box.textContent = '';
        var button = document.createElement('button');
        button.type = 'button'; button.className = 'btn btn-success'; button.textContent = '<#CTL_onlysave#>';
        button.onclick = function() {
            var url = URL.createObjectURL(new Blob([config], {type: 'text/plain'}));
            var link = document.createElement('a');
            link.href = url; link.download = ACLList[index][0] + '_wg.conf';
            document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
        };
        box.appendChild(button);
        var qr = document.createElement('div'); box.appendChild(qr);
        try { new QRCode(qr, {text: config, width: 256, height: 256, correctLevel: QRCode.CorrectLevel.L}); }
        catch (error) { qr.textContent = '<#AWG_QRTooLong#>'; }
        var pre = document.createElement('pre'); pre.textContent = config; box.appendChild(pre);
    });
}

function wg_acl_exports() {
    if (!found_app_wg() || document.form.vpns_type.value !== '3') return;
    ACLList.forEach(function(client, index) {
        var row = document.getElementById('row' + index);
        var cell = row.cells[1]; cell.textContent = '';
        var button = document.createElement('button');
        button.type = 'button'; button.className = 'btn'; button.textContent = '<#VPNS_Export#> / QR';
        button.onclick = function() { wg_export_client(index); };
        cell.appendChild(button);
        var exportRow = document.createElement('tr');
        var exportCell = document.createElement('td');
        exportCell.colSpan = 5; exportCell.id = 'wg_export_' + index;
        exportRow.appendChild(exportCell); row.parentNode.insertBefore(exportRow, row.nextSibling);
    });
}
