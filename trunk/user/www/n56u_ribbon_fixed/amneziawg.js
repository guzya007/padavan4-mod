/* Native VPN type 3 UI, using padavan-ng's NVRAM names and AWG 3.1 parameters. */
var wgRole, wgStatusTimer, wgImportSequence = 0;
var wgClientState = null, wgStatusMode = '', wgStatusGeneration = 0, wgStatusRequest = 0;
var wgHelpEnabled = '<% nvram_get_x("", "help_enable"); %>' !== '0';
var wgAwgFields = ['jc', 'jmin', 'jmax', 'i1', 'i2', 'i3', 'i4', 'i5',
    'h1', 'h2', 'h3', 'h4', 's1', 's2', 's3', 's4', 'contentpaddingaddition',
    'headerprotectionkey', 'rekeyaftertime', 'rekeytimeout', 'rejectaftertime',
    'keepalivetimeout', 'maxhandshakeattempts', 'randomtrailers', 'disablecookies'];

function wg_input(table, name, label, type, hint) {
    var row = document.createElement('tr');
    var th = document.createElement('th');
    th.style.width = '50%';
    th.textContent = label;
    if (hint) wg_hint(th, hint);
    row.appendChild(th);
    var td = document.createElement('td');
    var input = document.createElement(type === 'textarea' ? 'textarea' : 'input');
    input.name = name;
    input.className = 'input';
    if (type !== 'file') input.value = wgSettings[name] || '';
    if (type === 'textarea' && !Object.prototype.hasOwnProperty.call(wgSettings, name))
        input.setAttribute('data-wg-unloaded', '1');
    input.style.width = '95%';
    if (type === 'textarea') {
        input.rows = 5;
        input.wrap = 'off';
        input.spellcheck = false;
        input.style.fontFamily = 'monospace';
        input.style.resize = 'vertical';
    }
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

function wg_hint(label, text, toggle) {
    if (!wgHelpEnabled) return;
    var link = document.createElement('a');
    link.className = 'help_tooltip';
    link.href = '#';
    link.textContent = label.textContent;
    $j(label).empty().append(link);
    $j(link).popover({title: link.textContent, content: text, html: false, trigger: 'manual'})
        .on('mouseenter focus', function() { $j(this).popover('show'); })
        .on('mouseleave blur', function() { $j(this).popover('hide'); })
        .on('click', function(event) { event.preventDefault(); if (toggle) toggle(); });
    return link;
}

function wg_group(table, title, collapsed) {
    var row = table.insertRow(), cell = row.insertCell();
    cell.colSpan = 2;
    cell.style.padding = '0';
    var heading = document.createElement('button');
    heading.type = 'button';
    heading.className = 'btn btn-block';
    heading.style.textAlign = 'left';
    heading.textContent = title;
    var group = document.createElement('table');
    group.className = 'table';
    group.style.marginBottom = '0';
    group.style.display = collapsed ? 'none' : '';
    heading.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    heading.onclick = function() {
        var visible = group.style.display === 'none';
        group.style.display = visible ? '' : 'none';
        heading.setAttribute('aria-expanded', visible ? 'true' : 'false');
    };
    cell.appendChild(heading);
    cell.appendChild(group);
    return group;
}

function wg_reveal(input) {
    for (var parent = input.parentNode; parent; parent = parent.parentNode) {
        if (parent.tagName === 'TABLE' && parent.style.display === 'none') {
            parent.style.display = '';
            if (parent.previousSibling && parent.previousSibling.hasAttribute('aria-expanded'))
                parent.previousSibling.setAttribute('aria-expanded', 'true');
        }
        if (parent.getAttribute && parent.getAttribute('data-wg-panel') === '1') {
            parent.style.display = '';
            parent.previousSibling.setAttribute('aria-expanded', 'true');
        }
    }
}

function wg_textarea(table, name, title, hint) {
    var input = wg_input(table, name, title, 'textarea');
    var row = input.parentNode.parentNode, cell = input.parentNode;
    row.removeChild(row.firstChild);
    cell.colSpan = 2;
    var label = document.createElement('span');
    label.textContent = title;
    var panel = document.createElement('div');
    panel.id = name.replace(/\./g, '_') + '_panel';
    panel.setAttribute('data-wg-panel', '1');
    panel.style.display = 'none';
    panel.style.marginTop = '8px';
    function toggle() {
        var visible = panel.style.display === 'none';
        panel.style.display = visible ? '' : 'none';
        heading.setAttribute('aria-expanded', visible ? 'true' : 'false');
    }
    var heading = wg_hint(label, hint, toggle);
    if (!heading) {
        heading = document.createElement('a');
        heading.href = '#'; heading.textContent = title;
        heading.onclick = function() { toggle(); return false; };
    }
    heading.setAttribute('aria-expanded', 'false');
    heading.setAttribute('aria-controls', panel.id);
    input.setAttribute('aria-label', title);
    cell.appendChild(heading);
    panel.appendChild(input); cell.appendChild(panel);
    return input;
}

function wg_copy(input) {
    input.select();
    document.execCommand('copy');
}

function wg_secret(input) {
    wg_button(input, '<#AWG_ShowKey#>', function() {
        input.type = input.type === 'password' ? 'text' : 'password';
    });
}

function wg_clients(table) {
    var allowed = wg_input(table, 'vpnc_clients_allowed', '<#AWG_Clients#>', 'hidden', '<#AWG_ClientsHint#>');
    var added = document.createElement('input');
    added.type = 'hidden'; added.name = 'vpnc_clients'; added.value = wgSettings.vpnc_clients || '';
    allowed.parentNode.appendChild(added);
    var selector = document.createElement('div');
    selector.id = 'vpnc_clients_selector';
    allowed.parentNode.appendChild(selector);
    function entries(value) { return (value || '').split(/[\s,]+/).filter(Boolean); }
    var selected = entries(allowed.value), manual = entries(added.value), items = [];
    function add(ip, title) {
        if (!ip || items.some(function(item) { return item.text === ip; })) return;
        items.push({text: ip, title: title || '', checked: selected.indexOf(ip) >= 0});
    }
    // Show names even for saved selections; never drop offline/manual entries.
    (wgSettings.lan_clients || []).forEach(function(client) {
        if (wg_valid_ipv4_list(client[0]) && client[0].indexOf('/') < 0) add(client[0], client[1]);
    });
    selected.concat(manual).forEach(function(ip) { add(ip); });
    $j(selector).multiSelectDropdown({
        items: items, placeholder: '<#AWG_AllClients#>', width: '95%',
        allowDelete: true, allowAdd: true, addSuggestionText: '<#CTL_add#>', removeSpaces: true,
        validateItem: function(value) { return !/[\s,]/.test(value) && wg_valid_ipv4_list(value); },
        allowedAlert: '<#AWG_InvalidConfig#>',
        onChange: function(values) {
            allowed.value = values.join(',');
            added.value = this.multiSelectDropdown('getAllItems').filter(function(item) {
                return !item.title || manual.indexOf(item.text) >= 0;
            }).map(function(item) { return item.text; }).join(',');
        }
    });
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
        if (document.form.elements[name].value === key)
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
    var status = document.createElement('pre');
    status.id = 'wg_status';
    status.textContent = '<#AWG_Stopped#>';
    status.setAttribute('aria-live', 'polite');
    var privateName = role + (role === 'vpnc' ? '_wg_if_private' : '_wg_private');
    if (role === 'vpnc') {
        var file = wg_input(table, 'wg_import_file', '<#AWG_Import#>', 'file', '<#AWG_ImportHint#>');
        file.accept = '.conf,.txt';
        file.removeAttribute('name');
        file.onchange = function() { wg_import(file); };
        file.onclick = function() { file.value = ''; };
        var state = document.createElement('span'); state.id = 'col_vpnc_wg_state';
        state.style.display = 'none'; file.parentNode.appendChild(state);
        var result = document.createElement('div');
        result.id = 'wg_import_result'; result.className = 'help-block';
        result.style.display = 'none'; result.setAttribute('aria-live', 'polite');
        file.parentNode.appendChild(result);
        var statusCell = table.insertRow().insertCell();
        statusCell.colSpan = 2; statusCell.appendChild(status);
        wg_input(table, 'vpnc_wg_if_addr', '<#AWG_Address#>', 'text', '<#AWG_AddressHint#>');
    }
    var privateInput = wg_input(table, privateName, '<#AWG_Private#>', 'password', '<#AWG_PrivateHint#>');
    privateInput.maxLength = 44;
    privateInput.onchange = function() { wg_public(privateName); };
    wg_button(privateInput, '<#AWG_Generate#>', function() { wg_generate(privateName); });
    wg_secret(privateInput);
    var publicInput = wg_input(table, privateName.replace(/private$/, 'public'), '<#AWG_Public#>', 'text', '<#AWG_PublicHint#>');
    publicInput.readOnly = true;
    wg_button(publicInput, '<#AWG_Copy#>', function() { wg_copy(publicInput); });
    if (role === 'vpnc') {
        var psk = wg_input(table, 'vpnc_wg_if_preshared', '<#AWG_Preshared#>', 'password', '<#AWG_PresharedHint#>');
        psk.maxLength = 44;
        wg_button(psk, '<#AWG_Generate#>', function() { wg_generate('vpnc_wg_if_preshared', 'genpsk'); });
        wg_secret(psk);
        wg_input(table, 'vpnc_wg_peer_public', '<#AWG_PeerPublic#>', 'text', '<#AWG_PeerPublicHint#>').maxLength = 44;
        wg_input(table, 'vpnc_wg_peer_endpoint', '<#AWG_Endpoint#>', 'text', '<#AWG_EndpointHint#>');
        wg_input(table, 'vpnc_wg_peer_port', '<#OVPN_Port#>', 'text', '<#AWG_PortHint#>');
        wg_input(table, 'vpnc_wg_peer_keepalive', 'PersistentKeepalive', 'text', '<#AWG_KeepaliveHint#>');
        wg_input(table, 'vpnc_wg_peer_allowedips', 'AllowedIPs', 'text', '<#AWG_AllowedIPsHint#>');
        wg_input(table, 'vpnc_wg_if_dns', 'DNS', 'text', '<#AWG_DNSHint#>');
    } else {
        wg_input(table, 'vpns_wg_port', '<#OVPN_Port#>', 'text', '<#AWG_PortHint#>');
        wg_input(table, 'vpns_wg_ext_addr', '<#AWG_Endpoint#>', 'text', '<#AWG_ServerEndpointHint#>');
        wg_textarea(table, 'scripts.vpns_post_script.sh', '<#AWG_ServerPostScript#>', '<#AWG_PostScriptHint#>');
        var keyCell = document.form.vpns_pass_x_0;
        keyCell.maxLength = 44;
        wg_button(keyCell, '<#AWG_Generate#>', function() { wg_generate('vpns_pass_x_0'); });
        keyCell.parentNode.lastChild.id = 'wg_client_genkey';
    }
    wg_input(table, role + '_wg_mtu', 'MTU', 'text', '<#AWG_MTUHint#>');
    if (found_app_awg()) {
        var awg = wg_group(table, 'AmneziaWG 3.1 — <#AWG_ConfigHint#>', true);
        var hints = {
            jc: '<#AWG_JcHint#>', jmin: '<#AWG_JSizeHint#>', jmax: '<#AWG_JSizeHint#>',
            headerprotectionkey: '<#AWG_HeaderKeyHint#>', contentpaddingaddition: '<#AWG_PaddingHint#>',
            randomtrailers: '<#AWG_TrailersHint#>', disablecookies: '<#AWG_CookiesHint#>',
            rekeyaftertime: '<#AWG_RekeyHint#>', rekeytimeout: '<#AWG_RetryHint#>',
            rejectaftertime: '<#AWG_RejectHint#>', keepalivetimeout: '<#AWG_TimeoutHint#>',
            maxhandshakeattempts: '<#AWG_AttemptsHint#>'
        };
        var groups = [
            ['<#AWG_Junk#>', ['jc', 'jmin', 'jmax']],
            ['<#AWG_Headers#>', ['headerprotectionkey', 'contentpaddingaddition', 'randomtrailers',
                'disablecookies', 'h1', 'h2', 'h3', 'h4', 's1', 's2', 's3', 's4']],
            ['<#AWG_Obfuscation#>', ['i1', 'i2', 'i3', 'i4', 'i5']],
            ['<#AWG_Timeouts#>', ['rekeyaftertime', 'rekeytimeout', 'rejectaftertime',
                'keepalivetimeout', 'maxhandshakeattempts']]
        ];
        groups.forEach(function(group) {
            var fields = wg_group(awg, group[0], true);
            group[1].forEach(function(field) {
                var input = wg_input(fields, role + '_awg_' + field, field,
                    field === 'headerprotectionkey' ? 'password' : 'text', hints[field] ||
                    (/^h/.test(field) ? '<#AWG_HHint#>' : /^s/.test(field) ? '<#AWG_SHint#>' : '<#AWG_IHint#>'));
                if (/^(randomtrailers|disablecookies)$/.test(field)) {
                    var select = document.createElement('select');
                    select.name = input.name; select.className = 'input';
                    ['<#btn_Disable#>', '<#checkbox_Yes#>'].forEach(function(label, index) {
                        var option = document.createElement('option'); option.value = index;
                        option.textContent = label; select.appendChild(option);
                    });
                    select.value = input.value;
                    input.parentNode.replaceChild(select, input);
                } else if (field === 'headerprotectionkey') {
                    input.maxLength = 44;
                    wg_button(input, '<#AWG_Generate#>', function() { wg_generate(input.name); });
                    wg_secret(input);
                }
            });
        });
    }
    if (role === 'vpnc') {
        wg_clients(table);
        wg_textarea(table, 'scripts.vpnc_remote_network.list', '<#AWG_RemoteNetworks#>', '<#AWG_RemoteHint#>');
        if (wgSettings.ipset_supported)
            wg_textarea(table, 'scripts.vpnc_domains.list', '<#AWG_Domains#>', '<#AWG_DomainsHint#>').maxLength = 32768;
        wg_textarea(table, 'scripts.vpnc_exclude_network.list', '<#AWG_ExcludeNetworks#>', '<#AWG_ExcludeHint#>');
        wg_textarea(table, 'scripts.vpnc_post_script.sh', '<#AWG_PostScript#>', '<#AWG_PostScriptHint#>');
    }
    var base = document.getElementById(role === 'vpnc' ? 'tbl_vpnc_config' : 'tbl_vpn_config');
    base.parentNode.insertBefore(table, base.nextSibling);
    // File contents are JSON-escaped by httpd; do not expose them via innerHTML.
    Object.keys(wgSettings).forEach(function(name) {
        if (document.form.elements[name]) document.form.elements[name].value = wgSettings[name];
    });
    if (!login_safe()) $j(table).find('input, textarea, select, button').prop('disabled', true);
    if (role !== 'vpnc') table.parentNode.insertBefore(status, table.nextSibling);
    wgStatusTimer = setTimeout(wg_refresh_status, 1000);
}

function wg_toggle(role, enabled, selected) {
    if (!found_app_wg()) return;
    var active = enabled && selected;
    var mode = role + ':' + !!enabled + ':' + !!selected;
    if (mode !== wgStatusMode) {
        $j('#tbl_' + role + '_wg .help_tooltip').popover('hide');
        wgStatusMode = mode;
        wgStatusGeneration++;
        wgClientState = null;
    }
    $j('#tbl_' + role + '_wg, #wg_status').toggle(!!active);
    $j('#tbl_' + role + '_wg').find('input, textarea, select, button').each(function() {
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
                wg_reveal(networks); alert('<#AWG_InvalidConfig#>'); networks.focus(); return false;
            }
        }
        var domains = document.form.elements['scripts.vpnc_domains.list'];
        if (domains && !domains.disabled && !wg_valid_domains(domains.value)) {
            wg_reveal(domains); alert('<#AWG_InvalidDomains#>'); domains.focus(); return false;
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
        if (!/^\d+$/.test(jc.value) || +jc.value > 128) wg_reveal(jc);
        if (!/^\d+$/.test(jmin.value) || +jmin.value > 1024) wg_reveal(jmin);
        if (!/^\d+$/.test(jmax.value) || +jmax.value < +jmin.value || +jmax.value > 1024) wg_reveal(jmax);
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
                var range = value.match(/^s[1-4]$/.test(field) ? /^(\d+)$/ : /^(\d+)(?:-(\d+))?$/);
                if (range && +range[1] <= max && (!range[2] || (+range[2] >= +range[1] && +range[2] <= max))) continue;
            }
            wg_reveal(input); alert('<#AWG_InvalidConfig#>'); input.focus(); return false;
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

function wg_valid_domains(value) {
    return value.replace(/#.*$/gm, '').split(/\r\n|\n|\r/).every(function(domain) {
        domain = domain.trim();
        if (!domain) return true;
        domain = domain.replace(/\.$/, '');
        return domain.length <= 253 && domain.indexOf('.') > 0 && !/^[\d.]+$/.test(domain) &&
            domain.split('.').every(function(label) {
                return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label);
            });
    });
}

function wg_parse_conf(text) {
    var result = {interface: {}, peer: {}}, section = '', peers = 0, interfaces = 0;
    if (typeof text !== 'string' || /\x00/.test(text)) throw new Error('<#AWG_InvalidConfig#>');
    text.replace(/^\uFEFF/, '').split(/\r\n|\n|\r/).forEach(function(line) {
        line = line.replace(/#.*$/, '').trim();
        if (!line || /^[#;]/.test(line)) return;
        if (/^\[Interface\]$/i.test(line)) { section = 'interface'; interfaces++; return; }
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
        if (Object.prototype.hasOwnProperty.call(result[section], name))
            throw new Error('<#AWG_InvalidConfig#>');
        result[section][name] = pair[2].trim();
    });
    if (interfaces !== 1 || peers !== 1 || !result.interface.privatekey || !result.interface.address ||
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
    var sequence = ++wgImportSequence;
    var result = document.getElementById('wg_import_result');
    function failure(message) {
        if (sequence !== wgImportSequence) return;
        if (result) { result.textContent = message; result.style.display = ''; }
        alert(message);
    }
    if (input.files[0].size > 65536) { failure('<#AWG_InvalidConfig#>'); return; }
    var reader = new FileReader();
    reader.onload = function(event) {
        try {
            var config = wg_parse_conf(event.target.result);
            function apply(defaults) {
                if (sequence !== wgImportSequence || !login_safe()) return;
                try {
                    wg_apply_conf(config, defaults);
                    if (result) { result.textContent = '<#AWG_Imported#>'; result.style.display = ''; }
                } catch (error) { failure(error.message); }
            }
            if (!found_app_awg()) apply({});
            else $j.getJSON('/amneziawg.json', function(defaults) {
                if (!Array.isArray(defaults) || !defaults[0] || typeof defaults[0] !== 'object' ||
                    !wgAwgFields.every(function(field) { return Object.prototype.hasOwnProperty.call(defaults[0], field); }))
                    failure('<#AWG_DefaultsError#>');
                else apply(defaults[0]);
            }).fail(function() { failure('<#AWG_DefaultsError#>'); });
        } catch (error) { failure(error.message); }
    };
    reader.onerror = function() { failure('<#AWG_FileError#>'); };
    try { reader.readAsText(input.files[0]); } catch (error) { failure('<#AWG_FileError#>'); }
}

function wg_state_label(state) {
    var labels = {disabled: '<#AWG_Disabled#>', stopped: '<#AWG_Stopped#>',
        connecting: '<#AWG_Connecting#>', connected: '<#Connected#>',
        running: '<#AWG_Running#>', error: '<#AWG_StartError#>', unknown: '<#AWG_StatusUnknown#>'};
    return Object.prototype.hasOwnProperty.call(labels, state) ? labels[state] : '<#AWG_StatusUnknown#>';
}

function wg_error_label(stage) {
    var labels = {config: '<#AWG_ErrorConfig#>', module: '<#AWG_ErrorModule#>',
        interface: '<#AWG_ErrorInterface#>', address: '<#AWG_ErrorAddress#>',
        setconf: '<#AWG_ErrorSetconf#>', link_up: '<#AWG_ErrorLinkUp#>',
        sysctl: '<#AWG_ErrorSysctl#>', endpoint: '<#AWG_ErrorEndpoint#>',
        routes: '<#AWG_ErrorRoutes#>', firewall: '<#AWG_ErrorFirewall#>', dns: '<#AWG_ErrorDNS#>'};
    return Object.prototype.hasOwnProperty.call(labels, stage) ? labels[stage] : '';
}

function wg_status_failure() {
    document.getElementById('wg_status').textContent = '<#AWG_StatusError#>';
    if (wgRole === 'vpnc') {
        wgClientState = '4';
        update_vpnc_status(wgClientState);
    }
}

function wg_refresh_status() {
    clearTimeout(wgStatusTimer);
    if (login_safe() && document.getElementById('wg_status') && document.form.elements[wgRole + '_type'].value === '3') {
        var generation = wgStatusGeneration, request = ++wgStatusRequest, iface = wgRole === 'vpnc' ? 'wg0' : 'wg1';
        $j.ajax({type: 'post', url: '/apply.cgi', dataType: 'json', timeout: 4000,
            data: {action_mode: ' wg_action ', action: 'status_json', iface: iface},
            success: function(response) {
                if (generation !== wgStatusGeneration || request !== wgStatusRequest || document.form.elements[wgRole + '_type'].value !== '3') return;
                var states = {disabled: '0', stopped: '0', connecting: '2', connected: '1', error: '3', running: '1', unknown: '4'};
                if (!response || typeof response.state !== 'string' || !Object.prototype.hasOwnProperty.call(states, response.state) || response.interface !== iface ||
                    typeof response.endpoint !== 'string' || typeof response.error !== 'string' ||
                    !['handshake', 'rx', 'tx'].every(function(key) {
                        return typeof response[key] === 'number' && isFinite(response[key]) && response[key] >= 0;
                    })) {
                    wg_status_failure(); return;
                }
                var text = wg_state_label(response.state), error = wg_error_label(response.error);
                if (error) text += ': ' + error;
                text += '\n<#AWG_Interface#>: ' + response.interface;
                if (response.endpoint) text += '\n<#AWG_Endpoint#>: ' + response.endpoint;
                if (response.handshake) text += '\n<#AWG_Handshake#>: ' + new Date(response.handshake * 1000).toLocaleString();
                text += '\nRX: ' + (response.rx || 0) + ' B / TX: ' + (response.tx || 0) + ' B';
                document.getElementById('wg_status').textContent = text;
                if (wgRole === 'vpnc') {
                    wgClientState = states[response.state];
                    update_vpnc_status(wgClientState);
                    document.getElementById('col_vpnc_wg_state').title = error;
                }
            }, error: function() {
                if (generation === wgStatusGeneration && request === wgStatusRequest && document.form.elements[wgRole + '_type'].value === '3')
                    wg_status_failure();
            }
        });
        if (wgRole === 'vpns' && window.location.hash === '#cli') wg_refresh_clients();
    }
    wgStatusTimer = setTimeout(wg_refresh_status, 5000);
}

function wg_refresh_clients() {
    var generation = wgStatusGeneration;
    var table = document.querySelector('#wnd_vpns_cli table');
    var labels = ['<#VPNS_CName#>', '<#AWG_Address#>', '<#AWG_Endpoint#>', '<#AWG_Handshake#>', 'RX', 'TX'];
    var header = table.rows[0];
    header.textContent = '';
    labels.forEach(function(label) { var th = document.createElement('th'); th.textContent = label; header.appendChild(th); });
    $j.ajax({type: 'post', url: '/apply.cgi', dataType: 'json', timeout: 4000,
        data: {action_mode: ' wg_action ', action: 'clients'}, success: function(clients) {
            if (generation !== wgStatusGeneration || document.form.vpns_type.value !== '3' ||
                !Array.isArray(clients) || !clients.every(function(client) { return Array.isArray(client) && client.length >= 6; })) return;
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
