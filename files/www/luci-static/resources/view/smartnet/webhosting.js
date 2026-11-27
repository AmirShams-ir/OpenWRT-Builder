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
            E('p', {}, _('General-purpose hosting for static Vue/Vite, React and other frontend builds. AmirNote is one possible hosted app, not the hosting root.')),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Device')),
                E('p', {}, _('Model: ') + model),
                E('p', {}, _('Architecture: ') + arch),
                E('p', {}, _('Memory: ') + mem)
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Hosting layout')),
                E('p', {}, _('Persistent app root: /home/smartnet/webhosting/apps/')),
                E('p', {}, _('Each app has public/, data/, db/, logs/ and config/ directories.')),
                E('p', {}, _('Static app URL: http://<LAN-IP>:8080/apps/<app-slug>/')),
                E('p', {}, _('Nginx uses port 8080; existing LuCI/uHTTPd ports are not changed.'))
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Create and publish an app')),
                E('p', {}, _('Run as root: smartnet-webhosting create <slug>')),
                E('p', {}, _('Build Vue/Vite or React on a development PC/CI, then copy the production build into the app public/ directory.')),
                E('p', {}, _('List apps: smartnet-webhosting list')),
                E('p', {}, _('If Docker is installed, container-run supports only locally available Linux 386/i386 images and checks the image architecture.'))
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Backend and database')),
                E('p', {}, _('Dynamic backend/container runtimes must be verified for this device architecture before deployment. The CLI can manage per-app containers when Docker is available, but only compatible Linux 386/i386 images are accepted.')),
                E('p', {}, _('SQLite is app-local: an app can create /home/smartnet/webhosting/apps/<slug>/db/app.sqlite using its own SQLite library.')),
                E('p', {}, _('Module 08 installs sqlite3-cli and the SQLite runtime library. SQLite has no separate daemon or listening port.')),
                E('p', {}, _('Show an app database path: smartnet-webhosting db-path <slug> ; check an existing database: smartnet-webhosting db-check <slug>.')),
                E('p', {}, _('Do not expose data/, db/, logs/ or config/ through the web server. Keep secrets out of frontend build files.')),
                E('p', {}, _('AmirNote currently needs an API and storage adapter for its Vercel Functions/Blob dependencies; static files alone do not provide those services.'))
            ])
        ]);
    },
    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
