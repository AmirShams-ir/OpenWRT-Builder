'use strict';
'require view';
'require rpc';

var callSystemInfo = rpc.declare({
    object: 'system',
    method: 'info',
    expect: {}
});

var callBoard = rpc.declare({
    object: 'system',
    method: 'board',
    expect: {}
});

return view.extend({
    load: function() {
        return Promise.all([
            callSystemInfo().catch(function() { return {}; }),
            callBoard().catch(function() { return {}; })
        ]);
    },

    render: function(data) {
        var info = data[0] || {};
        var board = data[1] || {};
        var model = board.model || _('Unknown');
        var arch = board.system || _('Unknown');
        var mem = info.memory && info.memory.total
            ? Math.round(info.memory.total / 1048576) + ' MiB'
            : _('Unknown');

        return E('div', { 'class': 'cbi-map' }, [
            E('h2', _('Smart-Net WebApp Hosting')),
            E('p', {}, _('Hosting foundation for AmirNote and future Smart-Net web applications.')),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('System')),
                E('p', {}, _('Model: ') + model),
                E('p', {}, _('Architecture: ') + arch),
                E('p', {}, _('Memory total: ') + mem)
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Web server')),
                E('p', {}, _('Nginx site listener: http://192.168.12.1:8080/')),
                E('p', {}, _('LuCI remains on its existing uHTTPd ports.')),
                E('p', {}, _('Frontend root: /home/smartnet/webhosting/sites/amirnote')),
                E('p', {}, _('API upstream: 127.0.0.1:3000 (reserved; runtime pending)'))
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('AmirNote deployment')),
                E('p', {}, _('The current AmirNote API depends on Vercel Functions and Vercel Blob. A compatible API adapter and storage configuration are required before full operation.')),
                E('p', {}, _('Never expose BLOB_READ_WRITE_TOKEN in frontend files.'))
            ])
        ]);
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
