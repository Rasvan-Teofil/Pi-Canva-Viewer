# Pi-Screen – Requirements (V1, Neustart)

Stand: 03.11.2026 · Branch `feat/requirements-v2`

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
6. **Absicherung** – Zugriff auf Admin/Config nur per Code, kein offener Zugriff.
7. **Public-Modus** – eigene Variante: nur Slideshow, kein Dashboard.
8. **HDMI-CEC** – TV-Steuerung für Samsung 65 Zoll (an/aus, Quelle).
9. **Sauberer Neustart** – keine alten Skripte, Services oder Hintergrundprozesse übernehmen.

## Installation (frischer Pi → Standalone)
**Vorher**
- Raspberry Pi Imager → *Raspberry Pi OS (64-bit) with desktop*
- Im Imager: Hostname, Admin-User, WLAN, SSH setzen
- Pi booten, per SSH verbinden

**Ein Befehl**
```bash
curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/feat/requirements-v2/scripts/bootstrap-pi.sh \
  | sudo bash -s -- --canva-url "https://www.canva.com/design/<ID>/view" --reboot
```

**Was das Skript macht** (`scripts/bootstrap-pi.sh`, wiederholbar)
1. OS-Update + Pakete (Chromium, xdotool, unclutter, cec-utils, git)
2. Altlasten entfernen (alte Services, Autostarts, Prozesse)
3. Kiosk-User `canva` anlegen (kein Passwort, nur Autologin)
4. Repo nach `/opt/pi-screen` klonen bzw. aktualisieren
5. Config `/etc/pi-screen/config.env` (Canva-URL, Modus, Admin-PIN, Klick-Koordinaten)
6. X11 + LightDM-Autologin für `canva`, Bildschirmschoner aus
7. Autostart: `~canva/.config/autostart/pi-screen.desktop` → `kiosk/start-kiosk.sh`

**Nach dem Reboot**
- Pi loggt als `canva` ein, Chromium startet im Vollbild mit dem Canva-Link
- Einmalig bei Canva einloggen, Session bleibt im Profil
- Login im normalen Fenster: `sudo -u canva touch /home/canva/.pi-screen-login && sudo systemctl restart lightdm`
- Link ändern: `/etc/pi-screen/config.env` bearbeiten, danach `sudo systemctl restart lightdm`

**Optionen:** `--user`, `--admin-pin`, `--mode canva|public`, `--branch`, `--no-upgrade`, `--reboot`

## V2 / V3 – Später
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
