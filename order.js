// Order and visibility of items, shared by the daemon and the settings.
//
// Each list is stored as an array of strings: "id" for a shown item, "-id" for
// a hidden one, in the chosen order. Unknown ids are dropped and missing ones
// (added in later versions) go to the end, hidden.
.pragma library

const PANEL_IDS = ["batteryIcon", "batteryText", "signalIcon", "signalText", "operator", "title", "media", "notifications"]
const SECTION_IDS = ["battery", "network", "bluetooth"]
const TAB_IDS = ["status", "notifications", "player", "calls"]

const PANEL_DEFAULT = ["batteryIcon", "batteryText", "signalIcon", "operator", "-signalText", "-title", "-media", "notifications"]
const SECTION_DEFAULT = ["battery", "network", "bluetooth"]
const TAB_DEFAULT = ["status", "notifications", "player", "calls"]

function parse(entries, ids) {
    const items = []
    const seen = {}
    const count = entries ? entries.length : 0
    for (let i = 0; i < count; ++i) {
        const raw = String(entries[i])
        const hidden = raw.startsWith("-")
        const id = hidden ? raw.slice(1) : raw
        if (ids.indexOf(id) < 0 || seen[id])
            continue
        seen[id] = true
        items.push({ id: id, shown: !hidden })
    }
    for (const id of ids) {
        if (!seen[id])
            items.push({ id: id, shown: false })
    }
    return items
}

function serialize(items) {
    return items.map(item => (item.shown ? "" : "-") + item.id)
}

function shown(entries, ids) {
    return parse(entries, ids).filter(item => item.shown).map(item => item.id)
}
