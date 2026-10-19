const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const api = {};
vm.createContext(api);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../qml/DockLayout.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), api);
let checks = 0;
function check(value, message) { assert.ok(value, message); checks++; }
for (const live of [false, true]) {
    const original = api.defaultState(live);
    check(api.valid(original, live), 'default layout is valid');
    const serialized = JSON.stringify(original);
    let state = api.move(original, 'queue', 'effects', 'center', 'test-group', null);
    check(api.owner(state, 'queue').id === 'effects', 'center drop groups only dragged tab');
    check(api.owner(state, 'params').id === 'settings', 'other source tabs stay put');
    check(api.owner(state, 'queue').active === 'queue', 'drop selects the moved tab');
    check(JSON.stringify(original) === serialized, 'operation does not mutate original');
    check(api.valid(state, live), 'grouped state remains valid');
    for (const zone of ['left', 'right', 'top', 'bottom']) {
        state = api.move(original, 'queue', 'program', zone, 'split-' + zone, null);
        check(api.valid(state, live), 'valid ' + zone + ' split');
        check(api.owner(state, 'queue').id === 'split-' + zone, 'edge creates a separate group');
        check(api.owner(state, 'params').id === 'settings', 'split preserves other source tabs');
        const rects = api.placements(state, 1440, 800);
        check(Object.keys(rects.groups).length === api.groups(state.root).length, 'every group has geometry');
        for (const r of Object.values(rects.groups))
            check(r.width >= 0 && r.height >= 0 && r.x >= 0 && r.y >= 0, 'nonnegative geometry');
    }
    state = api.move(original, 'queue', '', 'float', 'float-queue',
        { x: 30, y: 40, width: 380, height: 520 });
    check(api.valid(state, live), 'floating state is valid');
    check(state.floating.length === 1 && state.floating[0].tabs.length === 1, 'only one tab floats');
    state = api.move(state, 'queue', 'settings', 'center', 'return-queue', null);
    check(state.floating.length === 0, 'return removes empty floating group');
    check(api.valid(state, live), 'returned layout is valid');
    check(api.move(original, 'preview', '', 'float', 'bad', {}) === original, 'preview cannot cross QRhi devices');
    check(api.move(original, 'queue', 'missing', 'center', 'bad', null) === original, 'missing target rejected');
    check(api.move(original, 'unknown', 'effects', 'center', 'bad', null) === original, 'unknown panel rejected');
    const invalid = api.copy(original);
    invalid.root.ratio = NaN;
    check(!api.valid(invalid, live), 'non-finite saved ratio rejected');
    const duplicate = api.copy(original);
    api.owner(duplicate, 'queue').tabs.push('effects');
    check(!api.valid(duplicate, live), 'duplicate panel rejected');
    const unknown = api.copy(original);
    api.owner(unknown, 'queue').tabs.push('unknown');
    check(!api.valid(unknown, live), 'unknown persisted panel rejected');
    state = api.hide(original, 'presets');
    check(!api.owner(state, 'presets'), 'inactive tab can be hidden');
    check(api.owner(original, 'presets') !== null, 'hide does not mutate original');
    state = api.show(state, 'presets', live, 'restore-presets');
    check(api.owner(state, 'presets').active === 'presets', 'show restores and selects tab');
    for (const panel of api.panelIds) state = api.hide(state, panel);
    check(state.root === null && state.floating.length === 0, 'empty splits collapse safely');
    check(api.valid(state, live), 'fully hidden layout remains valid');
    for (const panel of api.panelIds.filter(p => !live || !['timeline', 'levels'].includes(p))) {
        state = api.show(state, panel, live, 'restore-' + panel);
        check(api.valid(state, live), 'restored panel leaves valid layout');
    }
    check(api.owner(state, 'preview') && !state.floating.includes(api.owner(state, 'preview')),
        'preview restores into main window');
    check(api.show(original, 'unknown', live, 'bad') === original, 'unknown show rejected');
    if (live) check(api.show(original, 'timeline', live, 'bad') === original, 'live timeline stays unavailable');
    state = original;
    for (let i = 0; i < 100; i++) {
        const movable = api.panelIds.filter(p => p !== 'preview' && (!live || !['timeline', 'levels'].includes(p)));
        const panel = movable[i % movable.length];
        const target = api.groups(state.root)[i % api.groups(state.root).length];
        const zones = ['center', 'left', 'right', 'top', 'bottom'];
        const next = api.move(state, panel, target.id, zones[i % zones.length], 'iteration-' + i, null);
        check(api.valid(next, live), 'repeated moves retain every panel exactly once');
        state = next;
    }
}
for (const height of [800, 600, 440]) {
    const state = api.defaultState(false);
    const saved = JSON.stringify(state);
    const rect = api.placements(state, 960, height).groups.timeline;
    check(rect.height >= 256, 'default timeline keeps useful tracks at workspace height ' + height);
    check(JSON.stringify(state) === saved, 'adaptive geometry does not rewrite saved layout');
    check(Math.abs(api.placements(state, 960, height, false).groups.timeline.height - (height - 6) * 0.24) < 0.001,
        'explicit user sizing disables adaptation even at the default ratio');
    api.setRatio(state.root, 'rows', 0.66);
    check(Math.abs(api.placements(state, 960, height).groups.timeline.height - (height - 6) * 0.34) < 0.001,
        'customized split stays proportional, including the old default ratio');
}
console.log(`Dock layout: ${checks} checks passed`);
