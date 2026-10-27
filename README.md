# Raspberry Pi Canva Kiosk & ICF Church Screen Manager

Dieses Projekt automatisiert die Anzeige von **Canva-Präsentationen (Keynotes)**, einem **Church- & Volunteer-Aufgaben-Dashboard** sowie dem **Vers der Woche** im Vollbild-Kioskmodus auf einem oder mehreren Raspberry Pis – inklusive **zentraler Web-Steuerung (Multi-Pi Control Center)** und **automatischer TV-Power-Steuerung (Nachtabschaltung & Auto-Wakeup) über HDMI-CEC**.

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
- Administration im lokalen Netz: `http://<PI-IP>:8080/admin`
- Admin-Schlüssel: in der Kopfzeile der Administration einfügen; er wird nur für die laufende Browser-Sitzung gespeichert.

Der Schlüssel liegt auf dem Pi mit restriktiven Rechten in `/etc/pi-screen/runtime.env`. Bei einer Aktualisierung des ausgecheckten Branches genügt danach erneut `sudo bash ./install.sh`; der Schlüssel bleibt erhalten und der Dienst wird neu gestartet.

### Sicherheit und CEC-Hinweis

Alle schreibenden Steuerbefehle (Modus, Canva-Link, Zeitplan, TV-Power usw.) verlangen den Admin-Schlüssel. Der reine TV-Display-Endpunkt darf ohne Schlüssel gelesen werden, enthält aber keine Notion- oder Fleet-Zugangsdaten. CORS für fremde Webseiten ist deaktiviert.

HDMI-CEC kann einen kompatiblen Fernseher in den Standby schicken und wieder wecken. Es schaltet **nicht garantiert die Netzspannung** ab. CEC muss am Fernseher aktiviert sein (bei Samsung: Anynet+); der mitgelieferte Status meldet einen Fehler, statt wie der alte Prototyp einen simulierten Erfolg anzuzeigen. Für professionelle Displays ohne verlässliches CEC wäre später RS-232, IP-Control oder ein geprüfter Stromschalter nötig.

Der Zeitplan wird beim Booten abgeglichen: Fährt der Pi während der geplanten Öffnungszeit hoch, weckt er den TV erneut. „Aktive Tage“ beziehen sich auf den Beginn des täglichen Anzeigezeitraums und unterstützen auch Zeitfenster über Mitternacht.

### Sofort zwischen Canva und Notion wechseln

Sobald im Admin-Bereich je ein Canva-Design-Link und eine veröffentlichte Notion-Ansicht hinterlegt sind, lädt die Anzeige beide Embeds bereits im Hintergrund. Mit der linken Pfeiltaste (`←`) wird die Canva-Keynote und mit der rechten Pfeiltaste (`→`) die Notion-Ansicht gezeigt. Der Wechsel erfolgt ausschließlich durch Umschalten der sichtbaren Ansicht: Die iFrames bleiben geladen und die Seiten werden nicht erneut aufgerufen. Eine Änderung im Admin-Bereich oder ein Display-Reload übernimmt wieder die zentral konfigurierte Ansicht.

### Mehrere Pis

Die lokale Kiosk-Installation ist produktionsbereit vorbereitet. Die bisherige Mehr-Pi-Oberfläche bleibt als Übersicht enthalten. Bevor aktive Befehle sicher zwischen Pis weitergereicht werden, braucht jeder Ziel-Pi eine eindeutig hinterlegte Vertrauensbeziehung bzw. einen Schlüssel. Das wird bewusst nicht über ungeschützte Netzwerkaufrufe gelöst.

---

## ✨ Features im Überblick

1. **5 Live-Anzeige-Modi (ohne Neustart umschaltbar):**
   - 🎞️ **Canva Keynote:** Zeigt eine konfigurierbare Canva-Präsentation im Vollbild (per Embed-View oder klassisch mit `xdotool` Autoplay-Steuerung).
   - 🧩 **Church Dashboard (ICF Heilbronn):** Kontrastreiches Dark-Mode-Dashboard für 65"-TVs im Space mit offenen **Church- & Volunteer-Aufgaben** (lokal pflegbar oder per **Notion-API Sync** aus `[🧩 Volunteer Aufgaben]`), **Vers der Woche Widget**, **Kommenden Events** (*Sunday Night*, *Youth Friendsgiving*, *Celebration*) und Live-Uhrzeit.
   - 🗂️ **Beliebige Notion-Datenbank / Ansicht (`notion`):** Zeigt jede im Web veröffentlichte Notion-Datenbank oder Notion-Seite direkt live auf dem Screen an (Board, Tabelle, Kalender, Timeline). Normale `notion.site`-, `notion.so/...?v=...`-Links oder `<iframe>`-Snippets werden automatisch in iframe-kompatible `.notion.site/ebd/...`-Embed-URLs umgewandelt; mehrere Ansichten können als **1-Klick-Vorlagen (Presets)** gespeichert oder alternativ direkt links im Church-Dashboard eingebettet werden.
   - 📖 **Vers der Woche (Fullscreen Slide):** Ruhige, großformatige Vollbild-Ansicht mit Bibelvers, Bibelstelle und kurzem Wochen-Impuls.
   - 🔄 **Auto-Rotation (Playlist / Mix):** Wechselt automatisch in einstellbaren Zeitintervallen zwischen Canva-Keynote, Church-Dashboard und Vers der Woche (inkl. Fortschrittsbalken).

2. **Web-Control-Panel & Multi-Pi Management (`/admin`):**
   - Übersicht und Steuerung **einzelner Raspberry Pis** (z. B. *Celebration Space Links*, *Celebration Space Rechts*, *Welcome Area*) oder **aller Pis gleichzeitig (Broadcast)**.
   - Live-Umschalten des Anzeige-Modus vom Smartphone oder Laptop im Netzwerk.
   - Direktes Bearbeiten von Canva-URL (synchronisiert automatisch mit `canva_url.txt`), Vers der Woche und Volunteer-Aufgaben im Browser.
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
│   └── dashboard_data.json       # Konfiguration: Modus, Aufgaben, Vers der Woche, TV-Zeitplan, Pi-Fleet
├── modules/
│   ├── config_manager.py         # Lädt/speichert JSON-Config & hält canva_url.txt synchron
│   ├── tv_power.py               # HDMI-CEC Steuerung (cec-client/cec-ctl/vcgencmd) & NightPowerScheduler
│   ├── notion_sync.py            # Optionaler Live-Sync mit Notion-Datenbank [🧩 Volunteer Aufgaben]
│   └── pi_fleet.py               # Multi-Pi Statusabfrage & Remote-Befehlsverteilung
├── templates/
│   ├── display.html              # Vollbild-TV-Ansicht (/display) für 65"-Screens
│   └── admin.html                # Web-Control-Panel (/admin) zur Steuerung aller Pis & Inhalte
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
- **Admin & Multi-Pi Control Center:** `http://<pi-ip>:8080/admin`

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
| `GET` | `/api/state` | Liefert kompletten aktuellen Zustand (Modus, Aufgaben, Vers, Events, TV-Power, Fleet) |
| `POST` | `/api/display/mode` | Setzt den Modus (`canva`, `dashboard`, `notion`, `verse`, `rotation`) & Rotationsintervalle |
| `POST` | `/api/display/reload` | Löst einen sofortigen Reload auf dem TV-Screen aus |
| `POST` | `/api/canva` | Aktualisiert die Canva-URL (und schreibt sie in `canva_url.txt`) |
| `POST` | `/api/verse` | Aktualisiert den Vers der Woche (`text`, `reference`, `impulse`, `week_label`) |
| `POST` | `/api/tasks` | Aufgaben verwalten (`action`: `add`, `toggle`, `update`, `delete`) |
| `POST` | `/api/notion/view` | Speichert/aktiviert eine veröffentlichte Notion-Datenbank-Ansicht (`url` → `/ebd/`, `presets`, `show_in_dashboard`) |
| `POST` | `/api/notion/sync` | Synchronisiert Aufgaben live aus Notion (`NOTION_TOKEN` + `database_id`) |
| `POST` | `/api/tv/power` | Führt HDMI-CEC Befehl aus (`action`: `on`, `standby`, `active-source`, `status`) |
| `POST` | `/api/tv/schedule` | Speichert den Zeitplan für die automatische Nachtabschaltung (`off_time`, `on_time`) |
| `GET` | `/api/fleet/status` | Prüft den Live-Status aller registrierten Raspberry Pis im Space |
| `POST` | `/api/fleet/command` | Sendet Befehle gezielt an einen Pi oder per Broadcast (`target: "all"`) an alle Pis |

---

## 👤 Autor

- **Teofil Wetzel** – *Initial work & ICF Heilbronn Screen Architecture*
