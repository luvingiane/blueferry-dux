// iPhone Status daemon: the iPhone's battery, signal, notifications, player and
// recent calls, read from BlueFerry. The shell creates it once; the bar
// widgets read it through the "controller" global variable.
//
// Everything goes through BlueFerry's D-Bus API (session bus, object
// /io/weirdware/BlueFerry), called with gdbus: GetStatus for battery and
// network, GetNowPlaying and SendMediaCommand for the player, ListCallHistory
// and GetContactPhoto for calls, ListEvents for SMS. BlueFerry sends app
// notifications to the desktop as transient ones that the shell does not keep:
// the daemon copies them from the shell's notification server as they arrive.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import "order.js" as Order
import "util.js" as Util

Scope {
    id: root

    property var pluginService: null
    property string pluginId: "iphoneStatus"

    readonly property var gdbusCall: ["gdbus", "call", "--session", "--timeout", "5",
        "--dest", "io.weirdware.BlueFerry", "--object-path", "/io/weirdware/BlueFerry", "--method"]
    readonly property string dash: "—"
    readonly property int callsShown: 15
    readonly property int messagesShown: 20
    readonly property int appNotificationsKept: 50

    // --- Settings ----------------------------------------------------------

    property var config: ({})

    function loadConfig() {
        const get = (key, fallback) => pluginService ? pluginService.loadPluginData(pluginId, key, fallback) : fallback
        config = {
            title: String(get("title", "") || ""),
            panelItems: get("panelItems", Order.PANEL_DEFAULT),
            popupTabs: get("popupTabs", Order.TAB_DEFAULT),
            statusSections: get("statusSections", Order.SECTION_DEFAULT),
            emojiFont: String(get("emojiFont", "Apple Color Emoji") || ""),
            notificationClick: String(get("notificationClick", "app") || "app"),
            onlineArtwork: get("onlineArtwork", true) !== false,
            airplayDuplicate: String(get("airplayDuplicate", "hide") || "hide")
        }
    }

    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadConfig()
        }
    }

    readonly property string title: (config.title || "").trim() || I18n.trFor("iphoneStatus", "iPhone")
    readonly property string emojiFont: config.emojiFont || ""
    readonly property var panelItems: Order.shown(config.panelItems, Order.PANEL_IDS)
    readonly property var statusSections: Order.shown(config.statusSections, Order.SECTION_IDS)
    readonly property var popupTabs: Order.shown(config.popupTabs, Order.TAB_IDS)
    readonly property bool onlineArtwork: config.onlineArtwork !== false
    readonly property string notificationClick: config.notificationClick || "app"

    // --- Phone status (GetStatus) ----------------------------------------

    property bool loaded: false
    property string error: ""            // not empty: the command failed or the daemon is off
    property bool connected: false       // the iPhone's BR/EDR or LE link is up
    property string connectivityDetail: ""
    property bool callsEnabled: false    // HFP calls are on in BlueFerry
    property date lastUpdate

    // GetStatus's phone_* keys; null when unknown.
    property var batteryLevel: null
    property var batterySource: null     // "gatt", "bluez" or "hfp"
    property var signalStrength: null    // 0-100, in steps of 20 over HFP
    property var networkName: null
    property var networkStatus: null

    // Phone reachable and data valid.
    readonly property bool active: loaded && error === "" && connected

    // Why the icons are dimmed; empty when all is well.
    readonly property string reason: {
        if (!loaded)
            return I18n.trFor("iphoneStatus", "Reading the status…")
        if (error !== "")
            return error
        if (!connected)
            return connectivityDetail !== ""
                ? I18n.trFor("iphoneStatus", "iPhone not connected (%1)").arg(connectivityDetail)
                : I18n.trFor("iphoneStatus", "iPhone not connected")
        return ""
    }

    readonly property string batteryText: batteryLevel === null ? dash
        : (batterySource === "hfp" ? "~" : "") + I18n.trFor("iphoneStatus", "%1 %").arg(batteryLevel)

    // 0-100 → 0-5 bars; -1 when unknown.
    readonly property int signalBars: signalStrength === null ? -1
        : Math.max(0, Math.min(5, Math.round(signalStrength / 20)))
    readonly property string signalText: signalBars < 0 ? dash
        : I18n.trFor("iphoneStatus", "%1 % (%2/5)").arg(signalStrength).arg(signalBars)

    // The operator without the truncated " Wi-Fi" suffix iOS adds during
    // Wi-Fi calling; wifiCalling says whether it was there.
    readonly property var networkParts: Util.splitWifiCalling(networkName)
    readonly property bool wifiCalling: networkParts.wifi
    readonly property string networkText: networkName === null || networkName === "" ? dash : networkParts.name

    // The iPhone does not report whether it is charging (its Battery Service
    // only has Battery Level, and HFP only the level), so it is estimated from
    // exact LE readings. Each rise marks the phone as charging and updates the
    // measured seconds per percentage point; when the next point does not come
    // within a few times that interval the estimate expires, so a phone that
    // stopped charging (unplugged at a plateau, full, or held at 80 % by iOS)
    // is no longer announced. A drop ends it at once.
    property bool charging: false
    property real secondsPerPoint: 0     // measured charging rate, 0 = not known yet
    property var chargeLevel: null       // last exact level
    property var chargeSource: null      // its source: "gatt" or "bluez"
    property var chargeRiseLevel: null   // level at the last rise
    property double chargeRiseAt: 0      // time of the last rise, ms
    property double exactSeenAt: 0       // time of the last exact reading, ms

    readonly property int chargeGapMs: 120000   // a gap this short keeps the estimate

    // How long without a new point before the estimate expires, in seconds.
    function chargeTimeout() {
        return secondsPerPoint > 0 ? Math.max(90, Math.min(1500, secondsPerPoint * 2.5)) : 300
    }

    function resetCharging() {
        charging = false
        secondsPerPoint = 0
        chargeRiseLevel = null
        chargeRiseAt = 0
    }

    function estimateCharging() {
        const now = Date.now()
        const exact = active && batteryLevel !== null && (batterySource === "gatt" || batterySource === "bluez")
        if (!exact) {
            // A failed read or a short disconnect keeps the estimate; a long
            // absence does not.
            if (exactSeenAt === 0 || now - exactSeenAt > chargeGapMs) {
                resetCharging()
                chargeLevel = null
                chargeSource = null
            }
            return
        }
        exactSeenAt = now
        // A new source (BlueZ's cached value against the live GATT one) is
        // not comparable with the previous reading.
        if (chargeLevel !== null && chargeSource === batterySource) {
            if (batteryLevel > chargeLevel) {
                // Only consecutive rises measure the rate: one after an
                // expired estimate starts over.
                if (charging && chargeRiseLevel !== null && batteryLevel > chargeRiseLevel) {
                    const perPoint = (now - chargeRiseAt) / 1000 / (batteryLevel - chargeRiseLevel)
                    secondsPerPoint = secondsPerPoint > 0 ? secondsPerPoint * 0.6 + perPoint * 0.4 : perPoint
                } else {
                    secondsPerPoint = 0
                }
                chargeRiseLevel = batteryLevel
                chargeRiseAt = now
                charging = true
            } else if (batteryLevel < chargeLevel) {
                resetCharging()
            }
        }
        chargeLevel = batteryLevel
        chargeSource = batterySource
        if (charging && (now - chargeRiseAt) / 1000 > chargeTimeout())
            resetCharging()
    }

    // "45 s" or "3 min", for the charging rate.
    function rateText(seconds) {
        return seconds < 90 ? I18n.trFor("iphoneStatus", "%1 s").arg(Math.round(seconds))
            : I18n.trFor("iphoneStatus", "%1 min").arg(Math.round(seconds / 60))
    }

    // How the Status tab and the tooltip describe the estimate.
    readonly property string chargingText: !charging ? ""
        : secondsPerPoint > 0 ? I18n.trFor("iphoneStatus", "probably charging, 1 % every %1").arg(rateText(secondsPerPoint))
        : I18n.trFor("iphoneStatus", "probably charging")

    readonly property string batteryIcon: !active || batteryLevel === null
        ? "battery_unknown" : Util.batteryIcon(batteryLevel, charging)
    readonly property string signalIcon: !active ? "signal_cellular_off" : Util.signalIcon(signalBars)

    // --- Player (GetNowPlaying, AirPlay over MPRIS) -----------------------

    property var nowPlaying: null        // the GetNowPlaying answer
    property double mediaFetchedAt: 0    // when it arrived, in ms
    property double clock: Date.now()    // ticks every second during playback

    // The iPhone's track over Bluetooth (AMS): title, artist, album, duration.
    readonly property var amsTrack: nowPlaying && nowPlaying.available === true && nowPlaying.track
        ? nowPlaying.track : null
    readonly property bool amsPlaying: amsTrack !== null && !!nowPlaying.player
        && nowPlaying.player.state === "playing"

    // shairport-sync (AirPlay to this computer), as an MPRIS player.
    readonly property var shairport: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) {
            if (players[i] && /ShairportSync/i.test(players[i].dbusName || ""))
                return players[i]
        }
        return null
    }
    readonly property var airplay: shairport ? {
        playing: shairport.isPlaying,
        title: shairport.trackTitle || "",
        artist: shairport.trackArtist || "",
        album: shairport.trackAlbum || "",
        // Only files in shairport-sync's cache.
        art: String(shairport.trackArtUrl || "").startsWith("file:///tmp/shairport-sync/")
            ? String(shairport.trackArtUrl) : "",
        length: shairport.lengthSupported && shairport.length > 0 ? shairport.length : 0
    } : null
    readonly property bool airplayPlaying: !!airplay && airplay.playing
    readonly property bool airplaySameTrack: !!airplay && amsTrack !== null
        && Util.sameTitle(airplay.title, amsTrack.title)
    // AirPlay plays a different track from the one AMS reports (another app,
    // for instance): that one is shown.
    readonly property bool showAirplay: airplayPlaying && !amsPlaying && !airplaySameTrack
        && airplay.title !== ""

    readonly property var track: showAirplay
        ? { title: airplay.title, artist: airplay.artist, album: airplay.album, duration: airplay.length }
        : amsTrack
    readonly property bool mediaAvailable: track !== null
    readonly property bool playing: showAirplay || amsPlaying || (airplayPlaying && airplaySameTrack)
    readonly property var player: nowPlaying && nowPlaying.player ? nowPlaying.player : null
    readonly property string mediaSource: showAirplay ? I18n.trFor("iphoneStatus", "AirPlay")
        : player && player.name ? I18n.trFor("iphoneStatus", "%1 · iPhone").arg(player.name)
        : I18n.trFor("iphoneStatus", "iPhone")
    readonly property var mediaCommands: nowPlaying && nowPlaying.supported_commands ? nowPlaying.supported_commands : []
    readonly property real mediaDuration: track && typeof track.duration === "number" ? track.duration : 0
    // AMS gives the elapsed time; shairport-sync does not, so without AMS there
    // is no bar.
    readonly property bool mediaHasProgress: !showAirplay && !!amsTrack && typeof amsTrack.elapsed === "number"
        && mediaDuration > 0
    readonly property real mediaElapsed: {
        if (!mediaHasProgress)
            return 0
        const rate = player && typeof player.rate === "number" ? player.rate : 1
        const extra = amsPlaying ? Math.max(0, clock - mediaFetchedAt) / 1000 * rate : 0
        return Math.min(amsTrack.elapsed + extra, mediaDuration)
    }
    readonly property bool hasVolume: !showAirplay && !!player && typeof player.volume === "number"
    readonly property string mediaText: !mediaAvailable ? ""
        : [track.title, track.artist].filter(part => !!part).join(" – ")

    // Artwork: shairport-sync's when it is the same track, otherwise the iTunes
    // search (when enabled); "" without artwork.
    property var artworkCache: ({})      // "artist|title" → URL, "" when missing
    readonly property string artworkKey: track ? (track.artist || "") + "|" + (track.title || "") : ""
    readonly property string artwork: {
        if (airplay && airplay.art !== "" && (showAirplay || airplaySameTrack))
            return airplay.art
        return onlineArtwork && artworkKey !== "" ? artworkCache[artworkKey] || "" : ""
    }
    onArtworkKeyChanged: fetchArtwork()
    onOnlineArtworkChanged: fetchArtwork()

    // The last error of a player command, shown for a few seconds.
    property string mediaError: ""

    // Whether a command is offered. While BlueFerry has no list of the
    // iPhone's commands yet, it is tried anyway.
    function canCommand(command) {
        return mediaCommands.length === 0 || mediaCommands.indexOf(command) >= 0
            || (command === "toggle" && mediaCommands.indexOf(amsPlaying ? "pause" : "play") >= 0)
    }

    // --- Recent calls (ListCallHistory, GetContactPhoto) -----------------

    property var calls: []               // [{direction, timestamp, address, name, contact_name}]
    property var photos: ({})            // number → data URI, "" without a photo
    property var photoQueue: []
    property bool photoBusy: false

    // --- Notifications: SMS (ListEvents) and apps (notification server) --

    property var messages: []            // [{kind, app, title, body, time}]
    property var appNotifications: []    // same keys, plus key and notifId
    property int unseen: 0               // arrived since the popup was last opened

    readonly property var notifications: messages.concat(appNotifications)
        .sort((a, b) => b.time - a.time)

    // --- Popups ------------------------------------------------------------

    // The bar widgets that have their popup open; while one is, the player is
    // read more often and new notifications do not count as unseen.
    property var openPopups: ({})
    property string lastTab: ""          // the popup reopens on the tab it was left on
    readonly property bool popupOpen: Object.keys(openPopups).length > 0

    function setPopupOpen(owner, open) {
        const key = String(owner)
        if (!!openPopups[key] === open)
            return
        const next = Object.assign({}, openPopups)
        if (open)
            next[key] = true
        else
            delete next[key]
        openPopups = next
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            unseen = 0
            refreshAll()
        }
    }

    // --- Text --------------------------------------------------------------

    function styled(text) {
        return Util.styled(text, emojiFont)
    }

    // "now", "5 min ago", "14:32", "yesterday 14:32", "Mon 14:32" or
    // "12/10/26".
    function timeText(date) {
        if (!(date instanceof Date) || isNaN(date.getTime()))
            return ""
        const now = new Date()
        const minutes = Math.floor((now - date) / 60000)
        if (minutes >= 0 && minutes < 1)
            return I18n.trFor("iphoneStatus", "now")
        if (minutes >= 1 && minutes < 60)
            return I18n.trFor("iphoneStatus", "%1 min ago").arg(minutes)
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const thatDay = new Date(date.getFullYear(), date.getMonth(), date.getDate())
        const diffDays = Math.round((today - thatDay) / 86400000)
        const time = Qt.formatTime(date, "hh:mm")
        if (diffDays <= 0)
            return time
        if (diffDays === 1)
            return I18n.trFor("iphoneStatus", "yesterday %1").arg(time)
        if (diffDays < 7)
            return Qt.locale().dayName(date.getDay(), Locale.ShortFormat) + " " + time
        return Qt.formatDate(date, "dd/MM/yy")
    }

    function durationText(seconds) {
        const total = Math.max(0, Math.floor(seconds))
        return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
    }

    function registrationText(status) {
        switch (status) {
        case "registered": return I18n.trFor("iphoneStatus", "Registered")
        case "roaming": return I18n.trFor("iphoneStatus", "Roaming")
        case "searching": return I18n.trFor("iphoneStatus", "Searching for a network…")
        case "unregistered": return I18n.trFor("iphoneStatus", "Not registered")
        case "denied": return I18n.trFor("iphoneStatus", "Registration denied")
        case "unknown": return I18n.trFor("iphoneStatus", "Unknown")
        case null: return dash
        default: return status
        }
    }

    function describeFailure(exitCode, stderr) {
        if (exitCode === 127 || /not found|No such file/i.test(stderr) && !/GDBus\.Error/.test(stderr))
            return I18n.trFor("iphoneStatus", "The gdbus command was not found")
        if (/ServiceUnknown|NameHasNoOwner|not provided by any/.test(stderr))
            return I18n.trFor("iphoneStatus", "BlueFerry is not running")
        if (/NoReply|Timeout|timed out/i.test(stderr))
            return I18n.trFor("iphoneStatus", "BlueFerry is not responding")
        if (/AccessDenied|NotAuthorized/.test(stderr))
            return I18n.trFor("iphoneStatus", "BlueFerry denied access to the status")
        const line = stderr.trim().split("\n")[0].replace(/^Error:\s*/, "").replace(/^GDBus\.Error:/, "")
        return line !== "" ? I18n.trFor("iphoneStatus", "Error: %1").arg(line)
            : I18n.trFor("iphoneStatus", "The command exited with code %1").arg(exitCode)
    }

    // --- Running commands --------------------------------------------------

    // Commands run without a shell: the arguments go to gdbus as they are.
    // LC_ALL=C keeps gdbus error messages in English, so they can be
    // recognised; --timeout stops a stuck call from overlapping the polling
    // cycles.
    property var processes: []

    function run(command, callback) {
        const proc = processComponent.createObject(root, {
            command: command,
            callback: callback || null,
            startedAt: Date.now()
        })
        if (!proc)
            return
        processes = processes.concat([proc])
        proc.running = true
    }

    function call(method, args, callback) {
        run(gdbusCall.concat(["io.weirdware.BlueFerry." + method], args || []), callback)
    }

    function forgetProcess(proc) {
        processes = processes.filter(other => other !== proc)
        Qt.callLater(() => proc.destroy())
    }

    Component {
        id: processComponent

        Process {
            id: proc

            property var callback: null
            property double startedAt: 0
            property bool exitSeen: false
            property bool outSeen: false
            property bool errSeen: false
            property int exitCodeValue: -1

            environment: ({ "LC_ALL": "C" })

            stdout: StdioCollector {
                onStreamFinished: {
                    proc.outSeen = true
                    proc.finish()
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    proc.errSeen = true
                    proc.finish()
                }
            }
            onExited: exitCode => {
                proc.exitCodeValue = exitCode
                proc.exitSeen = true
                proc.finish()
            }

            // Calls back once the process has exited and both streams are
            // closed, or when forced (a process that could not start).
            function finish(forced) {
                if (!callback || !forced && (!exitSeen || !outSeen || !errSeen))
                    return
                const done = callback
                callback = null
                try {
                    done(exitSeen ? exitCodeValue : 127, outSeen ? stdout.text || "" : "",
                        errSeen ? stderr.text || "" : "")
                } catch (e) {
                    console.warn("iphoneStatus: command callback failed:", e)
                }
                root.forgetProcess(proc)
            }
        }
    }

    // A command that never started (gdbus missing) counts as not found; one
    // that runs far past gdbus's own timeout is stopped.
    Timer {
        interval: 2000
        running: root.processes.length > 0
        repeat: true
        onTriggered: {
            const now = Date.now()
            for (const proc of root.processes) {
                if (!proc.running && !proc.exitSeen && now - proc.startedAt > 1500)
                    proc.finish(true)
                else if (proc.running && now - proc.startedAt > 20000)
                    proc.running = false
            }
        }
    }

    // --- Reading the data --------------------------------------------------

    property bool statusBusy: false
    property bool mediaBusy: false
    property bool callsBusy: false
    property bool messagesBusy: false

    // Whether a freshly parsed value differs from the current one. Reassigning
    // an equal array would make every ListView using it destroy and recreate
    // all its delegates (photos, rounded clips, GPU textures) on each poll.
    function differs(current, next) {
        return JSON.stringify(current) !== JSON.stringify(next)
    }

    function nullable(value) {
        return value === undefined ? null : value
    }

    function clearPhone() {
        batteryLevel = null
        batterySource = null
        signalStrength = null
        networkName = null
        networkStatus = null
        connected = false
        connectivityDetail = ""
        estimateCharging()
    }

    function applyStatus(exitCode, stdout, stderr) {
        loaded = true
        lastUpdate = new Date()
        if (exitCode !== 0) {
            clearPhone()
            error = describeFailure(exitCode, stderr)
            return
        }
        const status = Util.gvariantJson(stdout)
        if (!status || typeof status !== "object") {
            clearPhone()
            error = I18n.trFor("iphoneStatus", "BlueFerry's answer could not be read")
            return
        }
        if (status.daemon === false) {
            clearPhone()
            error = I18n.trFor("iphoneStatus", "The BlueFerry daemon is not active")
            return
        }
        error = ""
        connected = status.bredr === true || status.le === true
        connectivityDetail = status.connectivity_detail || ""
        callsEnabled = status.calls_enabled === true
        batteryLevel = typeof status.phone_battery_level === "number" ? status.phone_battery_level : null
        batterySource = nullable(status.phone_battery_source)
        signalStrength = typeof status.phone_signal_strength === "number" ? status.phone_signal_strength : null
        networkName = nullable(status.phone_network_name)
        networkStatus = nullable(status.phone_network_status)
        estimateCharging()
    }

    function refreshStatus() {
        if (statusBusy)
            return
        statusBusy = true
        call("Messages1.GetStatus", [], (code, out, err) => {
            statusBusy = false
            applyStatus(code, out, err)
        })
    }

    function refreshMedia() {
        if (mediaBusy)
            return
        mediaBusy = true
        call("Media1.GetNowPlaying", [], (code, out) => {
            mediaBusy = false
            const value = code === 0 ? Util.gvariantJson(out) : undefined
            const next = value && typeof value === "object" ? value : null
            if (differs(nowPlaying, next))
                nowPlaying = next
            mediaFetchedAt = Date.now()
            clock = mediaFetchedAt
        })
    }

    // The artwork from the iTunes search API, one request per track.
    function fetchArtwork() {
        if (!onlineArtwork || !track || !track.title || artworkCache[artworkKey] !== undefined)
            return
        const key = artworkKey
        const remember = url => {
            const next = Object.assign({}, artworkCache)
            next[key] = url
            artworkCache = next
        }
        remember("")   // marks the request as done, even if it fails
        const country = (Qt.locale().name.split("_")[1] || "US").toLowerCase()
        const request = new XMLHttpRequest()
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE || request.status !== 200)
                return
            try {
                const result = JSON.parse(request.responseText).results[0]
                if (result && typeof result.artworkUrl100 === "string"
                        && result.artworkUrl100.startsWith("https://"))
                    remember(result.artworkUrl100.replace(/\/\d+x\d+bb\./, "/600x600bb."))
            } catch (e) {
            }
        }
        request.open("GET", "https://itunes.apple.com/search?media=music&entity=song&limit=1&country="
            + country + "&term=" + encodeURIComponent([track.artist, track.title].filter(p => !!p).join(" ")))
        request.send()
    }

    // A player command; a refusal shows up in the popup.
    function mediaCommand(command) {
        if (!canCommand(command))
            return
        call("Media1.SendMediaCommand", [Util.gvariantArg(command)], (code, out, err) => {
            if (code !== 0) {
                mediaError = err.trim().split("\n")[0].replace(/^Error:\s*/, "")
                    .replace(/^GDBus\.Error:[\w.]+:\s*/, "")
                mediaErrorTimer.restart()
            }
            mediaAfterCommand.restart()
        })
    }

    function refreshCalls() {
        if (callsBusy)
            return
        callsBusy = true
        call("CallHistory1.ListCallHistory", [String(callsShown)], (code, out) => {
            callsBusy = false
            const value = code === 0 ? Util.gvariantJson(out) : undefined
            if (!Array.isArray(value))
                return
            const next = value.filter(entry => entry && typeof entry === "object")
            if (differs(calls, next))
                calls = next
            for (const entry of calls) {
                if (Util.isPhoneAddress(entry.address) && photos[entry.address] === undefined
                        && photoQueue.indexOf(entry.address) < 0)
                    photoQueue.push(entry.address)
            }
            fetchNextPhoto()
        })
    }

    // One photo at a time: the answers are a few hundred KB each.
    function fetchNextPhoto() {
        if (photoBusy || photoQueue.length === 0)
            return
        const address = photoQueue.shift()
        photoBusy = true
        call("Messages1.GetContactPhoto", [Util.gvariantArg(address)], (code, out) => {
            photoBusy = false
            // An error (photos being updated) leaves the number to retry on the
            // next round.
            if (code === 0) {
                const next = Object.assign({}, photos)
                next[address] = Util.imageUri(Util.gvariantBytes(out))
                photos = next
            }
            fetchNextPhoto()
        })
    }

    function callName(entry) {
        return entry.contact_name || entry.name || entry.address || I18n.trFor("iphoneStatus", "Unknown")
    }

    function dial(address) {
        if (callsEnabled && Util.isPhoneAddress(address))
            call("Calls1.Dial", [Util.gvariantArg(address)], () => {})
    }

    function refreshMessages() {
        if (messagesBusy)
            return
        messagesBusy = true
        call("Messages1.ListEvents", ['["sms_received"]', String(messagesShown)], (code, out) => {
            messagesBusy = false
            const value = code === 0 ? Util.gvariantJson(out) : undefined
            if (!Array.isArray(value))
                return
            const app = I18n.trFor("iphoneStatus", "Messages")
            const before = messages.length > 0 ? messages[0].time : null
            const next = value.filter(event => event && typeof event === "object").map(event => ({
                kind: "sms",
                app: app,
                title: Util.cleanText(event.group_name || event.contact_name || event.sender_address)
                    || I18n.trFor("iphoneStatus", "Unknown"),
                body: Util.cleanText(event.body),
                time: new Date(event.timestamp || event.seen_at || 0)
            })).sort((a, b) => b.time - a.time)
            if (!differs(messages, next))
                return
            messages = next
            if (before !== null && !popupOpen)
                unseen += messages.filter(message => message.time > before).length
        })
    }

    // --- App notifications, from the shell's notification server ----------

    readonly property string phoneMark: "📱"   // prefix of ANCS titles

    // Dux Shell wraps each notification it shows in NotificationService's
    // allWrappers. A transient one leaves the list when its popup closes, but
    // the notification itself stays alive (and its actions usable) until
    // BlueFerry withdraws it or someone dismisses it. One the shell drops on
    // arrival (Do Not Disturb, duplicates) never gets a wrapper, so it is not
    // seen.
    function captureWrappers() {
        const wrappers = NotificationService.allWrappers
        for (let i = 0; i < wrappers.length; ++i) {
            if (wrappers[i])
                captureNotification(wrappers[i].notification)
        }
    }

    // The notifications of this shell session that are in the list:
    // id → {notification, key, capturedAt}.
    property var live: ({})

    function captureNotification(notification) {
        if (!notification || notification.appName !== "BlueFerry")
            return
        const id = notification.id
        if (live[id])
            return
        // BlueFerry titles app notifications "📱 App · Title"; SMS and missed
        // calls already come from its own lists.
        const summary = Util.plainText(notification.summary)
        if (!summary.startsWith(phoneMark))
            return
        const heading = summary.slice(phoneMark.length).trim()
        const separator = heading.indexOf(" · ")
        const item = {
            notifId: id,
            kind: "app",
            app: separator >= 0 ? heading.slice(0, separator) : heading,
            title: separator >= 0 ? heading.slice(separator + 3) : "",
            body: Util.plainText(notification.body),
            time: new Date()
        }
        item.key = [item.app, item.title, item.body, Math.floor(item.time.getTime() / 1000)].join("\u001f")

        // After a plugin reload the stored copy is still there: attach to it.
        const stored = appNotifications.find(other => other.notifId === id && other.app === item.app
            && other.title === item.title && other.body === item.body)
        const key = stored ? stored.key : item.key

        const entries = Object.assign({}, live)
        entries[id] = { notification: notification, key: key, capturedAt: Date.now() }
        live = entries
        // With the daemon as receiver the connection goes away with it (on a
        // plugin reload, for instance).
        notification.closed.connect(root, reason => root.notificationClosed(id, reason))

        if (stored)
            return
        appNotifications = [item].concat(appNotifications).slice(0, appNotificationsKept)
        saveNotifications()
        if (!popupOpen)
            unseen += 1
    }

    // BlueFerry withdraws the desktop notification when it is removed on the
    // iPhone; one dismissed on the desktop (its popup closed, or its Clear
    // button) is gone as well. One dismissed right as it arrives was dropped
    // by the shell (Do Not Disturb, duplicates) and stays.
    function notificationClosed(id, reason) {
        const entry = live[id]
        if (!entry)
            return
        const entries = Object.assign({}, live)
        delete entries[id]
        live = entries
        const withdrawn = reason === NotificationCloseReason.CloseRequested
            || reason === NotificationCloseReason.Dismissed && Date.now() - entry.capturedAt > 1500
        if (!withdrawn)
            return
        appNotifications = appNotifications.filter(item => item.key !== entry.key)
        saveNotifications()
    }

    // App notifications survive shell restarts in the plugin's state file.
    function loadNotifications() {
        const stored = pluginService ? pluginService.loadPluginState(pluginId, "notifications", []) : []
        if (!Array.isArray(stored))
            return
        appNotifications = stored.filter(row => row && typeof row.key === "string").map(row => ({
            key: row.key,
            notifId: typeof row.notifId === "number" ? row.notifId : -1,
            kind: "app",
            app: String(row.app || ""),
            title: String(row.title || ""),
            body: String(row.body || ""),
            time: new Date(row.time || 0)
        })).sort((a, b) => b.time - a.time).slice(0, appNotificationsKept)
    }

    function saveNotifications() {
        if (!pluginService)
            return
        pluginService.savePluginState(pluginId, "notifications", appNotifications.map(item => ({
            key: item.key,
            notifId: item.notifId,
            app: item.app,
            title: item.title,
            body: item.body,
            time: item.time.getTime()
        })))
    }

    function liveEntry(item) {
        for (const id of Object.keys(live)) {
            if (live[id].key === item.key)
                return live[id]
        }
        return null
    }

    // Dismiss on the iPhone too: BlueFerry's "Clear" button (its ANCS negative
    // action) is pressed on the desktop notification while BlueFerry still
    // tracks it, that is within the same shell and BlueFerry session.
    function dismissOnPhone(item) {
        const entry = liveEntry(item)
        const actions = entry && entry.notification ? entry.notification.actions || [] : []
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i] && actions[i].identifier === "ancs-negative") {
                actions[i].invoke()
                return
            }
        }
    }

    function removeNotification(item) {
        dismissOnPhone(item)
        appNotifications = appNotifications.filter(other => other.key !== item.key)
        saveNotifications()
    }

    function clearNotifications() {
        for (const item of appNotifications)
            dismissOnPhone(item)
        appNotifications = []
        saveNotifications()
        unseen = 0
    }

    // --- App icons and launching -------------------------------------------

    property var iconCache: ({})         // app name → icon path; only hits are kept

    // The desktop entry of an iPhone app: by id, then by its displayed name.
    function desktopEntry(app) {
        for (const name of Util.iconCandidates(app)) {
            const entry = DesktopEntries.byId(name)
            if (entry)
                return entry
        }
        const lower = String(app || "").trim().toLowerCase()
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; ++i) {
            if (apps[i] && String(apps[i].name || "").toLowerCase() === lower)
                return apps[i]
        }
        return null
    }

    // The app's icon from the icon theme, or its desktop entry's; "" when
    // there is none.
    function appIcon(app) {
        const key = String(app || "")
        if (key === "")
            return ""
        if (iconCache[key])
            return iconCache[key]
        let found = ""
        for (const name of Util.iconCandidates(key)) {
            found = Paths.themedIconPath(name) || ""
            if (found !== "")
                break
        }
        if (found === "") {
            const entry = desktopEntry(key)
            if (entry && entry.icon)
                found = Paths.themedIconPath(entry.icon) || ""
        }
        if (found !== "")
            iconCache[key] = found
        return found
    }

    // Clicking a notification opens its app on this computer, or its web
    // version when it has no app. Returns whether something was opened.
    function openNotification(item) {
        if (notificationClick === "none" || item.kind !== "app")
            return false
        const entry = desktopEntry(item.app)
        if (entry) {
            SessionService.launchDesktopEntry(entry)
            return true
        }
        const web = Util.webUrl(item.app)
        if (notificationClick === "app" && web !== "") {
            Qt.openUrlExternally(web)
            return true
        }
        return false
    }

    // --- Bar ---------------------------------------------------------------

    function panelIcon(id) {
        switch (id) {
        case "batteryIcon": return batteryIcon
        case "signalIcon": return signalIcon
        case "media": return playing ? "play_arrow" : "pause"
        case "notifications": return "notifications"
        case "placeholder": return "phone_iphone"
        default: return ""
        }
    }

    function panelText(id) {
        switch (id) {
        case "batteryText": return batteryText
        case "signalText": return signalBars < 0 ? dash : I18n.trFor("iphoneStatus", "%1 %").arg(signalStrength)
        case "operator": return networkText
        case "title": return title
        case "media": return mediaText
        case "notifications": return String(unseen)
        default: return ""
        }
    }

    // Bar items visible right now: texts disappear without data, and when
    // nothing is left a phone icon keeps the widget clickable.
    readonly property var panelVisible: {
        const items = panelItems.filter(id => {
            switch (id) {
            case "batteryIcon":
            case "signalIcon":
            case "title":
                return true
            case "media":
                return mediaText !== ""
            case "notifications":
                return unseen > 0
            default:
                return active && panelText(id) !== dash
            }
        })
        return items.length > 0 ? items : ["placeholder"]
    }

    readonly property string tooltip: {
        if (!active)
            return title + "\n" + reason
        const lines = [title, wifiCalling
            ? I18n.trFor("iphoneStatus", "Carrier: %1, Wi-Fi calling").arg(networkText)
            : I18n.trFor("iphoneStatus", "Carrier: %1").arg(networkText),
            charging ? I18n.trFor("iphoneStatus", "Battery: %1, %2").arg(batteryText).arg(chargingText)
                : I18n.trFor("iphoneStatus", "Battery: %1").arg(batteryText),
            I18n.trFor("iphoneStatus", "Signal: %1").arg(signalText)]
        if (mediaText !== "")
            lines.push((playing ? "▶ " : "⏸ ") + mediaText)
        if (unseen > 0)
            lines.push(unseen === 1 ? I18n.trFor("iphoneStatus", "1 new notification")
                : I18n.trFor("iphoneStatus", "%1 new notifications").arg(unseen))
        return lines.join("\n")
    }

    // --- Timers ------------------------------------------------------------

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }
    Timer {
        interval: root.popupOpen ? 3000 : 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshMedia()
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshCalls()
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshMessages()
    }
    // Moves the track's progress bar between two reads.
    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.clock = Date.now()
    }
    Timer {
        id: mediaAfterCommand
        interval: 600
        onTriggered: root.refreshMedia()
    }
    Timer {
        id: mediaErrorTimer
        interval: 6000
        onTriggered: root.mediaError = ""
    }

    function refreshAll() {
        refreshStatus()
        refreshMedia()
        refreshCalls()
        refreshMessages()
    }

    // --- One player in the shell for AirPlay from the iPhone ----------------

    // With BlueFerry's media control on and the iPhone playing over AirPlay
    // to shairport-sync, the shell sees the same track twice: BlueFerry's
    // MPRIS player ("iPhone (BlueFerry)": working controls and position, no
    // artwork) and shairport-sync's ("Shairport Sync": artwork, position
    // stuck at 0). While both play the same track the daemon either hides
    // Shairport Sync from the shell's players ("hide") or makes BlueFerry's
    // the preferred one ("prefer", which keeps the artwork). Whatever it
    // changes in the shell's settings it undoes when the tracks part, when
    // the option changes and when the plugin stops.
    readonly property string airplayDuplicate: config.airplayDuplicate || "hide"
    readonly property string shairportToken: "shairport-sync"   // matches its desktop entry

    readonly property var blueferryMpris: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) {
            if (players[i] && /\.blueferry/i.test(players[i].dbusName || ""))
                return players[i]
        }
        return null
    }

    // The same track on both, by the shell's own comparison.
    readonly property bool sameTrackTwice: !!shairport && !!blueferryMpris
        && shairport.playbackState !== MprisPlaybackState.Stopped
        && blueferryMpris.playbackState !== MprisPlaybackState.Stopped
        && MprisController.isSameTrack(shairport, blueferryMpris)

    // sameTrackTwice, steadied: on a track change the two players update a
    // moment apart, so a mismatch only counts once it lasts.
    property bool duplicate: false
    onSameTrackTwiceChanged: {
        if (sameTrackTwice) {
            duplicateRelease.stop()
            duplicate = true
        } else {
            duplicateRelease.restart()
        }
    }
    Timer {
        id: duplicateRelease
        interval: 8000
        onTriggered: root.duplicate = root.sameTrackTwice
    }

    property bool mediaModReady: false   // the players have had time to appear
    readonly property bool hideShairport: mediaModReady && duplicate && airplayDuplicate === "hide"
    readonly property bool preferBlueferry: mediaModReady && duplicate && airplayDuplicate === "prefer"
    onHideShairportChanged: applyMediaMod()
    onPreferBlueferryChanged: applyMediaMod()

    Timer {
        interval: 4000
        running: true
        onTriggered: {
            root.mediaModReady = true
            root.applyMediaMod()
        }
    }

    // What the daemon changed, kept in the plugin's state so that a shell
    // that stopped without cleaning up is put right on the next start:
    // {excluded: bool, pinned: string, previousPin: string}.
    function mediaModState() {
        const state = pluginService ? pluginService.loadPluginState(pluginId, "mediaMod", {}) : {}
        return state && typeof state === "object" ? state : {}
    }

    function saveMediaModState(state) {
        if (pluginService)
            pluginService.savePluginState(pluginId, "mediaMod", state)
    }

    function applyMediaMod() {
        const state = Object.assign({}, mediaModState())
        const token = shairportToken
        const excluded = (SettingsData.mediaExcludePlayers || []).map(entry => String(entry))
        const listed = excluded.some(entry => entry.trim().toLowerCase() === token)
        // Only an exclusion the daemon added is taken away again.
        if (hideShairport && !listed) {
            SettingsData.set("mediaExcludePlayers", excluded.concat([token]))
            state.excluded = true
        } else if (!hideShairport && listed && state.excluded) {
            SettingsData.set("mediaExcludePlayers", excluded.filter(entry => entry.trim().toLowerCase() !== token))
            state.excluded = false
        } else if (!listed) {
            state.excluded = false
        }

        const identity = blueferryMpris ? blueferryMpris.identity || "" : state.pinned || ""
        if (preferBlueferry && identity !== "" && MprisController.pinnedIdentity !== identity) {
            if (!state.pinned)
                state.previousPin = MprisController.pinnedIdentity || ""
            MprisController.setPinned(identity)
            state.pinned = identity
        } else if (!preferBlueferry && state.pinned) {
            // The pin goes back unless someone changed it meanwhile.
            if (MprisController.pinnedIdentity === state.pinned)
                MprisController.setPinned(state.previousPin || "")
            state.pinned = ""
            state.previousPin = ""
        }
        saveMediaModState(state)
    }

    function undoMediaMod() {
        mediaModReady = false
        applyMediaMod()
    }

    // --- Sharing the daemon with the widgets --------------------------------

    Connections {
        target: NotificationService
        function onAllWrappersChanged() {
            root.captureWrappers()
        }
    }

    function publish() {
        if (pluginService)
            pluginService.setGlobalVar(pluginId, "controller", root)
    }

    onPluginServiceChanged: {
        loadConfig()
        publish()
    }

    Component.onCompleted: {
        loadConfig()
        loadNotifications()
        captureWrappers()
        publish()
    }

    Component.onDestruction: {
        undoMediaMod()
        if (pluginService && pluginService.getGlobalVar(pluginId, "controller", null) === root)
            pluginService.setGlobalVar(pluginId, "controller", null)
    }
}
