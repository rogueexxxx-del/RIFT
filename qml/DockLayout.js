.pragma library

// Workspace state contains panel ids only. Panel objects and engine state stay alive.
var panelIds = ["effects", "presets", "preview", "params", "clip", "color", "queue",
                "timeline", "levels", "controls", "audio"]

function group(id, tabs) {
    return { id: id, tabs: tabs, active: tabs[0] }
}

function split(id, axis, ratio, first, second) {
    return { id: id, axis: axis, ratio: ratio, first: first, second: second }
}

function defaultState(live) {
    var top = split("main", "horizontal", 0.20,
        group("effects", ["effects", "presets"]),
        split("center", "horizontal", 0.70, group("program", ["preview"]),
            group("settings", ["params", "clip", "color", "queue", "controls", "audio"])))
    return { version: 1, root: live ? top : split("rows", "vertical", 0.76, top,
        split("bottom", "horizontal", 0.87, group("timeline", ["timeline"]),
            group("levels", ["levels"]))), floating: [] }
}

function copy(value) { return JSON.parse(JSON.stringify(value)) }

function groups(node) {
    if (!node) return []
    return node.tabs ? [node] : groups(node.first).concat(groups(node.second))
}

function allGroups(state) { return groups(state.root).concat(state.floating) }

function find(state, id) {
    return allGroups(state).find(function(g) { return g.id === id }) || null
}

function owner(state, panel) {
    return allGroups(state).find(function(g) { return g.tabs.indexOf(panel) >= 0 }) || null
}

function remove(node, panel) {
    if (!node) return null
    if (node.tabs) {
        node.tabs = node.tabs.filter(function(p) { return p !== panel })
        if (!node.tabs.length) return null
        if (node.tabs.indexOf(node.active) < 0) node.active = node.tabs[0]
        return node
    }
    node.first = remove(node.first, panel)
    node.second = remove(node.second, panel)
    if (!node.first) return node.second
    if (!node.second) return node.first
    return node
}

function replace(node, id, replacement) {
    if (node.id === id) return replacement
    if (!node.tabs) {
        node.first = replace(node.first, id, replacement)
        node.second = replace(node.second, id, replacement)
    }
    return node
}

function move(state, panel, targetId, zone, newId, geometry) {
    if (panel === "preview" || panelIds.indexOf(panel) < 0) return state
    var source = owner(state, panel)
    var target = find(state, targetId)
    if (!source || (zone !== "float" && !target)) return state
    if (["center", "left", "right", "top", "bottom", "float"].indexOf(zone) < 0)
        return state
    if (zone !== "float" && source.id === targetId && source.tabs.length === 1)
        return state
    if (zone !== "center" && zone !== "float" && state.floating.indexOf(target) >= 0)
        return state

    var next = copy(state)
    next.root = remove(next.root, panel)
    next.floating = next.floating.filter(function(g) { return remove(g, panel) !== null })
    if (zone === "float") {
        var floating = group(newId, [panel])
        floating.x = geometry.x
        floating.y = geometry.y
        floating.width = geometry.width
        floating.height = geometry.height
        next.floating.push(floating)
        return next
    }
    target = find(next, targetId)
    if (!target) return state
    if (zone === "center") {
        target.tabs.push(panel)
        target.active = panel
    } else {
        var before = zone === "left" || zone === "top"
        var added = group(newId, [panel])
        var branch = split(newId + "-split",
            zone === "left" || zone === "right" ? "horizontal" : "vertical",
            0.5, before ? added : target, before ? target : added)
        next.root = replace(next.root, targetId, branch)
    }
    return next
}

function hide(state, panel) {
    if (!owner(state, panel)) return state
    var next = copy(state)
    next.root = remove(next.root, panel)
    next.floating = next.floating.filter(function(g) { return remove(g, panel) !== null })
    return next
}

function show(state, panel, live, newId) {
    var home = owner(defaultState(live), panel)
    if (!home) return state
    if (owner(state, panel)) return select(state, panel)
    var next = copy(state)
    var target = find(next, home.id)
    if (target && groups(next.root).indexOf(target) >= 0) {
        target.tabs.push(panel)
        target.active = panel
    } else {
        var added = group(find(next, home.id) ? newId : home.id, [panel])
        if (!next.root) next.root = added
        else {
            var before = panel === "effects" || panel === "presets"
            next.root = split(newId + "-split",
                panel === "timeline" || panel === "levels" ? "vertical" : "horizontal",
                before ? 0.25 : 0.75, before ? added : next.root, before ? next.root : added)
        }
    }
    return next
}

function select(state, panel) {
    var next = copy(state)
    var g = owner(next, panel)
    if (g) g.active = panel
    return next
}

function setRatio(node, id, ratio) {
    if (!node || node.tabs) return
    if (node.id === id) node.ratio = Math.max(0.12, Math.min(0.88, ratio))
    else {
        setRatio(node.first, id, ratio)
        setRatio(node.second, id, ratio)
    }
}

function geometry(node, x, y, width, height, result, adaptDefault) {
    if (!node) return
    if (node.tabs) {
        result.groups[node.id] = { x: x, y: y, width: width, height: height }
        return
    }
    var horizontal = node.axis === "horizontal"
    var size = Math.max(0, (horizontal ? width : height) - 6)
    var edge = size * node.ratio
    // Default rows reserve a usable video/audio pair in logical pixels at high DPI.
    // Saved custom ratios remain proportional; no layout data is rewritten.
    if (adaptDefault !== false && node.id === "rows" && !horizontal
        && node.ratio === 0.76 && node.second.id === "bottom"
        && groups(node.second).some(function(g) { return g.tabs.indexOf("timeline") >= 0 }))
        edge = Math.min(edge, size - Math.min(256, size * 0.66))
    result.handles.push({ id: node.id, axis: node.axis, origin: horizontal ? x : y,
        extent: size, x: horizontal ? x + edge : x, y: horizontal ? y : y + edge,
        width: horizontal ? 6 : width, height: horizontal ? height : 6 })
    geometry(node.first, x, y, horizontal ? edge : width, horizontal ? height : edge, result, adaptDefault)
    geometry(node.second, horizontal ? x + edge + 6 : x, horizontal ? y : y + edge + 6,
        horizontal ? size - edge : width, horizontal ? height : size - edge, result, adaptDefault)
}

function placements(state, width, height, adaptDefault) {
    var result = { groups: {}, handles: [] }
    geometry(state.root, 0, 0, Math.max(0, width), Math.max(0, height), result, adaptDefault)
    return result
}

function valid(state, live) {
    if (!state || state.version !== 1 || state.root === undefined || !Array.isArray(state.floating)
        || state.floating.length > panelIds.length) return false
    var seenPanels = [], seenIds = []
    function visit(node, depth, floating) {
        if (!node || depth > 12 || typeof node.id !== "string" || !/^[\w-]{1,64}$/.test(node.id)
            || seenIds.indexOf(node.id) >= 0) return false
        seenIds.push(node.id)
        if (node.tabs) {
            if (!Array.isArray(node.tabs) || !node.tabs.length
                || node.tabs.indexOf(node.active) < 0) return false
            for (var i = 0; i < node.tabs.length; ++i) {
                var p = node.tabs[i]
                if (panelIds.indexOf(p) < 0 || seenPanels.indexOf(p) >= 0
                    || (floating && p === "preview")) return false
                seenPanels.push(p)
            }
            return true
        }
        return !floating && ["horizontal", "vertical"].indexOf(node.axis) >= 0
            && typeof node.ratio === "number" && isFinite(node.ratio)
            && node.ratio >= 0.12 && node.ratio <= 0.88
            && visit(node.first, depth + 1, false) && visit(node.second, depth + 1, false)
    }
    if (state.root !== null && !visit(state.root, 0, false)) return false
    for (var i = 0; i < state.floating.length; ++i) {
        var g = state.floating[i]
        if (!visit(g, 0, true)) return false
        for (var k of ["x", "y", "width", "height"])
            if (typeof g[k] !== "number" || !isFinite(g[k]) || Math.abs(g[k]) > 50000)
                return false
        if (g.width < 180 || g.height < 100) return false
    }
    var expected = panelIds.filter(function(p) { return !live || (p !== "timeline" && p !== "levels") })
    return seenPanels.every(function(p) { return expected.indexOf(p) >= 0 })
}
