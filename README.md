# GTA V Mod Installer & Settings Tuner / GTA V Mod Installer & Settings Tuner (DE/EN)

> **Hinweis / Note**  
> This tool is intended for **singleplayer use only**. Do **not** use it with GTA Online.  
> Dieses Tool ist ausschließlich für den **Singleplayer** gedacht. Bitte **nicht** mit GTA Online verwenden.

---

## 🇩🇪 Übersicht (Deutsch)

Der **GTA V Mod Installer & Settings Tuner** ist ein PowerShell-Skript mit moderner WinForms-GUI.  
Es hilft dir dabei, gängige Grafikmods und ReShade-Presets für GTA V vorzubereiten und vereinfacht die Anpassung von Grafikeinstellungen.

### Features

- Dark-Theme WinForms-GUI
- Automatische Erkennung des GTA V Installationsordners (GTA5\*.exe, inkl. umbenannter Varianten)
- Konfigurierbarer Download-Ordner für Mod-Archive
- Staging-Verzeichnis `_staging` unterhalb des Download-Ordners
- Unterstützung von Archivformaten:
  - **ZIP:** wird automatisch entpackt
  - **RAR / 7Z / OIV:** werden in das Staging-Verzeichnis kopiert
- Erkennung bereits vorhandener Staging-Ordner / Dateien mit Rückfrage, ob überschrieben werden soll
- Zentrales Logging in **einer** Logdatei
- Klickbare URLs im Log (öffnen denselben Link wie die Download-Buttons)
- Wahl des Browsers für Download-Links:
  - System-Standard
  - Microsoft Edge
  - Google Chrome
  - Mozilla Firefox

### Unterstützte Mods

Der Installer ist so aufgebaut, dass er leicht erweitert werden kann. Standardmäßig sind folgende Mods vorgesehen:

- **QuantV**
- **LA Roads**
- **Forests of San Andreas**
- **ReShade Presets** (z.B. QuantV-Presets)

Die eigentliche Installation innerhalb von GTA (z.B. über OpenIV) erfolgt weiterhin manuell – das Skript bereitet die Dateien nur auf und legt sie übersichtlich im Staging-Ordner ab.

### Settings Tuner (integriert)

Der Settings Tuner ist im Installer integriert und kann über einen Button geöffnet werden.

Er bietet u.a.:

- Erkennung und Bearbeitung von `settings.xml` (unter „Eigene Dokumente\Rockstar Games\...“)
- Optionales Anpassen von `commandline.txt` im GTA-Installationsordner
- Vordefinierte Grafik-Presets (z.B. „Performance“, „Balanced“)
- Erstellung von Backups der `settings.xml` bei jeder Änderung (`settings.xml.bak_YYYYMMDD_HHMMSS`)
- Hinweise zu Fadenkreuz-Einstellungen (Crosshair) und Maus-Sensitivität im Spiel

### Logging

Alle Log-Einträge landen in **einer einzigen Logdatei**, typischerweise im gleichen Verzeichnis wie das Skript:

```text
GTA5_ModInstaller.log
```

Protokolliert werden u.a.:

- Start des Installers
- erkannte GTA-Exe(s) im Installationsordner
- gesetzte Pfade für GTA-Ordner, Download-Ordner und Staging
- gefundene Mod-Archive
- Entpacken / Kopieren von Dateien
- Fehlermeldungen und Warnungen

Das GUI-Log-Fenster zeigt dieselben Informationen in Echtzeit an.  
URLs im Log sind klickbar und öffnen denselben Browser wie die Download-Buttons.

### Nutzung (Kurzfassung)

1. **PowerShell-Skript ausführen**  
   Rechtsklick auf die `.ps1` → „Mit PowerShell ausführen“  
   Falls PowerShell blockiert:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **GTA V Installationsordner wählen**  
   Beispiel:
   ```text
   E:\SteamLibrary\steamapps\common\Grand Theft Auto V Enhanced
   ```
   Der Ordner muss mindestens eine `GTA5*.exe` enthalten (z.B. `GTA5.exe`, `GTA5_Enhanced.exe`, …).

3. **Download-Ordner wählen**  
   Beispiel:
   ```text
   C:\Users\<Benutzer>\Downloads\GTA5_Mods
   ```
   Die Mod-Archive (ZIP, RAR, 7Z, OIV) sollten dort liegen.

4. **Mods auswählen und „Installation starten“ drücken**  
   - ZIP-Dateien werden nach `_staging\<ModName>` entpackt  
   - andere Archive werden dorthin kopiert  
   - bereits vorhandene Ordner/Dateien werden erkannt, und du wirst gefragt, ob überschrieben werden soll

5. **Settings Tuner verwenden** (optional)  
   - Button „Settings Tuner öffnen“ benutzen  
   - Preset auswählen, `settings.xml` anpassen lassen  
   - optional `commandline.txt` im GTA-Ordner mit anpassen

### Bekannte Einschränkungen

- Das Skript installiert keine Mods „vollautomatisch“ in RPF-Archive oder über OpenIV.  
- Es gibt keine Verwaltung verschiedener Mod-Profile.  
- Nur gängige Browser-Pfade (Edge/Chrome/Firefox) werden automatisch erkannt. Ist ein Browser nicht installiert, wird auf den System-Standard zurückgefallen.

### Sicherheit

- Das Skript verändert ausschließlich:
  - Dateien im gewählten GTA-Installationsordner (z.B. `commandline.txt`, ReShade-Presets)
  - `settings.xml` (mit automatischen Backups)
  - das Staging-Verzeichnis `_staging` im Download-Ordner
  - die Logdatei
- Es werden keine ausführbaren Dateien von GTA verändert oder gepatcht.
- Nutzung erfolgt auf eigene Verantwortung.

---

## 🇬🇧 Overview (English)

The **GTA V Mod Installer & Settings Tuner** is a PowerShell script with a modern WinForms GUI.  
It helps you prepare common graphics mods and ReShade presets for GTA V and simplifies tweaking graphics settings.

### Features

- Dark-theme WinForms GUI
- Automatic detection of the GTA V installation folder (`GTA5*.exe`, including renamed variants)
- Configurable download folder for mod archives
- Staging directory `_staging` below the download folder
- Archive support:
  - **ZIP:** extracted automatically
  - **RAR / 7Z / OIV:** copied into the staging directory
- Detection of existing staging folders / files with a prompt before overwriting
- Central logging into a **single** log file
- Clickable URLs in the log (same links as the download buttons)
- Browser selection for download links:
  - System default
  - Microsoft Edge
  - Google Chrome
  - Mozilla Firefox

### Supported Mods

The installer is designed to be easily extensible. Out of the box, it is configured for:

- **QuantV**
- **LA Roads**
- **Forests of San Andreas**
- **ReShade presets** (e.g. QuantV presets)

Actual installation into GTA (e.g. via OpenIV) is still manual – the script prepares and organizes the files in a clean staging folder.

### Integrated Settings Tuner

The Settings Tuner is integrated into the installer and can be opened via a dedicated button.

It provides:

- Detection and editing of `settings.xml` (under “My Documents\Rockstar Games\...”)
- Optional editing of `commandline.txt` in the GTA installation folder
- Predefined graphics presets (e.g. “Performance”, “Balanced”)
- Automatic backups of `settings.xml` on every change (`settings.xml.bak_YYYYMMDD_HHMMSS`)
- Hints for crosshair configuration and in-game mouse sensitivity

### Logging

All log entries go into a **single log file**, typically in the same directory as the script:

```text
GTA5_ModInstaller.log
```

The log contains e.g.:

- Installer start
- Detected GTA executable(s)
- Effective paths for GTA folder, download folder and staging
- Found mod archives
- Extraction / copy operations
- Errors and warnings

The GUI log window shows the same information live.  
URLs inside the log are clickable and use the same browser as the download buttons.

### Usage (Short Version)

1. **Run the PowerShell script**  
   Right-click the `.ps1` → “Run with PowerShell”  
   If PowerShell blocks the script:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Select GTA V installation folder**  
   Example:
   ```text
   E:\SteamLibrary\steamapps\common\Grand Theft Auto V Enhanced
   ```
   The folder must contain at least one `GTA5*.exe` (e.g. `GTA5.exe`, `GTA5_Enhanced.exe`, …).

3. **Select download folder**  
   Example:
   ```text
   C:\Users\<User>\Downloads\GTA5_Mods
   ```
   Place the mod archives (ZIP, RAR, 7Z, OIV) there.

4. **Check desired mods & click “Start Installation”**  
   - ZIP files are extracted to `_staging\<ModName>`  
   - other archives are copied there  
   - existing folders/files are detected and you are asked whether they should be overwritten

5. **Use the Settings Tuner** (optional)  
   - Click “Open Settings Tuner”  
   - Choose a preset, let the script adjust `settings.xml`  
   - optionally let it update `commandline.txt` in the GTA folder

### Known Limitations

- The script does not perform fully automatic mod installation into RPF archives or through OpenIV.  
- It does not manage multiple mod profiles.  
- Only common browser paths (Edge/Chrome/Firefox) are auto-detected; if a browser is missing, the system default is used instead.

### Safety

- The script only modifies:
  - Files inside the selected GTA installation folder (e.g. `commandline.txt`, ReShade presets)
  - `settings.xml` (with automatic backups)
  - The `_staging` directory in the download folder
  - The log file
- It does not patch or modify GTA’s executable files.
- Use at your own risk.

---

## Contribution / Contribution

Pull Requests, Issues und Verbesserungen sind ausdrücklich willkommen.  
Pull requests, issues and improvements are very welcome.

Bitte beachte beim Ändern des Codes:
- nur **eine zentrale Logdatei** verwenden
- das Verhalten der GUI möglichst generisch halten (wiederverwendbar für andere Projekte)
- neue Mods im Code sauber kommentieren

