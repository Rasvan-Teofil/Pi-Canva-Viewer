# Pi-Screen · V1

Ein sauberer Raspberry-Pi-OS-Kiosk für die Samsung-Displays im Church Space.
V1 enthält bewusst nur drei öffentliche Bildschirmvarianten:

- `canva` – Canva-Präsentation im Vollbild mit persistentem Login-Profil
- `public` – reine öffentliche Canva-Slideshow, ohne Dashboard oder Administration
- `dashboard` – öffentliches Church-Dashboard mit Kalender, Vers des Tages, Wetter, Hintergrund und ICF-Branding

Die bisherigen Dashboard-/Notion-/Fleet-Experimente wurden verworfen und sind unter dem Git-Tag `archive/v0-experimente` gesichert. Die verbindliche Spezifikation steht in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md).

## Stufe 1: Board (aktueller Weg)

Fullscreen-Board mit Bibelvers, ICF-Logo und Uhrzeit. Läuft als der bereits eingeloggte Desktop-User, komplett offline.

**Installieren / aktualisieren** (per SSH als Desktop-User, ohne `sudo` davor):

```bash
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/install-board.sh | bash
```

Das Skript:
- installiert fehlende Pakete (git, chromium, unclutter, cec-utils, v4l-utils, cron)
- klont bzw. aktualisiert das Repo nach `~/pi-screen`
- legt `~/.config/pi-screen/board.env` und `schedule.env` an (bestehende bleiben)
- entfernt alte Pi-Screen-Starts (`/etc/lightdm/lightdm.conf.d/90-pi-screen.conf`, canva-Autologin)
- Autostart: `~/.config/autostart/pi-screen-board.desktop`, bei labwc zusätzlich `~/.config/labwc/autostart`
- setzt den HDMI-CEC-Zeitplan in die crontab des Users
- startet das Board sofort auf `DISPLAY=:0`, ohne Reboot

**Inhalt**
- Vers des Tages aus `board/verses.js` (22 Verse, Wechsel täglich um Mitternacht)
- ICF-Logo weiß oben mittig, Uhr HH:MM, Datum deutsch (Europe/Berlin)
- Auslieferung über lokalen Server `http://127.0.0.1:8787/` (`scripts/board-server.py`), Fallback `file://`

**HDMI-CEC-Zeitplan**
```bash
nano ~/.config/pi-screen/schedule.env   # TV_ON=08:00, TV_OFF=22:30, TV_DAYS=* | 1-5 | 0,6
~/pi-screen/scripts/apply-schedule.sh   # übernimmt in die crontab
```

**TV per SSH**
```bash
~/pi-screen/scripts/cec-control.sh on|off|status
```

**Testbuttons „TV aus“ / „TV an“ (temporär)**
- unten rechts auf dem Board, nur bei `SHOW_TEST_BUTTONS=true` in `~/.config/pi-screen/board.env`
- ausschalten: `SHOW_TEST_BUTTONS=false`, danach Board neu laden (`pkill -f pi-screen/board-profile`, startet in 3 s neu)
- nach „TV aus“ ist der TV im Standby: Einschalten per Zeitplan oder SSH

**Fehlersuche**
```bash
journalctl -t pi-screen-board -t pi-screen-cec -n 50 --no-pager
cat ~/.local/share/pi-screen/board-server.log
```

## Stufe 2: Canva-Diashow

- Pfeiltaste rechts/links wechselt zwischen Board und Canva (zyklisch)
- Canva läuft als öffentliches Embed (`…/view?embed`) im Vollbild, Steuerleiste ausgeblendet
- Weiterblättern macht das Board selbst: alle `CANVA_SLIDE_SECONDS` die nächste Seite, nach der letzten wieder Seite 1
- Seitenzahl erkennt der Board-Server automatisch, Design-Änderungen kommen alle `CANVA_RELOAD_MINUTES` an
- Braucht Internet; ohne Verbindung erscheint ein Hinweis

**Einstellungen** in `~/.config/pi-screen/board.env` (fehlende Keys ergänzt der Installer):

| Key | Default | Bedeutung |
| --- | --- | --- |
| `CANVA_URL` | Bistro Slide Loop (`DAGeJOlW_fg`) | edit-, view- oder embed-Link |
| `CANVA_SLIDE_SECONDS` | `10` | Sekunden pro Folie |
| `CANVA_PAGES` | `0` | Seitenzahl, `0` = automatisch |
| `CANVA_RELOAD_MINUTES` | `30` | Neuladen für Design-Änderungen |
| `START_VIEW` | `board` | Ansicht beim Start: `board` oder `canva` |

Nach einer Änderung: `pkill -f pi-screen/board-profile` (Chromium startet in 3 s neu).

**Canva-Freigabe** (einmalig pro Design): In Canva *Teilen → Mehr anzeigen → Einbetten* bzw. Link auf „Jeder mit dem Link kann ansehen“. Ohne Freigabe zeigt die Ansicht eine Canva-Login-Seite.

## Looker-Studio-Ansicht

- Dritte Ansicht im Pfeiltasten-Wechsel: Board → Canva → Looker → Board
- Bericht „ICF HN Dashboard“ als öffentliches Embed (`lookerstudio.google.com/embed/reporting/…`), Seitennavigation und Fußzeile ausgeblendet
- Blättert durch die Seiten aus `LOOKER_PAGES`; die nächste Seite lädt verdeckt und wird dann eingeblendet
- Ohne Internet oder ohne Freigabe erscheint ein Hinweis, Board und Canva laufen weiter

| Key | Default | Bedeutung |
| --- | --- | --- |
| `LOOKER_URL` | ICF HN Dashboard | reporting-, embed- oder datastudio-Link; leer = Ansicht entfällt |
| `LOOKER_PAGES` | 4 Seiten-IDs | IDs aus `…/page/<ID>`, kommagetrennt; leer = nur erste Seite |
| `LOOKER_PAGE_SECONDS` | `30` | Sekunden pro Seite (min. 10) |
| `LOOKER_RELOAD_MINUTES` | `10` | Neuladen bei nur einer Seite |
| `VIEWS` | `board,canva,looker` | Reihenfolge; Ansichten ohne URL werden übersprungen |

**Freigabe in Looker Studio** (für einen anderen Bericht): *Teilen → Link-Einstellungen → „Jeder im Internet mit dem Link kann ansehen“* und *Datei → Bericht einbetten → „Einbetten zulassen“*. Datenquellen mit Anmeldedaten des Inhabers („Owner’s credentials“).

Die folgenden Abschnitte beschreiben den älteren Weg mit eigenem `canva`-User (`bootstrap-pi.sh`). Auf dem aktuellen Pi hat er nicht gegriffen.

## Frischen Pi installieren

Im Raspberry Pi Imager zunächst **Raspberry Pi OS (64-bit) with desktop** wählen und dort Hostname, WLAN, SSH und einen normalen Admin-Benutzer festlegen. Nach dem ersten Boot per SSH verbinden und ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/bootstrap-pi.sh \
  | sudo bash -s -- \
      --canva-url "https://www.canva.com/design/<ID>/view" \
      --mode canva \
      --reboot
```

Das Skript ist wiederholbar und erledigt alles Nötige:

1. installiert Chromium, X11-/Kiosk-Werkzeuge und HDMI-CEC;
2. entfernt bekannte Altlasten der früheren Pi-Screen-Varianten;
3. legt den dedizierten, passwortlosen Kiosk-User `canva` an;
4. installiert den aktuellen Branch nach `/opt/pi-screen`;
5. speichert die Konfiguration getrennt vom Repository unter `/etc/pi-screen/config.env`;
6. richtet eine eigene X11-/LightDM-Kiosk-Sitzung und den Chromium-Autostart ein;
7. weckt den Fernseher per HDMI-CEC und setzt den Pi als aktive Quelle, sofern CEC aktiviert ist.

Nach dem Reboot erscheint die Canva-Präsentation im Vollbild. Beim ersten Mal in Canva anmelden; die Sitzung bleibt im Chromium-Profil des Users `canva` erhalten.

## Bedienung und Konfiguration

Die V1-Anzeige ist absichtlich öffentlich und hat **keine Admin-Oberfläche und keine PIN-Eingabe**. Änderungen erfolgen direkt auf dem Pi per SSH:

```bash
sudoedit /etc/pi-screen/config.env
sudo systemctl restart lightdm
```

Wichtige Felder:

| Feld | Bedeutung |
| --- | --- |
| `CANVA_URL` | URL der Canva-Präsentation |
| `MODE` | `canva`, `public` oder `dashboard` |
| `CANVA_LOAD_WAIT_SEC` | Wartezeit vor der Canva-Präsentationsautomation |
| `CANVA_AUTOPLAY_CLICKS` | Klickpositionen für die derzeit noch fragile Canva-Autoplay-Automation; leer lassen, um sie auszuschalten |
| `DASHBOARD_CALENDAR_URL` | Optionaler veröffentlichter Kalender-Embed |
| `DASHBOARD_VERSE_TEXT`, `DASHBOARD_VERSE_REFERENCE` | Inhalt des Vers-des-Tages-Blocks |
| `DASHBOARD_WEATHER_LAT`, `DASHBOARD_WEATHER_LON` | Standort für die Wetteranzeige |
| `DASHBOARD_BACKGROUND_URL`, `DASHBOARD_LOGO_URL` | optionale öffentliche Bild-/Logo-URLs |
| `CEC_ADDRESS` | logische CEC-Adresse des Fernsehers (gewöhnlich `0`) |

Die vollständigen Vorgabewerte stehen in [config/config.env.example](config/config.env.example). Der Eintrag `ADMIN_PIN` ist nur für die geplante V2 reserviert und wird in V1 nicht verwendet.

Die mitgelieferten Canva-Klickkoordinaten passen zu einem 1920×1080-Display und sind absichtlich als Übergangslösung gekennzeichnet. Bei einem anderen Layout die Koordinaten in der Konfigurationsdatei anpassen oder die Automatisierung zunächst leer lassen.

### Canva-Login erneut öffnen

Falls ein Login abläuft, wird einmalig ein normales Chromium-Fenster statt des Kiosks gestartet:

```bash
sudo -u canva touch /home/canva/.pi-screen-login
sudo systemctl restart lightdm
```

Nach dem Login Chromium schließen. Der Kiosk startet automatisch wieder.

### HDMI-CEC

Bei Samsung muss Anynet+ / HDMI-CEC aktiviert sein. Lokale Befehle:

```bash
sudo /opt/pi-screen/scripts/cec-control.sh on
sudo /opt/pi-screen/scripts/cec-control.sh off
sudo /opt/pi-screen/scripts/cec-control.sh active
sudo /opt/pi-screen/scripts/cec-control.sh status
```

CEC schaltet in der Regel Standby und die HDMI-Quelle, nicht zwingend die physische Stromversorgung des Fernsehers.

## Update

Das gleiche Bootstrap-Skript kann später erneut laufen. Lokale Einstellungen in `/etc/pi-screen/config.env` bleiben erhalten:

```bash
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/bootstrap-pi.sh \
  | sudo bash -s -- --reboot
```

Ohne `--reboot` startet das Skript die grafische Sitzung am Ende neu, damit der aktualisierte Kiosk sofort aktiv wird.

## Troubleshooting

Wenn nach dem Reboot nur ein leerer schwarzer/grauer Desktop erscheint und kein Chromium:

```bash
# Logs des Kiosk-Starts
journalctl -t pi-screen-kiosk -n 50 --no-pager
# Session / Autostart prüfen
sudo -u canva cat /home/canva/.config/openbox/autostart
ls -l /opt/pi-screen/kiosk/start-kiosk.sh
# Bootstrap erneut (Config bleibt erhalten)
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/bootstrap-pi.sh \
  | sudo bash -s -- --reboot
```

Openbox startet **keine** `~/.config/autostart/*.desktop`-Dateien. Der Kiosk läuft über `~/.config/openbox/autostart` bzw. `kiosk/x11-session.sh`.
