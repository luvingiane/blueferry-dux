# iPhone Status for Dux Shell

**English** · [Italiano](README.it.md)

A [Dux Shell](https://github.com/duxlabs-dev/dux-shell) plugin (QML only) that
shows your iPhone's battery, signal, carrier, notifications, now playing track
and recent calls, read from [BlueFerry](https://github.com/erikwb/blueferry).

It is the port of [blueferry-plasmoid](https://github.com/luvingiane/blueferry-plasmoid),
the KDE Plasma 6 applet, with the same features.

- **Bar widget**: battery icon, percentage, signal icon (5 bars), signal
  percentage, carrier, title, now playing track and a count of new
  notifications, each one reorderable or hidden. Vertical bars show the icons,
  the battery level and the notification count.
- **Tabbed popup**, with tabs you can reorder or hide:
  - **Status**: Battery (with "~" when it comes from the HFP hands-free
    link), Cellular network and Bluetooth sections;
  - **Notifications**: SMS from BlueFerry's history and the iPhone's app
    notifications, iOS style, with the app icon taken from the icon theme;
  - **Player**: artwork, track, artist, album, progress and controls;
  - **Calls**: recent calls with the contact's photo (or initials) and a
    call back button when HFP calls are on.
- **Control Center tile**: battery and carrier, with the Status tab as its
  detail page.
- **Emoji** in a font of your choice (Apple Color Emoji by default), the rest
  of the text in the theme font.
- **Tooltip**: carrier, battery and signal, or the reason the phone cannot be
  reached.
- English and Italian user interface.

## How it is built

The plugin has two parts:

- a **daemon** (`PhoneDaemon.qml`), created once by the shell: it reads
  BlueFerry, estimates charging, keeps the app notifications and shares itself
  with the widgets as the `controller` global variable;
- the **bar widget** (`PhoneWidget.qml`), one per bar, with the popup
  (`PhonePopout.qml` and the `*Page.qml` tabs).

So several bars or screens never read BlueFerry more than once.

## Data source

The daemon calls BlueFerry's D-Bus API (session bus, object
`/io/weirdware/BlueFerry`) with `gdbus`, without a shell in between:

| Data | Method | Every |
| --- | --- | --- |
| Battery, signal, network | `Messages1.GetStatus` | 10 s |
| Player | `Media1.GetNowPlaying`, `Media1.SendMediaCommand` | 15 s (3 s with the popup open) |
| Calls | `CallHistory1.ListCallHistory`, `Messages1.GetContactPhoto` | 60 s |
| SMS | `Messages1.ListEvents` | 30 s |
| AirPlay | shairport-sync's MPRIS player, through Quickshell | as it changes |

`blueferry phone-status --json` exposes the same `phone_*` keys but does not
say whether the iPhone is connected; the phone counts as connected when
BlueFerry reports `bredr` or `le`.

App notifications (ANCS) are not part of the API: BlueFerry sends them to the
desktop as transient notifications, which Dux Shell does not keep in its
notification center. The daemon copies them from the shell's
`NotificationService` as they arrive and keeps the last 50 in the plugin's
state file (`~/.local/state/dms/plugins/iphoneStatus_state.json`), so they
survive shell restarts. BlueFerry skips the notifications already on the
iPhone when it connects, so those never show up; neither do the ones the shell
drops as they arrive (Do Not Disturb, duplicates), because the shell never
hands them over.

Clearing a notification in the plugin also clears it on the iPhone, by
pressing BlueFerry's "Clear" button (the ANCS negative action) for it; this
works for notifications that arrived in the current shell and BlueFerry
session. A notification cleared on the iPhone disappears from the plugin when
BlueFerry withdraws its desktop notification, and so does one dismissed on the
desktop (its popup closed, or its own Clear button). Clicking a notification
opens its app on this computer, or its web version when there is no app (see
the settings). Replies are not possible: ANCS only offers the iPhone's
positive and negative actions.

BlueFerry replaces control characters and text direction marks with "�"
(Discord, for example, wraps names in bidi isolates). They are invisible on
iOS, so the plugin removes them.

An app's icon is looked up in the icon theme, trying the app name in lower
case and a few known aliases (Telegram → `org.telegram.desktop`), then the
icon of the desktop entry with the same name. Without a match the
notification gets a bell with a phone.

The iPhone does not send artwork over Bluetooth: the AMS attributes are only
artist, album, title and duration. During AirPlay to this computer the
artwork comes from shairport-sync (MPRIS, `mpris:artUrl`); otherwise, if the
option is on, the artist and title are looked up with the public iTunes
search API (Apple sees the titles looked up).

Player controls follow the list of commands the iPhone announces to
BlueFerry; when that list is empty they are tried anyway and a refusal shows
up in the popup.

Contact photos need `BLUEFERRY_CONTACT_PHOTOS=true` in
`~/.config/blueferry/local.env`, a BlueFerry restart and
`blueferry contacts-sync`.

The service is D-Bus activatable: if BlueFerry is not running, the first read
starts it.

The iPhone does not report whether it is charging (its Battery Service only
has Battery Level, and HFP only the level). The plugin estimates it from exact
LE readings: a rising level shows the charging icon and "probably charging",
with the measured rate ("1 % every 45 s"). If the next point does not arrive
within 2.5 times that interval (at least 90 s, at most 25 min; 5 min before a
rate is known) the estimate expires, and a drop ends it at once, so a full
phone or one held at 80 % by iOS is no longer announced. A missed reading or
a disconnect shorter than 2 minutes keeps the estimate.

During Wi-Fi calling iOS appends " Wi-Fi" to the operator name, which HFP
cuts at 16 characters ("vodafone IT Wi F"). The plugin drops the cut suffix
and shows a Wi-Fi icon after the operator instead.

The network type (LTE, 5G…) is not available: the iPhone's Bluetooth
hands-free profile only reports status, carrier, signal and mode.

## One player for AirPlay from the iPhone

With BlueFerry's MPRIS player on (`blueferry media enable-mpris`) and the
iPhone playing over AirPlay to shairport-sync, the shell sees the same track
twice: "iPhone (BlueFerry)", with working controls and position but no
artwork, and "Shairport Sync", with the artwork but the position stuck at 0.
While the two play the same track (by the shell's own comparison, steadied
for 8 s across track changes) the plugin pins BlueFerry's player and makes it
the active one: the bar, the dash and the media OSD show and control the
iPhone, with shairport-sync's artwork.

Shairport Sync stays in the dash's player list: the shell borrows artwork
only from a player it can see, and BlueFerry's player never has any, so
hiding shairport-sync would lose it. When the active player changes in the
middle of a track the shell shows the artwork in the bar from the next track
on.

The pin is undone when the tracks part, when the option is turned off and
when the plugin stops; a pin you set yourself is left alone. AirPlay from
another device, not playing on the iPhone, is never touched.

## Requirements

- Dux Shell 1.7 or later (tested with 2.0)
- BlueFerry 0.8.1 or later; signal and carrier need calls turned on
  (`blueferry calls enable`)
- `gdbus` (from GLib)

## Installation

Clone the repository into the shell's plugin folder, under the plugin's id:

```bash
git clone https://github.com/luvingiane/blueferry-dux ~/.config/DankMaterialShell/plugins/iphoneStatus
```

Then in Settings → Plugins press "Scan for Plugins", turn on **iPhone
Status** and add it to a bar (Settings → Bar, or the bar's edit mode). From a
terminal:

```bash
dms ipc call plugins enable iphoneStatus
```

To work on a checkout kept elsewhere, link it instead of cloning:
`ln -s "$PWD" ~/.config/DankMaterialShell/plugins/iphoneStatus`. After a change:

```bash
dms ipc call plugins reload iphoneStatus
```

The popup and its tabs are loaded with a fresh URL each time, so a reload
updates them too; a change to `util.js` or `order.js` needs a shell restart
(`dms restart`).

## Translations

Source strings are in English, wrapped in `I18n.trFor("iphoneStatus", …)`.
Italian lives in `translations/it.json`; for another language add
`translations/<code>.json` in the same format. The shell reads it again when
the language changes.

## License

MIT, see [LICENSE](LICENSE).
