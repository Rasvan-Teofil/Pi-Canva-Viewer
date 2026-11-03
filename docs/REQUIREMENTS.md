# Pi-Screen – Requirements (V1, Neustart)

Stand: 03.11.2026

## V1 – Muss
1. **Frischer Pi** – sauberes Raspberry Pi OS, Setup von null.
2. **Self-Install** – Repo von GitHub klonen, ein Install-Skript, Autostart per systemd.
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

## V2 / V3 – Später
- Notion-Anbindung (Datenbank-Ansichten, Volunteer-Aufgaben)
- Tiefe Integrationen (Multi-Pi-Fleet, Remote-Steuerung)

## Repo-Entscheidung
- Aktueller Stand (`main`): Canva, Dashboard, Notion, Fleet, PIN, Ubuntu-Kiosk – zu viele Richtungen gemischt.
- Empfehlung: **Repo behalten, neuer Branch** für V1.
  - Aktuellen Stand als Tag sichern (`archive/v0-experimente`)
  - Branch `v1-clean` vom ursprünglichen Canva-Viewer (`69583c5`) oder leer starten
  - Nützliche Teile gezielt übernehmen (z. B. `tv_power.py`, CEC-Skript)
  - Nach Abnahme `v1-clean` → `main`
- Neues Repo nur, wenn die Historie bewusst nicht mehr gebraucht wird.
