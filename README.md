GTA V Mod Installer + Settings Tuner



Ein vollautomatischer PowerShell-Installer für GTA V Mods (Singleplayer).

Er installiert / staged Mod-Archive, entpackt ZIPs, kopiert Presets und bietet einen integrierten Settings Tuner für settings.xml + commandline.txt.



⚠️ Singleplayer only!

Der Installer ist NICHT für GTA Online gedacht. Nutzung auf eigene Verantwortung.



Funktionen

🧰 Installer (WinForms GUI)



Automatische Erkennung des GTA-Installationsordners (GTA5\*.exe)



Download-Ordner für Mod-Archive



Staging-System (\_staging/)



Unterstützung für ZIP, RAR, 7Z, OIV (ZIP = Auto-Entpackung, Rest = Kopie)



Overwrite-Dialog:



Ja



Nein



Ja für alle



Alle Logs in einer Datei + GUI-Log



Optional: Interner LogViewer (selbe Datei)



🎮 Unterstützte Mods



QuantV



LA Roads



Forests of San Andreas



ReShade Presets (ini / ZIP)



📐 Settings Tuner



Ändert settings.xml → Grafikeinstellungen



Ändert optional commandline.txt



Presets:



Performance (GTX 1070 / 1080p empfohlen)



Balanced



Empfehlungen für Crosshair / Maus-Sensitivity



Backup-System der settings.xml → .bak\_YYYYMMDD\_HHMMSS



UI / Download Buttons



Rechte Seitenleiste:



Öffnet Download-Seiten im Browser deiner Wahl



Unterstützt:



Systemdefault



Edge



Chrome



Firefox



Clicks im Log → URL öffnet ebenfalls



Installation

1\. Skript ausführen



Rechtsklick → Mit PowerShell ausführen



Falls PowerShell blockiert:



Set-ExecutionPolicy RemoteSigned -Scope CurrentUser



2\. GTA Installationsordner wählen



Beispiele:



E:\\SteamLibrary\\steamapps\\common\\Grand Theft Auto V Enhanced\\

C:\\Program Files (x86)\\Steam\\steamapps\\common\\Grand Theft Auto V\\





Wichtig: Ordner muss GTA5\*.exe enthalten

→ z.B. GTA5.exe, GTA5\_Enhanced.exe, GTA5\_Enhanced\_BE.exe



3\. Download-Ordner



Beispiel:



C:\\Users\\<USER>\\Downloads\\GTA5\_Mods





Archive dort reinlegen:



QuantV\_2.1.4\_xxx.zip

LA\_Roads\_Patch.zip

Forests\_of\_SA\_5.8.rar

Reshade\_Preset.zip



4\. Haken setzen → Installation starten



ZIP → wird entpackt



RAR/OIV/7Z → Kopie in \_staging



Presets → Kopie in GTA-Ordner



Settings Tuner



Über Button „Settings Tuner öffnen“.



Funktionen:



Automatically find settings.xml



Wählt Preset aus



Optional commandline.txt schreiben



Backups



Jede Änderung erzeugt einen Backup:



settings.xml.bak\_20250127\_203530



Typische Fehler \& Lösungen

❌ GTA Pfad ungültig



→ Ordner enthält keine GTA5.exe

Fix: Korrekte Installation wählen



❌ Keine Mod-Dateien gefunden



→ Archive nicht im Download-Ordner

Fix: ZIP/RAR/7Z dort ablegen



❌ ZIP entpackt nichts



→ Datei nicht ZIP

Fix: Andere Archive werden nur kopiert



❌ „Ja/Nein/Ja für alle“



→ Installer erkennt vorhandene Dateien

„Ja für alle“ setzt global – kein weiteres Nachfragen



❌ GUI zeigt keine Links



→ URL leer im Code → Button deaktiviert



Logsystem



Eine Logdatei für alles:



GTA5\_ModInstaller.log





Log enthält:



Button-Events



URL-Aufrufe



Pfad-Erkennung



Installationsschritte



Fehler / Warnungen



GUI Log = Live-Output



Was der Installer nicht macht



🚫 Keine Direktinstallation in GTA selbst (OpenIV automatisiert nichts)

🚫 Keine Mod-Manager-Funktionalität

🚫 Kein Support für GTA Online

🚫 Keine automatischen Updates von Mods

🚫 Keine Garantie für Performance



Sicherheit



Der Mod-Installer schreibt nur:



\_staging



commandline.txt



settings.xml



Kein Code in GTA5.exe oder Spieldateien



Keine Injection / Hooking / DLL



Anforderungen



Windows 10/11



.NET / Powershell >= 5



Schreibrechte im GTA-Verzeichnis



Empfehlung (für 1080p / GTX 1060 / 1070 / 4070)



Preset: Performance



FXAA: An



TXAA: Aus



Grass: Niedrig



Shadows: Soft



LOD: 0.7–0.9



FPS Limit: 0 (unlimited)



Lizenz



Du entscheidest selbst. Vorschlag:

MIT License

Keine Haftung für Schäden / Bans / Datenverlust / kaputte Savegames.



Hinweise



Dieses Repository verändert nur lokale Spiel-Configs und bereitet Mods vor.

Modding geschieht auf eigene Gefahr.

