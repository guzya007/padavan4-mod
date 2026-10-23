/**
 * Client dropdown adapted from nilabsent/padavan-ng's multiSelectDropdown.
 * Original author: nil. MIT licence (http://opensource.org/licenses/MIT).
 * Use text nodes for client names and keep initial values unchanged until edited.
 */
(function($) {
    $.fn.multiSelectDropdown = function(methodOrOptions) {
        if (typeof methodOrOptions === 'string') {
            var inst = this.data('multiSelectDropdown');
            if (!inst) return [];
            if (methodOrOptions === 'getAllItems') {
                return inst.list.find('input[type=checkbox]').map(function() {
                    return {text: this.value, title: this.title, checked: this.checked};
                }).get();
            }
            if (methodOrOptions === 'getSelected') return inst.selected();
            if (methodOrOptions === 'setSelected') {
                var values = arguments[1] || [];
                inst.list.find('input[type=checkbox]').each(function() {
                    this.checked = values.indexOf(this.value) >= 0;
                });
                inst.update();
                return this;
            }
            return this;
        }
        var settings = $.extend({items: [], placeholder: '', allowAdd: true, allowDelete: true,
            addSuggestionText: 'Add', allowedAlert: '', removeSpaces: false, width: null}, methodOrOptions);
        return this.each(function() {
            var wrapper = $(this).addClass('msd-dropdown');
            if (settings.width) wrapper.css('width', settings.width);
            // Static markup only: translations and network-map data are assigned as text.
            wrapper.html('<div class="msd-header"><input type="text" class="msd-input" autocomplete="off" spellcheck="false">' +
                '<button type="button" class="msd-chevron" aria-label="Select">&#9662;</button></div>' +
                '<div class="msd-content"><div class="msd-item-list"></div></div>');
            var input = wrapper.find('.msd-input'), list = wrapper.find('.msd-item-list');
            input.prop('placeholder', settings.placeholder);
            var suggestion = $('<div class="msd-add-suggestion" style="display:none"></div>').appendTo(list);
            var previous = [];
            function selected() {
                return list.find('input[type=checkbox]:checked').map(function() { return this.value; }).get();
            }
            function update(force, silent) {
                var values = selected();
                input.val(values.join(', ')).prop('placeholder', settings.placeholder);
                if (!silent && !input.prop('disabled') && typeof settings.onChange === 'function' &&
                    (force || values.join(',') !== previous.join(','))) settings.onChange.call(wrapper, values);
                previous = values;
            }
            function createItem(item) {
                var container = $('<div class="msd-item"></div>');
                if (settings.allowDelete) {
                    $('<button type="button" class="msd-delete" aria-label="Delete">&times;</button>')
                        .appendTo(container).on('click', function(e) {
                            e.stopPropagation();
                            if (input.prop('disabled')) return;
                            container.remove(); update(true);
                        });
                }
                var label = $('<label class="msd-label"></label>').appendTo(container);
                $('<input type="checkbox">').val(item.text).prop('checked', !!item.checked)
                    .prop('title', item.title || '').appendTo(label).on('change', function() { update(); });
                $('<span></span>').text(item.text).appendTo(label);
                $('<span class="msd-title"></span>').text(item.title || '').appendTo(label);
                list.append(container);
            }
            function hide() {
                wrapper.removeClass('msd-show');
                list.children('.msd-item').show(); suggestion.hide(); update();
            }
            function show() {
                if (input.prop('disabled')) return;
                $('.msd-dropdown.msd-show').not(wrapper).removeClass('msd-show');
                wrapper.addClass('msd-show');
            }
            function filter() {
                var query = $.trim(input.val()).toLowerCase(), exact = false;
                list.children('.msd-item').each(function() {
                    var item = $(this), value = item.find('input').val().toLowerCase();
                    if (value === query) exact = true;
                    item.toggle(!query || item.text().toLowerCase().indexOf(query) >= 0);
                });
                suggestion.text(settings.addSuggestionText + ' "' + input.val() + '"')
                    .toggle(!!query && settings.allowAdd && !exact);
                show();
            }
            function add() {
                if (input.prop('disabled') || !settings.allowAdd) return;
                var value = $.trim(input.val());
                if (settings.removeSpaces) value = value.replace(/\s+/g, '');
                if (!value) return;
                if ((settings.validateItem && !settings.validateItem(value)) ||
                    (settings.allowedItems && !(new RegExp(settings.allowedItems)).test(value))) {
                    if (settings.allowedAlert) alert(settings.allowedAlert);
                    return;
                }
                var exists = false;
                list.find('input[type=checkbox]').each(function() {
                    if (this.value === value) { this.checked = true; exists = true; }
                });
                if (!exists) createItem({text: value, checked: true});
                update(true); input.val(''); filter(); input.focus();
            }
            input.prop('readOnly', !settings.allowAdd).on('focus', function() {
                if (input.prop('disabled')) return;
                input.val(''); list.children('.msd-item').show(); suggestion.hide(); show();
            }).on('input', filter).on('keydown', function(e) {
                if (e.key === 'Enter' || e.keyCode === 13) { e.preventDefault(); add(); }
                if (e.key === 'Escape' || e.keyCode === 27) { e.preventDefault(); hide(); input.blur(); }
            });
            suggestion.on('click', add);
            wrapper.find('.msd-chevron').on('click', function() {
                if (input.prop('disabled')) return;
                if (wrapper.hasClass('msd-show')) hide();
                else input.focus();
            });
            $(document).on('mousedown', function(e) {
                if (!$(e.target).closest(wrapper).length) hide();
            });
            settings.items.forEach(function(item) {
                if (typeof item === 'string') item = {text: item};
                if (item && item.text) createItem(item);
            });
            wrapper.data('multiSelectDropdown', {list: list, selected: selected, update: update});
            update(false, true);
        });
    };
})(jQuery);
