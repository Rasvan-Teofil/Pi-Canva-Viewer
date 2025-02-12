# Raspberry Pi Canva Kiosk

Dieses Projekt automatisiert das Starten einer [Canva](https://www.canva.com/) Präsentation im Vollbild-Kioskmodus auf einem Raspberry Pi direkt nach dem Booten. Dabei kommen folgende Komponenten zum Einsatz:

- **Chromium** als Browser  
- **xdotool** zum automatisierten Senden von Tastatur- und Mausbefehlen  
- **systemd** zum automatischen Starten des Kiosk-Skripts beim Booten  

## Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)  
2. [Installation](#installation)  
3. [Dateistruktur](#dateistruktur)  
4. [Anwendung](#anwendung)  
5. [Automatischer Start](#automatischer-start)  
6. [Problemlösung](#problemlösung)  
7. [Lizenz](#lizenz)  
8. [Autor](#autor)

---

## Voraussetzungen

- Raspberry Pi mit Raspberry Pi OS (inkl. Desktop)  
- HDMI-Monitor (oder anderes kompatibles Display)  
- Netzwerkverbindung (LAN oder WLAN)  
- Maus und Tastatur für die Erstkonfiguration  

Zusätzlich sollte man haben:

- Grundkenntnisse in der Linux-Kommandozeile  
- Sudo-Berechtigungen auf dem Raspberry Pi  

---

## Installation

### 1. System aktualisieren

    sudo apt-get update
    sudo apt-get upgrade -y

Ggf. Neustart:

    sudo reboot

### 2. Benötigte Pakete installieren

    sudo apt-get install -y chromium-browser xdotool

---

## Dateistruktur

Ein mögliches Projekt-Layout (Pfade nach Wunsch anpassbar):

    .
    ├── start_canva.sh          # Hauptskript für den Kioskmodus
    ├── canva_url.txt           # Textdatei mit der Canva-Präsentations-URL
    ├── start_canva.service     # systemd-Service (i.d.R. unter /etc/systemd/system)
    └── README.md               # Diese README

> **Hinweis**:  
> - Oft wird `start_canva.service` nach `/etc/systemd/system/` kopiert.  
> - Pfade entsprechend der eigenen Umgebung anpassen.

---

## Anwendung

### 1. Kiosk-Skript einrichten

Die Datei `.../start_canva.sh` ausführbar machen mit `chmod +x`

### 2. URL-Datei erstellen

Füge in  `canva_url.txt` deine Canva-URL ein, z. B.:

    https://www.canva.com/design/EXAMPLE_LINK

---

## Automatischer Start

Um das Skript beim Booten auszuführen, kann ein `systemd`-Service eingerichtet werden.

1. Service-Datei (z. B. `/etc/systemd/system/start_canva.service`) mit folgendem Inhalt erstellen bzw. aus dem `start_canva.service` file des repos kopieren:

       [Unit]
       Description=Canva Kiosk Service
       After=display-manager.service
       Requires=display-manager.service

       [Service]
       User=pi
       Environment=DISPLAY=:0
       Environment=XAUTHORITY=/home/pi/.Xauthority
       WorkingDirectory=/home/pi
       ExecStart=/home/pi/kiosk_start.sh
       Restart=on-failure
       RestartSec=10
       KillMode=none
       RemainAfterExit=yes
       StandardOutput=journal
       StandardError=journal

       [Install]
       WantedBy=graphical.target

   Benutzername, Pfade usw. ggf. anpassen.

2. Systemd neu laden und Service aktivieren:

       sudo systemctl daemon-reload
       sudo systemctl enable start_canva.service

3. Service starten (Test):

       sudo systemctl start start_canva.service

4. Status und Logs überprüfen:

       sudo systemctl status start_canva.service
       sudo journalctl -u start_canva.service

Wenn alles funktioniert, öffnet sich beim Booten Chromium im Kioskmodus und lädt automatisch die angegebene Canva-Präsentation.

---

## Problemlösung

1. **Chromium startet nicht**  
   - Prüfen, ob `chromium-browser` installiert ist.  
   - Skript ausführbar (`chmod +x`) und Pfade in der Service-Datei korrekt?

2. **Vollbildmodus funktioniert nicht**  
   - `xdotool` installiert?  
   - `DISPLAY=:0` und `XAUTHORITY=/home/pi/.Xauthority` für den richtigen Nutzer setzen.

3. **Mausklicks nicht korrekt**  
   - Koordinaten im Skript an Bildschirmauflösung oder Canva-UI anpassen.

4. **Service startet nicht beim Booten**  
   - Journallogs checken: `sudo journalctl -u start_canva.service`  
   - `WantedBy=graphical.target` und Boot in den grafischen Modus sicherstellen.

---

## Lizenz

*(Hier kann eine passende Lizenz eingefügt oder dieser Abschnitt entfernt werden. Beispiel:)*

    MIT License

    Copyright (c) 2025

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    ...

---

## Autor

- **Teofil Wetzel** – *Initial work*

Fragen und Feedback bitte per Issue oder Pull-Request einreichen.

**Viel Erfolg mit deinem automatisierten Canva-Kiosk auf dem Raspberry Pi!**
```
