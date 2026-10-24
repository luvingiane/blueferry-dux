# Stato iPhone per Dux Shell

[English](README.md) · **Italiano**

Un plugin per [Dux Shell](https://github.com/duxlabs-dev/dux-shell) (solo
QML) che mostra batteria, segnale, operatore, notifiche, brano in riproduzione
e chiamate recenti dell'iPhone, letti da
[BlueFerry](https://github.com/erikwb/blueferry).

È il porting di [blueferry-plasmoid](https://github.com/luvingiane/blueferry-plasmoid),
l'applet per KDE Plasma 6, con le stesse funzioni.

- **Widget della barra**: icona della batteria, percentuale, icona del segnale
  (5 tacche), percentuale del segnale, operatore, titolo, brano in
  riproduzione e numero di notifiche nuove, ognuno riordinabile o
  nascondibile. Le barre verticali mostrano le icone, il livello della
  batteria e il numero di notifiche.
- **Popup a schede**, riordinabili o nascondibili:
  - **Stato**: sezioni Batteria (con "~" quando il valore arriva dal
    collegamento vivavoce HFP), Rete cellulare e Bluetooth;
  - **Notifiche**: gli SMS dallo storico di BlueFerry e le notifiche delle app
    dell'iPhone, in stile iOS, con l'icona dell'app presa dal tema di icone;
  - **Player**: copertina, brano, artista, album, avanzamento e comandi;
  - **Chiamate**: chiamate recenti con la foto del contatto (o le iniziali) e
    un pulsante per richiamare quando le chiamate HFP sono attive.
- **Riquadro del Centro di controllo**: batteria e operatore, con la scheda
  Stato come pagina di dettaglio.
- **Emoji** in un font a scelta (Apple Color Emoji di base), il resto del
  testo nel font del tema.
- **Suggerimento**: operatore, batteria e segnale, oppure il motivo per cui il
  telefono non è raggiungibile.
- Interfaccia in inglese e italiano.

## Com'è fatto

Il plugin ha due parti:

- un **daemon** (`PhoneDaemon.qml`), creato una sola volta dalla shell: legge
  BlueFerry, stima la ricarica, conserva le notifiche delle app e si mette a
  disposizione dei widget come variabile globale `controller`;
- il **widget della barra** (`PhoneWidget.qml`), uno per barra, con il popup
  (`PhonePopout.qml` e le schede `*Page.qml`).

Così più barre o più schermi non leggono mai BlueFerry più di una volta.

## Da dove arrivano i dati

Il daemon chiama l'API D-Bus di BlueFerry (bus di sessione, oggetto
`/io/weirdware/BlueFerry`) con `gdbus`, senza passare da una shell:

| Dato | Metodo | Ogni |
| --- | --- | --- |
| Batteria, segnale, rete | `Messages1.GetStatus` | 10 s |
| Player | `Media1.GetNowPlaying`, `Media1.SendMediaCommand` | 15 s (3 s col popup aperto) |
| Chiamate | `CallHistory1.ListCallHistory`, `Messages1.GetContactPhoto` | 60 s |
| SMS | `Messages1.ListEvents` | 30 s |
| AirPlay | il player MPRIS di shairport-sync, tramite Quickshell | a ogni cambio |

`blueferry phone-status --json` espone le stesse chiavi `phone_*` ma non dice
se l'iPhone è connesso; il telefono conta come connesso quando BlueFerry
riporta `bredr` o `le`.

Le notifiche delle app (ANCS) non fanno parte dell'API: BlueFerry le manda al
desktop come notifiche transitorie, che Dux Shell non conserva nel centro
notifiche. Il daemon le copia dal `NotificationService` della shell appena
arrivano e tiene le ultime 50 nel file di stato del plugin
(`~/.local/state/dms/plugins/iphoneStatus_state.json`), così sopravvivono ai
riavvii della shell. BlueFerry salta le notifiche già presenti sull'iPhone
quando si connette, quindi quelle non compaiono; non compaiono nemmeno quelle
che la shell scarta all'arrivo (Non disturbare, duplicati), perché la shell non
le passa.

Cancellare una notifica nel plugin la cancella anche sull'iPhone, premendo per
lei il pulsante "Clear" di BlueFerry (l'azione negativa di ANCS); funziona per
le notifiche arrivate nella sessione attuale della shell e di BlueFerry. Una
notifica cancellata sull'iPhone sparisce dal plugin quando BlueFerry ritira la
notifica dal desktop, e lo stesso vale per una chiusa sul desktop (chiudendo
il popup o col suo pulsante Clear). Un clic su una notifica apre la sua app su
questo computer, o la versione web quando l'app non c'è (vedi le
impostazioni). Non si può rispondere: ANCS offre solo l'azione positiva e
quella negativa dell'iPhone.

BlueFerry sostituisce i caratteri di controllo e i segni di direzione del
testo con "�" (Discord, per esempio, racchiude i nomi tra isolatori bidi). Su
iOS sono invisibili, quindi il plugin li toglie.

L'icona di un'app si cerca nel tema di icone, provando il nome dell'app in
minuscolo e alcuni alias noti (Telegram → `org.telegram.desktop`), poi
l'icona della voce desktop con lo stesso nome. Senza corrispondenza la
notifica mostra una campanella con un telefono.

L'iPhone non manda copertine via Bluetooth: gli attributi AMS sono solo
artista, album, titolo e durata. Durante AirPlay verso questo computer la
copertina arriva da shairport-sync (MPRIS, `mpris:artUrl`); altrimenti, se
l'opzione è attiva, artista e titolo si cercano con l'API pubblica di ricerca
di iTunes (Apple vede i titoli cercati).

I comandi del player seguono l'elenco che l'iPhone annuncia a BlueFerry;
quando l'elenco è vuoto si provano comunque e un rifiuto compare nel popup.

Le foto dei contatti richiedono `BLUEFERRY_CONTACT_PHOTOS=true` in
`~/.config/blueferry/local.env`, un riavvio di BlueFerry e
`blueferry contacts-sync`.

Il servizio si attiva via D-Bus: se BlueFerry non è in esecuzione, la prima
lettura lo avvia.

L'iPhone non comunica se è in carica (il suo Battery Service ha solo Battery
Level, e HFP solo il livello). Il plugin lo stima dalle letture esatte via LE:
un livello che sale mostra l'icona di ricarica e "probabilmente in carica",
con la velocità misurata ("1 % ogni 45 s"). Se il punto successivo non arriva
entro 2,5 volte quell'intervallo (almeno 90 s, al massimo 25 min; 5 min prima
di conoscere la velocità) la stima scade, e una discesa la chiude subito,
così un telefono carico o tenuto all'80 % da iOS non viene più segnalato. Una
lettura mancata o una disconnessione più breve di 2 minuti mantengono la
stima.

Durante le chiamate Wi-Fi iOS aggiunge " Wi-Fi" al nome dell'operatore, che
HFP taglia a 16 caratteri ("vodafone IT Wi F"). Il plugin toglie il suffisso
tagliato e mostra invece un'icona Wi-Fi dopo l'operatore.

Il tipo di rete (LTE, 5G…) non è disponibile: il profilo vivavoce Bluetooth
dell'iPhone riporta solo stato, operatore, segnale e modalità.

## Un solo player per AirPlay dall'iPhone

Con il player MPRIS di BlueFerry attivo (`blueferry media enable-mpris`) e
l'iPhone che suona in AirPlay su shairport-sync, la shell vede lo stesso brano
due volte: "iPhone (BlueFerry)", con comandi e posizione funzionanti ma senza
copertina, e "Shairport Sync", con la copertina ma la posizione ferma a 0.
Finché i due suonano lo stesso brano (secondo il confronto della shell stessa,
stabilizzato per 8 s ai cambi di brano) il plugin fissa il player di BlueFerry
e lo rende quello attivo: barra, dashboard e OSD multimediale mostrano e
comandano l'iPhone, con la copertina di shairport-sync.

Shairport Sync resta nell'elenco dei player della dashboard: la shell prende
in prestito la copertina solo da un player che vede, e quello di BlueFerry non
ne ha mai una, quindi nascondere shairport-sync la farebbe sparire. Quando il
player attivo cambia a metà brano, la shell mostra la copertina in barra dal
brano successivo.

Il player fissato torna com'era quando i brani si separano, quando l'opzione
viene spenta e quando il plugin si ferma; un player fissato da te resta com'è.
AirPlay da un altro dispositivo, che non suona sull'iPhone, non viene toccato.

## Requisiti

- Dux Shell 1.7 o successiva (provato con la 2.0)
- BlueFerry 0.8.1 o successivo; segnale e operatore richiedono le chiamate
  attive (`blueferry calls enable`)
- `gdbus` (da GLib)

## Installazione

Clona il repository nella cartella dei plugin della shell, col nome
dell'id del plugin:

```bash
git clone https://github.com/luvingiane/blueferry-dux ~/.config/DankMaterialShell/plugins/iphoneStatus
```

Poi in Impostazioni → Plugin premi "Cerca plugin", attiva **iPhone Status** e
aggiungilo a una barra (Impostazioni → Barra, o la modalità modifica della
barra). Da terminale:

```bash
dms ipc call plugins enable iphoneStatus
```

Per lavorare su una copia tenuta altrove, collegala invece di clonarla:
`ln -s "$PWD" ~/.config/DankMaterialShell/plugins/iphoneStatus`. Dopo una
modifica:

```bash
dms ipc call plugins reload iphoneStatus
```

Il popup e le sue schede si caricano ogni volta con un URL nuovo, quindi il
ricaricamento aggiorna anche loro; una modifica a `util.js` o `order.js`
richiede il riavvio della shell (`dms restart`).

## Traduzioni

Le stringhe sorgente sono in inglese, dentro `I18n.trFor("iphoneStatus", …)`.
L'italiano sta in `translations/it.json`; per un'altra lingua aggiungi
`translations/<codice>.json` nello stesso formato. La shell lo rilegge quando
cambia la lingua.

## Licenza

MIT, vedi [LICENSE](LICENSE).
