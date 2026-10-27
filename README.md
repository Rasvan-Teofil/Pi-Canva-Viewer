# Raspberry Pi Canva Kiosk & ICF Church Screen Manager

Dieses Projekt automatisiert die Anzeige von **Canva-Präsentationen (Keynotes)**, einer veröffentlichten **Notion-Seite** sowie optionalen Dashboard-Inhalten im Vollbild-Kioskmodus. Jede Raspberry-Pi-Installation ist dabei vollständig **eigenständig**: Sie hat ihre eigene Admin-Seite, ihren eigenen Canva-Link, ihre eigene Notion-Ansicht und ihren eigenen HDMI-CEC-Zeitplan.

## Schnellstart: Ubuntu auf dem Raspberry Pi

Der unterstützte Weg ist absichtlich auf einen einzigen Installationsschritt reduziert. Nach dem Klonen bzw. Auschecken des gewünschten Branches genügt auf dem Pi:

```bash
sudo bash ./install.sh
```

Das Skript ist wiederholbar und erledigt Folgendes: installiert die benötigten Ubuntu-Pakete, richtet den Webserver als systemd-Dienst ein, erzeugt einen Admin-Schlüssel, aktiviert den grafischen Autostart und startet Chromium nach jedem Boot im Kioskmodus neu. Der Kiosk startet auch wieder, falls Chromium abstürzt.

Beim Upgrade des ursprünglichen Prototyps beendet das Skript außerdem dessen alte `pi_kiosk_server.service`- und `start_canva.service`-Instanzen, damit nicht zwei Server oder Browser um Port und Bildschirm konkurrieren.

Voraussetzung ist **Ubuntu Desktop für Raspberry Pi** (22.04 oder neuer) mit einem normalen, nicht-root Benutzer. Auf Ubuntu Server installiert dieser Aufruf die benötigte schlanke Desktop-Umgebung ebenfalls automatisiert:

```bash
sudo bash ./install.sh --install-desktop
```

Nach der Installation einmal neu starten. Danach erscheint die Anzeige selbstständig am HDMI-Bildschirm. Die Ausgabe des Installers enthält den einmalig erzeugten Admin-Schlüssel.

- TV-Ansicht auf dem Pi: `http://127.0.0.1:8080/display`
- Administration im lokalen Netz: `http://<PI-IP>:8080/admin` – hier werden Canva-Link, Notion-Ansicht, Anzeige-Modus und TV-Zeitplan dieses Pi gesetzt.
- Admin-Schlüssel: in der Kopfzeile der Administration einfügen; er wird nur für die laufende Browser-Sitzung gespeichert.

Der Schlüssel liegt auf dem Pi mit restriktiven Rechten in `/etc/pi-screen/runtime.env`. Bei einer Aktualisierung des ausgecheckten Branches genügt danach erneut `sudo bash ./install.sh`; der Schlüssel bleibt erhalten und der Dienst wird neu gestartet.

### Sicherheit und CEC-Hinweis

Alle schreibenden Steuerbefehle (Modus, Canva-Link, Zeitplan, TV-Power usw.) verlangen den Admin-Schlüssel. Der reine TV-Display-Endpunkt darf ohne Schlüssel gelesen werden, enthält aber keine Notion-Zugangsdaten. CORS für fremde Webseiten ist deaktiviert.

HDMI-CEC kann einen kompatiblen Fernseher in den Standby schicken und wieder wecken. Es schaltet **nicht garantiert die Netzspannung** ab. CEC muss am Fernseher aktiviert sein (bei Samsung: Anynet+); der mitgelieferte Status meldet einen Fehler, statt wie der alte Prototyp einen simulierten Erfolg anzuzeigen. Für professionelle Displays ohne verlässliches CEC wäre später RS-232, IP-Control oder ein geprüfter Stromschalter nötig.

Der Zeitplan wird beim Booten abgeglichen: Fährt der Pi während der geplanten Öffnungszeit hoch, weckt er den TV erneut. „Aktive Tage“ beziehen sich auf den Beginn des täglichen Anzeigezeitraums und unterstützen auch Zeitfenster über Mitternacht.

### Sofort zwischen Canva und Notion wechseln

Sobald im Admin-Bereich je ein Canva-Design-Link und eine veröffentlichte Notion-Ansicht hinterlegt sind, lädt die Anzeige beide Embeds bereits im Hintergrund. Mit der linken Pfeiltaste (`←`) wird die Canva-Keynote und mit der rechten Pfeiltaste (`→`) die Notion-Ansicht gezeigt. Der Wechsel erfolgt ausschließlich durch Umschalten der sichtbaren Ansicht: Die iFrames bleiben geladen und die Seiten werden nicht erneut aufgerufen. Eine Änderung im Admin-Bereich oder ein Display-Reload übernimmt wieder die zentral konfigurierte Ansicht.

### Administration direkt am Kiosk und Canva-Diashow

Am angeschlossenen Pi-Keyboard öffnet `Strg` + `Alt` + `A` jederzeit die lokale Administration. Dort lassen sich der Canva-Link und die veröffentlichte Notion-URL direkt ändern. Mit `Strg` + `Alt` + `S` geht es wieder zurück zur TV-Ansicht.

Die Option **„Canva beim Laden automatisch als Diashow starten“** löst nach dem Vorladen im lokalen Chromium-Kiosk die Canva-Autoplay-Sequenz aus. Sie nutzt `xdotool` und deshalb bewusst X11; der Kiosk-Starter startet Chromium entsprechend im X11-Modus. Falls Canva seine Oberfläche grundlegend ändert oder auf dem Pi kein X11 verfügbar ist, bleibt der Embed sichtbar, aber die automatische Diashow muss in Canva einmal manuell gestartet werden.

### Mehrere Pis

Installiere das Repository auf jedem Pi separat und öffne jeweils dessen eigene Admin-Seite: `http://<IP-DIESES-PI>:8080/admin`. Konfigurationen werden ausschließlich lokal in dessen `config/dashboard_data.json` gespeichert; kein Pi verwaltet oder steuert andere Pis. Damit kann jeder Bildschirm unabhängig eine andere Canva-Präsentation, Notion-Seite und Ein-/Ausschaltzeit erhalten.

---

## ✨ Features im Überblick

1. **5 Live-Anzeige-Modi (ohne Neustart umschaltbar):**
   - 🎞️ **Canva Keynote:** Zeigt eine konfigurierbare Canva-Präsentation im Vollbild (per Embed-View oder klassisch mit `xdotool` Autoplay-Steuerung).
   - 🧩 **Church Dashboard (ICF Heilbronn):** Kontrastreiches Dark-Mode-Dashboard für 65"-TVs im Space mit offenen **Church- & Volunteer-Aufgaben** (lokal pflegbar oder per **Notion-API Sync** aus `[🧩 Volunteer Aufgaben]`), **Vers der Woche Widget**, **Kommenden Events** (*Sunday Night*, *Youth Friendsgiving*, *Celebration*) und Live-Uhrzeit.
   - 🗂️ **Beliebige Notion-Datenbank / Ansicht (`notion`):** Zeigt jede im Web veröffentlichte Notion-Datenbank oder Notion-Seite direkt live auf dem Screen an (Board, Tabelle, Kalender, Timeline). Normale `notion.site`-, `notion.so/...?v=...`-Links oder `<iframe>`-Snippets werden automatisch in iframe-kompatible `.notion.site/ebd/...`-Embed-URLs umgewandelt; mehrere Ansichten können als **1-Klick-Vorlagen (Presets)** gespeichert oder alternativ direkt links im Church-Dashboard eingebettet werden.
   - 📖 **Vers der Woche (Fullscreen Slide):** Ruhige, großformatige Vollbild-Ansicht mit Bibelvers, Bibelstelle und kurzem Wochen-Impuls.
   - 🔄 **Auto-Rotation (Playlist / Mix):** Wechselt automatisch in einstellbaren Zeitintervallen zwischen Canva-Keynote, Church-Dashboard und Vers der Woche (inkl. Fortschrittsbalken).

2. **Lokales Web-Control-Panel (`/admin`):**
   - Live-Umschalten des Anzeige-Modus ausschließlich auf dem jeweils geöffneten Pi – vom Smartphone oder Laptop im Netzwerk.
   - Direktes Bearbeiten von Canva-URL (synchronisiert automatisch mit `canva_url.txt`), veröffentlichter Notion-Ansicht, Vers der Woche und lokalen Dashboard-Inhalten im Browser.
   - **Zero-Dependency Python 3 Server:** Läuft direkt mit der Python-Standardbibliothek (`python3 app.py`) ohne `pip`- oder `venv`-Zwang (kompatibel mit Raspberry Pi OS Bookworm/Trixie PEP 668).

3. **TV-Powerhandling über HDMI-CEC (`cec-client` / `cec-ctl`):**
   - **Automatische Nachtabschaltung (Night Schedule):** Schaltet die angeschlossenen Fernseher abends (Standard: `22:30 Uhr`) automatisch per HDMI-CEC (`standby 0`) in den Standby und weckt sie morgens (Standard: `08:00 Uhr`) per `on 0` + `as` (Active Source) wieder auf.
   - **Manuelle Sofort-Steuerung:** Jederzeit per Button im Admin-UI, per REST-API (`POST /api/tv/power`) oder per CLI-Skript (`./scripts/tv_cec_power.sh on|standby|active|status`).

---

## 📂 Dateistruktur

```text
.
├── app.py                        # Python 3 HTTP/REST Kiosk- & Management-Server (Port 8080)
├── config/
│   └── dashboard_data.json       # Lokale Konfiguration dieses Pi: Modus, Links, Aufgaben, Vers, TV-Zeitplan
├── modules/
│   ├── config_manager.py         # Lädt/speichert JSON-Config & hält canva_url.txt synchron
│   ├── tv_power.py               # HDMI-CEC Steuerung (cec-client/cec-ctl/vcgencmd) & NightPowerScheduler
│   └── notion_sync.py            # Optionaler Live-Sync mit Notion-Datenbank [🧩 Volunteer Aufgaben]
├── templates/
│   ├── display.html              # Vollbild-TV-Ansicht (/display) für 65"-Screens
│   └── admin.html                # Lokales Web-Control-Panel (/admin) für diesen Pi & Inhalte
├── static/
│   ├── css/                      # Dark-Mode Stylesheets für TV-Display & Admin-Panel
│   └── js/                       # Live-Polling, Rotations-Timer & Admin-Steuerungslogik
├── scripts/
│   └── tv_cec_power.sh           # Standalone HDMI-CEC Skript (on | standby | active | status)
├── canva_url.txt                 # Textdatei mit der Canva-Präsentations-URL
├── start_canva.sh                # Autostart-Skript für Kiosk-Browser, CEC-Wakeup & Server
├── start_canva.service           # systemd-Service für den grafischen Chromium-Kiosk
├── pi_kiosk_server.service       # systemd-Service für den Hintergrund-Web- & CEC-Server
└── README.md                     # Dokumentation
```

---

## Manuelle Installation (Legacy / nur für Entwicklung)

### 1. System aktualisieren & Pakete installieren

```bash
sudo apt-get update
sudo apt-get install -y python3 chromium-browser xdotool unclutter cec-utils
```

*Hinweis:* `cec-utils` stellt `cec-client` bereit, womit der Raspberry Pi den Fernseher direkt über das HDMI-Kabel ein- und ausschalten kann.

### 2. Server & Kiosk testen

```bash
chmod +x start_canva.sh scripts/tv_cec_power.sh app.py
python3 app.py --port 8080
```

Anschließend im Browser erreichbar:
- **TV Fullscreen-Ansicht (Kiosk):** `http://<pi-ip>:8080/display` (oder mit Modus-Parameter `?mode=dashboard`, `?mode=notion`, `?mode=verse`, `?mode=canva`, `?mode=rotation`)
- **Lokale Administration dieses Pi:** `http://<pi-ip>:8080/admin`

---

## Manuelle systemd-Einrichtung (Legacy)

Kopiere die Service-Dateien nach `/etc/systemd/system/` (Benutzername/Pfade bei Bedarf anpassen):

```bash
sudo cp pi_kiosk_server.service /etc/systemd/system/
sudo cp start_canva.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pi_kiosk_server.service start_canva.service
sudo systemctl start pi_kiosk_server.service start_canva.service
```

In `start_canva.sh` kann über die Umgebungsvariable `KIOSK_MODE` gewählt werden:
- `KIOSK_MODE="hub"` *(Standard)*: Öffnet `http://localhost:8080/display` für nahtloses Live-Umschalten zwischen Canva Keynote, Church Dashboard, Vers der Woche und Auto-Rotation.
- `KIOSK_MODE="classic_canva"`: Öffnet direkt die URL aus `canva_url.txt` und führt die klassische `xdotool`-Tastatur-/Maus-Sequenz (`Ctrl+Alt+P` + Autoplay-Klick) aus.

---

## 📺 TV-Powerhandling (HDMI-CEC) & Samsung Hospitality Mode

### 1. HDMI-CEC Befehle (CLI & API)

Über das mitgelieferte Skript `scripts/tv_cec_power.sh` oder über das Admin-Panel (`/admin`) lassen sich die TVs jederzeit steuern:

```bash
# TV einschalten und Raspberry Pi als aktive HDMI-Quelle setzen
./scripts/tv_cec_power.sh on

# TV nachts in den Standby schicken
./scripts/tv_cec_power.sh standby

# HDMI-Eingang des Pi erzwingen (Active Source)
./scripts/tv_cec_power.sh active

# Aktuellen TV-Powerstatus per CEC abfragen
./scripts/tv_cec_power.sh status
```

Der integrierte `NightPowerScheduler` in `app.py` prüft automatisch die konfigurierte Uhrzeit in `config/dashboard_data.json` (Standard: **22:30 Uhr Standby**, **08:00 Uhr Wakeup**) und schaltet den Bildschirm nachts stromsparend aus.

### 2. Samsung TV Hospitality Mode (Verhindert Samsung TV Plus beim Start!)

Damit ein Samsung Smart-TV (z. B. 65" im Celebration Space) beim Einschalten **garantiert auf HDMI 1** startet und niemals ins langsame Tizen-Menü oder *Samsung TV Plus* wechselt:

1. Am eingeschalteten Samsung TV auf einer klassischen IR-Fernbedienung nacheinander drücken:
   **`Mute` → `1` → `1` → `9` → `Enter` (OK)**
2. Im versteckten **Hospitality Mode Menü** folgende Werte setzen:
   - **Hospitality Mode:** `Standalone` / `ON`
   - **Power On Source:** `HDMI 1` (der Port, an dem der Raspberry Pi hängt)
   - **Power On Option:** `Power On` (startet sofort bei Stromzufuhr)
   - **Anynet+ (HDMI-CEC):** `ON`
3. TV einmal neu starten – ab sofort landet der Fernseher nach jedem Einschalten direkt auf dem Raspberry Pi Signal.

---

## 🔌 REST-API Endpunkte (Auswahl)

| Methode | Pfad | Beschreibung |
| :--- | :--- | :--- |
| `GET` | `/api/state` | Liefert den lokalen Zustand dieses Pi (Modus, Canva, Notion, Aufgaben, Vers, Events, TV-Power) |
| `POST` | `/api/display/mode` | Setzt den Modus (`canva`, `dashboard`, `notion`, `verse`, `rotation`) & Rotationsintervalle |
| `POST` | `/api/display/reload` | Löst einen sofortigen Reload auf dem TV-Screen aus |
| `POST` | `/api/canva` | Aktualisiert die Canva-URL (und schreibt sie in `canva_url.txt`) |
| `POST` | `/api/verse` | Aktualisiert den Vers der Woche (`text`, `reference`, `impulse`, `week_label`) |
| `POST` | `/api/tasks` | Aufgaben verwalten (`action`: `add`, `toggle`, `update`, `delete`) |
| `POST` | `/api/notion/view` | Speichert/aktiviert eine veröffentlichte Notion-Datenbank-Ansicht (`url` → `/ebd/`, `presets`, `show_in_dashboard`) |
| `POST` | `/api/notion/sync` | Synchronisiert Aufgaben live aus Notion (`NOTION_TOKEN` + `database_id`) |
| `POST` | `/api/tv/power` | Führt HDMI-CEC Befehl aus (`action`: `on`, `standby`, `active-source`, `status`) |
| `POST` | `/api/tv/schedule` | Speichert den Zeitplan für die automatische Nachtabschaltung (`off_time`, `on_time`) |

---

## 👤 Autor

- **Teofil Wetzel** – *Initial work & ICF Heilbronn Screen Architecture*
