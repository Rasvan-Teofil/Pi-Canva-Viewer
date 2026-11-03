# Pi-Screen · V1

Ein sauberer Raspberry-Pi-OS-Kiosk für die Samsung-Displays im Church Space.
V1 enthält bewusst nur drei öffentliche Bildschirmvarianten:

- `canva` – Canva-Präsentation im Vollbild mit persistentem Login-Profil
- `public` – reine öffentliche Canva-Slideshow, ohne Dashboard oder Administration
- `dashboard` – öffentliches Church-Dashboard mit Kalender, Vers des Tages, Wetter, Hintergrund und ICF-Branding

Die bisherigen Dashboard-/Notion-/Fleet-Experimente wurden verworfen und sind unter dem Git-Tag `archive/v0-experimente` gesichert. Die verbindliche Spezifikation steht in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md).

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
