# Pi-Screen – Requirements (V1, Neustart)

Stand: 03.11.2026 · Branch `main`

## Roadmap (Stand 24.11.2026)

**Stufe 1 – Board (jetzt)**
- Fullscreen-Board: Bibelvers des Tages, ICF-Logo, Uhrzeit + Datum
- Vers des Tages von YouVersion (bible.com/de, HFA), Fallback offline auf `board/verses.js`
- Board läuft auch offline
- Läuft als eingeloggter Desktop-User, Autostart per XDG/labwc
- Install per One-Liner: `scripts/install-board.sh`
- HDMI-CEC-Zeitplan: TV an/aus zu festen Uhrzeiten, optional Wochentage (`~/.config/pi-screen/schedule.env`, crontab)
- Standard-Zeitplan: Mo–Fr 07:30 an, 20:17 aus, Sa/So aus

**Stufe 2 – Canva (umgesetzt)**
- Zweite Ansicht neben dem Board, Wechsel per Pfeiltaste links/rechts (zyklisch, erweiterbar)
- Canva-Diashow im Vollbild über das öffentliche Embed, Weiterblättern per Timer (`CANVA_SLIDE_SECONDS`)
- Design konfigurierbar (`CANVA_URL` in `board.env`), Default „Bistro Slide Loop“ (`DAGeJOlW_fg`)
- Start-Ansicht konfigurierbar (`START_VIEW`)
- Eine Chromium-Instanz, Tastaturfokus bleibt beim Board

**Looker Studio (umgesetzt)**
- Dritte Ansicht: Looker-Studio-Bericht „ICF HN Dashboard“ im Vollbild, öffentlich eingebettet
- Seiten automatisch durchblättern (`LOOKER_PAGES`, `LOOKER_PAGE_SECONDS`)
- Ansichten und Reihenfolge per `VIEWS`, Ansicht ohne URL entfällt

**Notion (umgesetzt)**
- Vierte Ansicht: Todo-Datenbank „Volunteer Aufgaben“ als öffentliche Notion-Embed-Ansicht, im selben Pfeiltasten-Wechsel
- Neuladen alle 5 min (`NOTION_RELOAD_MINUTES`), Notion-Topbar ausgeblendet

## V1 – Muss
1. **Frischer Pi** – sauberes Raspberry Pi OS, Setup von null.
2. **Self-Install + Autostart von Anfang an** – ein Skript bringt den Pi von null auf Standalone (siehe unten).
3. **Konfigurierbarer Canva-Viewer**
   - Canva-Link hinterlegbar (Config, kein Code-Edit)
   - Dedizierter Canva-Pi-User
   - Einmaliger Login, Session bleibt erhalten
   - Präsentation im eigenen Vollbild-Fenster
4. **Canva-Präsentationsmodus** – vorerst weiter über emulierte Mausklicks
   - Bekannt störanfällig
   - Bessere Lösung offen (z. B. Embed-/Autoplay-Link, Export)
5. **Simples Dashboard**
   - Church-Kalender
   - Vers des Tages
   - Wetter
   - Hintergrundbild
   - ICF-Logo
   - Öffentlich, ohne PIN (V1)
6. **Dashboard öffentlich** – in V1 ohne PIN, kein Admin-Zugriff am Screen.
7. **Public-Modus** – eigene Variante: nur Slideshow, kein Dashboard.
8. **HDMI-CEC** – TV-Steuerung für Samsung 65 Zoll (an/aus, Quelle).
9. **Sauberer Neustart** – keine alten Skripte, Services oder Hintergrundprozesse übernehmen.

## Installation (frischer Pi → Standalone) – Soll-Ablauf
**Vorher**
- Raspberry Pi Imager → *Raspberry Pi OS (64-bit) with desktop*
- Im Imager: Hostname, Admin-User, WLAN, SSH setzen
- Pi booten, per SSH verbinden

**Ein Befehl**
```bash
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/bootstrap-pi.sh \
  | sudo bash -s -- --canva-url "https://www.canva.com/design/<ID>/view" --reboot
```

**Was das Skript macht** (wiederholbar)
1. OS-Update + Pakete (Chromium, xdotool, unclutter, cec-utils, git)
2. Altlasten entfernen (alte Services, Autostarts, Prozesse)
3. Kiosk-User `canva` anlegen (kein Passwort, nur Autologin)
4. Repo nach `/opt/pi-screen` klonen bzw. aktualisieren
5. Config `/etc/pi-screen/config.env` (Canva-URL, Modus, Klick-Koordinaten, 4-stelliger PIN für V2)
6. X11 + LightDM-Autologin für `canva`, Bildschirmschoner aus
7. Autostart: `~canva/.config/autostart/pi-screen.desktop` → `kiosk/start-kiosk.sh`

**Nach dem Reboot**
- Pi loggt als `canva` ein, Chromium startet im Vollbild mit dem Canva-Link
- Einmalig bei Canva einloggen, Session bleibt im Profil
- Login im normalen Fenster: `sudo -u canva touch /home/canva/.pi-screen-login && sudo systemctl restart lightdm`
- Link ändern: `/etc/pi-screen/config.env` bearbeiten, danach `sudo systemctl restart lightdm`

**Optionen:** `--user`, `--admin-pin`, `--mode canva|public`, `--branch`, `--no-upgrade`, `--reboot`

## V2 / V3 – Später
- **PIN-Absicherung (V2)**
  - 4-stelliger PIN beim Start des Dashboard-Fensters
  - Eingabe nur per Tastatur, keine Maus nötig
  - PIN konfigurierbar in `/etc/pi-screen/config.env` (`ADMIN_PIN`), Install-Skript setzt ihn bereits (`--admin-pin`)
- Notion-Anbindung (Datenbank-Ansichten, Volunteer-Aufgaben)
- Tiefe Integrationen (Multi-Pi-Fleet, Remote-Steuerung)

## Repo-Entscheidung
- Aktueller Stand (`main`): Canva, Dashboard, Notion, Fleet, PIN, Ubuntu-Kiosk – zu viele Richtungen gemischt.
- Empfehlung: **Repo behalten, neuer Branch** für V1 → umgesetzt als `feat/requirements-v2`.
  - Aktuellen Stand als Tag sichern (`archive/v0-experimente`)
  - Branch `v1-clean` vom ursprünglichen Canva-Viewer (`69583c5`) oder leer starten
  - Nützliche Teile gezielt übernehmen (z. B. `tv_power.py`, CEC-Skript)
  - Nach Abnahme `v1-clean` → `main`
- Neues Repo nur, wenn die Historie bewusst nicht mehr gebraucht wird.
