// Stateless helpers: gdbus answers, photos, text, emoji, app names.
//
// QML's JavaScript engine does not know Unicode regexes (\p{…}, the u flag):
// characters are classified by code point by hand.
.pragma library

// gdbus prints the answer as a GVariant tuple: ('…json…',) with the string in
// single quotes (or double quotes when it contains one) and special characters
// escaped. Returns the decoded string, or null.
function gvariantString(text) {
    const match = /^\s*\((['"])([\s\S]*)\1,\)\s*$/.exec(text || "")
    if (!match)
        return null
    return gvariantUnescape(match[2])
}

// The content of a GVariant string literal without its escapes.
function gvariantUnescape(body) {
    const simple = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v" }
    return body.replace(/\\(u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|x[0-9a-fA-F]{2}|[\s\S])/g,
        (all, esc) => {
            if (esc.length > 1)
                return String.fromCodePoint(parseInt(esc.slice(1), 16))
            return simple[esc] !== undefined ? simple[esc] : esc
        })
}

// A BlueFerry method's JSON answer, or undefined if unreadable.
function gvariantJson(text) {
    const json = gvariantString(text)
    if (json === null)
        return undefined
    try {
        return JSON.parse(json)
    } catch (e) {
        return undefined
    }
}

// A byte array printed by gdbus: ([byte 0xff, 0xd8, …],) or (@ay [],).
function gvariantBytes(text) {
    const body = /\[([^\]]*)\]/.exec(text || "")
    if (!body)
        return []
    const bytes = []
    const re = /0x([0-9a-fA-F]{2})/g
    let match
    while ((match = re.exec(body[1])) !== null)
        bytes.push(parseInt(match[1], 16))
    return bytes
}

// A GVariant string literal for a gdbus argument. Use it only with text that
// was already validated: it is not escaped.
function gvariantArg(text) {
    return '"' + text + '"'
}

const BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64(bytes) {
    const out = []
    for (let i = 0; i < bytes.length; i += 3) {
        const a = bytes[i]
        const b = bytes[i + 1]
        const c = bytes[i + 2]
        out.push(BASE64[a >> 2],
            BASE64[((a & 3) << 4) | ((b === undefined ? 0 : b) >> 4)],
            b === undefined ? "=" : BASE64[((b & 15) << 2) | ((c === undefined ? 0 : c) >> 6)],
            c === undefined ? "=" : BASE64[c & 63])
    }
    return out.join("")
}

// An image as a data URI, only if the first bytes really are JPEG or PNG.
function imageUri(bytes) {
    if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8)
        return "data:image/jpeg;base64," + base64(bytes)
    if (bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47)
        return "data:image/png;base64," + base64(bytes)
    return ""
}

// A phone number as the iPhone reports it; anything else is rejected before it
// ends up in a command.
function isPhoneAddress(text) {
    return typeof text === "string" && /^[+0-9][0-9 ()*#+.-]{0,39}$/.test(text)
}

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
}

function isEmoji(cp) {
    return (cp >= 0x1F000 && cp <= 0x1FAFF) || (cp >= 0x2600 && cp <= 0x27BF)
        || (cp >= 0x2300 && cp <= 0x23FF) || (cp >= 0x2B00 && cp <= 0x2BFF)
}

// Characters that bind to the preceding emoji: ZWJ, variation selector, keycap
// and regional flag tags.
function isJoiner(cp) {
    return cp === 0x200D || cp === 0xFE0F || cp === 0x20E3 || (cp >= 0xE0020 && cp <= 0xE007F)
}

// Text for Text.StyledText: the rest stays in the theme font, emoji sequences
// switch to the chosen font (Apple Color Emoji, as on the iPhone).
function styled(text, emojiFont) {
    if (text === null || text === undefined)
        return ""
    const runs = []   // [{ emoji: bool, text: string }]
    for (const ch of String(text)) {
        const cp = ch.codePointAt(0)
        const last = runs.length > 0 ? runs[runs.length - 1] : null
        if (isJoiner(cp)) {
            if (last && !last.emoji && (cp === 0xFE0F || cp === 0x20E3)) {
                // "1️⃣", "©️": the character before the selector becomes an
                // emoji.
                const chars = Array.from(last.text)
                const base = chars.pop()
                last.text = chars.join("")
                runs.push({ emoji: true, text: base + ch })
            } else if (last) {
                last.text += ch
            }
            continue
        }
        const emoji = isEmoji(cp)
        if (last && last.emoji === emoji)
            last.text += ch
        else
            runs.push({ emoji: emoji, text: ch })
    }
    const face = escapeHtml(emojiFont || "")
    return runs.filter(run => run.text !== "").map(run => {
        const html = escapeHtml(run.text).replace(/\n/g, "<br>")
        return run.emoji && face !== "" ? '<font face="' + face + '">' + html + "</font>" : html
    }).join("")
}

// Initials for the avatar of a contact without a photo: the first letter of the
// first and the last word that does not start with an emoji or a symbol.
function initials(name) {
    const words = String(name || "").trim().split(/\s+/).filter(word => {
        const cp = word.codePointAt(0)
        return cp !== undefined && !isEmoji(cp) && /[0-9A-Za-zÀ-ɏͰ-ӿ]/.test(String.fromCodePoint(cp))
    })
    if (words.length === 0)
        return ""
    const first = Array.from(words[0])[0]
    const second = words.length > 1 ? Array.from(words[words.length - 1])[0] : ""
    return (first + second).toUpperCase()
}

// A notification's text without the characters that cannot be seen. BlueFerry
// replaces controls and text direction marks with "�" (the bidi isolates
// Discord wraps names in): they are invisible on iOS, so they go away here,
// along with the other invisible format characters.
function cleanText(text) {
    let out = ""
    for (const ch of String(text || "")) {
        const cp = ch.codePointAt(0)
        if (cp === 0xFFFD || cp === 0x200B || cp === 0xFEFF || cp === 0x200E || cp === 0x200F
                || (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2066 && cp <= 0x2069))
            continue
        out += ch
    }
    return out.replace(/\(\s*\)|\[\s*\]/g, "").replace(/[ \t]{2,}/g, " ")
        .replace(/ +\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
}

// Plain text from a notification's (possibly HTML) text, cleaned as above.
function plainText(text) {
    return cleanText(String(text || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
        .replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ")
        .replace(/&#x([0-9a-fA-F]+);/g, (all, hex) => String.fromCodePoint(parseInt(hex, 16)))
        .replace(/&#([0-9]+);/g, (all, dec) => String.fromCodePoint(parseInt(dec, 10)))
        .replace(/&amp;/g, "&"))
}

// Icon and desktop entry names to try for an iPhone app, from the most
// specific to the most generic. Icon themes usually name them after the app in
// lower case. The aliases cover the system apps under their English and
// Italian iOS names.
const ICON_ALIASES = {
    "telegram": ["org.telegram.desktop", "telegram"],
    "whatsapp": ["whatsapp", "com.github.eneshecan.whatsappforlinux", "com.rtosta.zapzap"],
    "messaggi": ["dialog-messages", "kdeconnect-sms"],
    "messages": ["dialog-messages", "kdeconnect-sms"],
    "mail": ["mail-client", "internet-mail"],
    "posta": ["mail-client", "internet-mail"],
    "calendario": ["office-calendar"],
    "calendar": ["office-calendar"],
    "telefono": ["call-start"],
    "phone": ["call-start"],
    "facetime": ["facetime", "camera-web"],
    "foto": ["multimedia-photo-viewer"],
    "photos": ["multimedia-photo-viewer"],
    "musica": ["apple-music", "multimedia-audio-player"],
    "music": ["apple-music", "multimedia-audio-player"],
    "x": ["x", "twitter"],
    "teams": ["teams", "microsoft-teams"],
    "youtube": ["youtube", "com.github.ztefn.youtube"],
    "app store": ["appstore", "system-software-install"]
}

function iconCandidates(appName) {
    const name = String(appName || "").trim().toLowerCase()
    const names = []
    const add = value => {
        if (value && names.indexOf(value) < 0)
            names.push(value)
    }
    for (const alias of ICON_ALIASES[name] || [])
        add(alias)
    add(name.replace(/\s+/g, "-"))
    add(name.replace(/[^0-9a-z]+/g, ""))
    const first = name.split(/\s+/)[0]
    if (first !== name)
        add(first)
    return names
}

// Compares two track titles, ignoring case, accents, spaces and punctuation.
function sameTitle(a, b) {
    const norm = text => String(text || "").toLowerCase().normalize("NFKD")
        .replace(/[̀-ͯ]/g, "").replace(/[^0-9a-z]+/g, "")
    const x = norm(a)
    return x !== "" && x === norm(b)
}

// HFP reports the operator name in at most 16 characters (AT+COPS?).
const HFP_NAME_CHARS = 16

// During Wi-Fi calling iOS appends " Wi-Fi" to the operator name; over HFP the
// hyphen becomes a space and the name is cut at 16 characters, so it arrives
// as "vodafone IT Wi F". Returns {name, wifi}: the operator without the suffix
// and whether Wi-Fi calling is on. A cut suffix ("Wi", "Wi F", "Wi-F") only
// counts when the name has the full HFP length, so a real name ending in "Wi"
// stays as it is.
function splitWifiCalling(name) {
    const text = String(name || "")
    const full = /^(.*\S)\s+Wi[\s-]?Fi$/i.exec(text)
    if (full)
        return { name: full[1], wifi: true }
    if (Array.from(text).length >= HFP_NAME_CHARS) {
        const cut = /^(.*\S)\s+Wi(?:[\s-]F?)?$/i.exec(text)
        if (cut)
            return { name: cut[1], wifi: true }
    }
    return { name: text, wifi: false }
}

// The web version of an iPhone app, for apps without a desktop entry here.
const WEB_APPS = {
    "whatsapp": "https://web.whatsapp.com",
    "telegram": "https://web.telegram.org",
    "discord": "https://discord.com/app",
    "instagram": "https://www.instagram.com/direct/inbox/",
    "messenger": "https://www.messenger.com",
    "facebook": "https://www.facebook.com",
    "teams": "https://teams.microsoft.com",
    "gmail": "https://mail.google.com",
    "outlook": "https://outlook.live.com",
    "slack": "https://app.slack.com",
    "x": "https://x.com",
    "threads": "https://www.threads.net",
    "youtube": "https://www.youtube.com",
    "reddit": "https://www.reddit.com",
    "linkedin": "https://www.linkedin.com"
}

function webUrl(appName) {
    return WEB_APPS[String(appName || "").trim().toLowerCase()] || ""
}

// Material Symbols name for a battery level, as Dux Shell's own battery.
function batteryIcon(level, charging) {
    if (level === null || level === undefined)
        return "battery_unknown"
    if (charging) {
        if (level >= 90) return "battery_charging_full"
        if (level >= 80) return "battery_charging_90"
        if (level >= 60) return "battery_charging_80"
        if (level >= 50) return "battery_charging_60"
        if (level >= 30) return "battery_charging_50"
        if (level >= 20) return "battery_charging_30"
        return "battery_charging_20"
    }
    if (level >= 95) return "battery_full"
    if (level >= 85) return "battery_6_bar"
    if (level >= 70) return "battery_5_bar"
    if (level >= 55) return "battery_4_bar"
    if (level >= 40) return "battery_3_bar"
    if (level >= 25) return "battery_2_bar"
    if (level >= 10) return "battery_1_bar"
    return "battery_0_bar"
}

// Material Symbols name for 0-5 signal bars (the icon has 0-4); -1 = unknown.
function signalIcon(bars) {
    if (bars < 0)
        return "signal_cellular_off"
    return "signal_cellular_" + Math.min(4, Math.ceil(bars * 4 / 5)) + "_bar"
}
