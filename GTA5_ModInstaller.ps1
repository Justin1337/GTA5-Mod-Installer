<#
    GTA V Mod Installer (QuantV / LA Roads / Forests of San Andreas / ReShade)
    + Settings Tuner (settings.xml / commandline.txt)

    Features:
    - PowerShell-GUI (WinForms) im Dark Theme
    - Download-Buttons rechts (öffnet Webseiten im gewünschten Browser)
    - ZIPs werden nach "_staging" entpackt
    - .rar / .7z / .oiv werden nur nach "_staging" kopiert
    - Zentrales Logging in EINER Logdatei
    - Erkennung vorhandener Mod-Staging-Ordner + "Ja / Nein / Ja für alle"
    - Optionaler externer LogViewer (PS_LogViewer.ps1, gleiche Logdatei)
    - Integrierter Settings Tuner (zweites Formular, Button im Installer)
#>

# ===================== Globale Konfiguration =================================

$ErrorActionPreference = 'Stop'   # alle Fehler als Exceptions behandeln

# Root-Verzeichnis dieses Skripts
$script:ScriptRoot = Split-Path -Parent $PSCommandPath

# Eine (1) Logdatei für alles
$script:LogFilePath = Join-Path $script:ScriptRoot "GTA5_ModInstaller.log"

# Optionaler Log-Viewer (liest dieselbe Logdatei, erzeugt KEINE neue)
$script:ExternalLogViewerPath = Join-Path $script:ScriptRoot "PS_LogViewer.ps1"
$script:UseExternalLogViewer  = $true   # nur im Code änderbar

# GUI-Log-Control (wird später gesetzt, kann für frühe Fehler $null sein)
$script:LogControl = $null

# aktuell gewählte Browser-Option
$script:SelectedBrowserName    = 'SystemDefault'
$script:BrowserMap             = @{}  # Name -> Pfad (falls vorhanden)

# Standard-Pfade
$script:DefaultGtaPath        = "E:\SteamLibrary\steamapps\common\Grand Theft Auto V Enhanced"
$script:DefaultDownloadRoot   = Join-Path $env:USERPROFILE "Downloads"
$script:DefaultDownloadPath   = Join-Path $script:DefaultDownloadRoot "GTA5_Mods"

# Settings-Tuner Hintergrundbild (optional)
$script:SettingsTunerBackgroundImageUrl = 'https://images.unsplash.com/photo-1731873826387-eto28ytYEVU?auto=format&fit=crop&w=1200&q=80'

# Download-Links (alle müssen gesetzt sein, keine leeren Strings!)
$script:Link_QuantV_Free            = 'https://www.gtainside.com/en/gta5/mods/119996-quantv-2-1-4/'
$script:Link_QuantV_Patreon         = 'https://www.patreon.com/QuantV'
$script:Link_LA_Roads               = 'https://gta5mod.net/gta-5-mods/misc/l-a-roads-l-a-roads-patch-1-0/'
$script:Link_Forests_Revised        = 'https://www.gta5-mods.com/maps/forests-of-san-andreas-revised'
$script:Link_Forests_Ultimate       = 'https://www.patreon.com/larcius/shop/forests-of-san-andreas-ultimate-v5-8-556798'
$script:Link_ReShade_Official       = 'https://reshade.me/'
$script:Link_ReShade_QuantV_Preset  = 'https://www.gta5-mods.com/misc/photorealistic-reshade-present-for-quantv'
$script:Link_ReShade_QuantV_Realism = 'https://www.gta5-mods.com/misc/samirf03-realism-reshade-preset-for-quantv'

# Overwrite-Flag für "Ja für alle"
$script:OverwriteAll = $false

# ===================== Konsole minimieren ====================================

function Minimize-ConsoleWindow {
    <#
        Minimiert das zugehörige Konsolenfenster (conhost),
        egal ob PowerShell.exe ein eigenes MainWindowHandle hat oder nicht.
    #>
    try {
        $consoleCode = @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsole {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
        Add-Type $consoleCode -ErrorAction SilentlyContinue | Out-Null

        $hWnd = [NativeConsole]::GetConsoleWindow()
        if ($hWnd -ne [IntPtr]::Zero) {
            # 6 = SW_MINIMIZE
            [NativeConsole]::ShowWindow($hWnd, 6) | Out-Null
        }
    } catch {
        # Fehler beim Minimieren ignorieren
    }
}

Minimize-ConsoleWindow

# ===================== Grund-Setup (Assemblies / ShadowForm) =================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# STA für WinForms erzwingen (wenn möglich)
try {
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        [System.Threading.Thread]::CurrentThread.SetApartmentState(
            [System.Threading.ApartmentState]::STA
        )
    }
} catch { }

# ShadowForm nur definieren, wenn noch nicht vorhanden
if (-not ('ShadowForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @"
using System;
using System.Windows.Forms;
using System.Drawing;

public class ShadowForm : Form
{
    private const int CS_DROPSHADOW = 0x00020000;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ClassStyle |= CS_DROPSHADOW;
            return cp;
        }
    }
}
"@
}

# ===================== Logging / Hilfsfunktionen =============================

function Write-GuiLog {
    <#
        Schreibt Logausgaben:
        - in die Konsole (Host)
        - in das GUI-Logfeld (RichTextBox, falls vorhanden)
        - in EINE Logdatei ($script:LogFilePath)

        Level:
          INFO  – normale Meldungen
          WARN  – nicht-kritische Probleme
          ERROR – Fehler / Exceptions
    #>
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    # 1) Console-Ausgabe
    Write-Host $line

    # 2) GUI-Log (falls schon vorhanden)
    if ($script:LogControl -ne $null -and -not $script:LogControl.IsDisposed) {
        $script:LogControl.AppendText($line + [Environment]::NewLine)
        $script:LogControl.SelectionStart = $script:LogControl.Text.Length
        $script:LogControl.ScrollToCaret()
    }

    # 3) Datei-Log (eine Datei für alles)
    if ($script:LogFilePath) {
        try {
            if (-not (Test-Path $script:LogFilePath)) {
                New-Item -ItemType File -Path $script:LogFilePath -Force | Out-Null
            }
            Add-Content -Path $script:LogFilePath -Value $line
        } catch {
            # Fehler beim Schreiben ins Log ignorieren
        }
    }
}

function Show-FolderDialog {
    param(
        [string]$Description = "Ordner auswählen"
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        return $null
    }
}

function Expand-ZipFile {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path $ZipPath)) {
        throw "ZIP-Archiv nicht gefunden: $ZipPath"
    }

    if (Test-Path $Destination) {
        Write-GuiLog "Lösche vorhandenes Zielverzeichnis: $Destination"
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Write-GuiLog "Entpacke: $ZipPath -> $Destination"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

function Find-ModArchive {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    if (-not (Test-Path $Root)) {
        throw "Download-Ordner existiert nicht: $Root"
    }

    foreach ($pattern in $Patterns) {
        $file = Get-ChildItem -Path $Root -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($file) {
            Write-GuiLog "Gefunden: $($file.FullName)"
            return $file.FullName
        }
    }

    return $null
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Test-GtaFolder {
    <#
        Prüft, ob im angegebenen Ordner eine GTA5-Exe liegt.
        Akzeptiert:
          - GTA5.exe
          - GTA5_Enhanced.exe
          - generell jede Datei "GTA5*.exe"
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }

    $exeCandidates = Get-ChildItem -Path $Path -Filter "GTA5*.exe" -File -ErrorAction SilentlyContinue
    if (-not $exeCandidates) {
        return $false
    }

    $names = ($exeCandidates | Select-Object -ExpandProperty Name) -join ", "
    Write-GuiLog "GTA-Exe(s) im Ordner gefunden: $names" 'INFO'

    return $true
}

function Confirm-Overwrite {
    <#
        Zeigt einen Dialog mit:
        - Ja
        - Nein
        - Ja für alle

        $script:OverwriteAll:
          - wenn bereits $true → kein Dialog mehr, immer $true.
    #>
    param(
        [Parameter(Mandatory)][string]$ItemName,
        [Parameter(Mandatory)][string]$Path
    )

    if ($script:OverwriteAll) {
        Write-GuiLog "Überschreiben bereits global erlaubt (Ja für alle): $ItemName ($Path)" 'INFO'
        return $true
    }

    Write-GuiLog "$ItemName bereits vorhanden: $Path" 'WARN'

    try {
        # lokale Farben für den Dialog (an dein Dark-Theme angepasst)
        $colorBg        = [System.Drawing.Color]::FromArgb(30, 34, 40)
        $colorAccent    = [System.Drawing.Color]::FromArgb(0, 122, 204)
        $colorAccentAlt = [System.Drawing.Color]::FromArgb(45, 170, 220)
        $colorText      = [System.Drawing.Color]::WhiteSmoke

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "$ItemName bereits vorhanden"
        $form.StartPosition = 'CenterParent'
        $form.Size = New-Object System.Drawing.Size(420, 180)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true

        $form.BackColor = $colorBg
        $form.Font      = New-Object System.Drawing.Font("Segoe UI", 9)

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(380, 70)
        $lbl.Location = New-Object System.Drawing.Point(15, 10)
        $lbl.ForeColor = $colorText
        $lbl.Text = "Es scheint, dass '$ItemName' bereits existiert:`r`n$Path`r`n`r`nMöchtest du überschreiben?"
        $form.Controls.Add($lbl)

        # kleine Helper-Funktion für hübsche Buttons in diesem Dialog
        function New-ConfirmButton {
            param(
                [string]$Text,
                [int]$X,
                [int]$Y,
                [int]$Width = 90,
                [int]$Height = 28
            )
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $Text
            $btn.Size = New-Object System.Drawing.Size($Width, $Height)
            $btn.Location = New-Object System.Drawing.Point($X, $Y)
            $btn.FlatStyle = 'Flat'
            $btn.FlatAppearance.BorderSize = 0
            $btn.BackColor = $colorAccent
            $btn.ForeColor = $colorText
            $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)

            $btn.Add_MouseEnter({
                param($s,$e)
                if ($s.Enabled) { $s.BackColor = $colorAccentAlt }
            })
            $btn.Add_MouseLeave({
                param($s,$e)
                if ($s.Enabled) {
                    $s.BackColor = $colorAccent
                } else {
                    $s.BackColor = [System.Drawing.Color]::FromArgb(70,70,75)
                }
            })

            return $btn
        }

        $btnYes = New-ConfirmButton -Text "Ja"         -X 30  -Y 100
        $btnNo  = New-ConfirmButton -Text "Nein"       -X 155 -Y 100
        $btnAll = New-ConfirmButton -Text "Ja für alle"-X 270 -Y 100 -Width 110

        $btnYes.Add_Click({
            $form.Tag = 'Yes'
            $form.Close()
        })
        $btnNo.Add_Click({
            $form.Tag = 'No'
            $form.Close()
        })
        $btnAll.Add_Click({
            $form.Tag = 'All'
            $form.Close()
        })

        $form.Controls.Add($btnYes)
        $form.Controls.Add($btnNo)
        $form.Controls.Add($btnAll)

        $form.AcceptButton = $btnYes
        $form.CancelButton = $btnNo

        [void]$form.ShowDialog()

        switch ($form.Tag) {
            'All' {
                $script:OverwriteAll = $true
                Write-GuiLog "Überschreiben von '$ItemName' bestätigt – Ja für alle." 'INFO'
                return $true
            }
            'Yes' {
                Write-GuiLog "Überschreiben von '$ItemName' bestätigt (Einzelfall)." 'INFO'
                return $true
            }
            default {
                Write-GuiLog "Überschreiben von '$ItemName' abgelehnt." 'INFO'
                return $false
            }
        }
    } catch {
        Write-GuiLog "Konnte Überschreib-Dialog für '$ItemName' nicht anzeigen, fahre trotzdem fort." 'WARN'
        return $true
    }
}


# ===================== Browser-Erkennung & URL-Öffnen ========================

function Initialize-BrowserMap {
    <#
        Füllt $script:BrowserMap mit gefundenen Browsern.
        Keys: Name (Edge/Chrome/Firefox)
        Value: voller Pfad zur EXE.
    #>
    $script:BrowserMap.Clear()

    $pf   = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}

    $candidates = @(
        @{ Name = 'Edge';    Paths = @(
            (Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $pf   'Microsoft\Edge\Application\msedge.exe')
        ) },
        @{ Name = 'Chrome';  Paths = @(
            (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $pf   'Google\Chrome\Application\chrome.exe')
        ) },
        @{ Name = 'Firefox'; Paths = @(
            (Join-Path $pf86 'Mozilla Firefox\firefox.exe'),
            (Join-Path $pf   'Mozilla Firefox\firefox.exe')
        ) }
    )

    foreach ($c in $candidates) {
        foreach ($p in $c.Paths) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            if (Test-Path $p) {
                $script:BrowserMap[$c.Name] = $p
                break
            }
        }
    }
}

function Open-Url {
    <#
        Öffnet eine URL im gewählten Browser:
        - SystemDefault: Standardbrowser via Start-Process $Url
        - Sonst: expliziter Browserpfad aus $script:BrowserMap

        Leere URLs werden abgefangen und als WARN geloggt.
    #>
    param(
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-GuiLog "Open-Url: Leere URL übergeben (Button / Konfiguration prüfen)." 'WARN'
        return
    }

    Write-GuiLog "Open-Url: Versuche URL zu öffnen: $Url" 'INFO'

    try {
        $browserName = $script:SelectedBrowserName
        if ([string]::IsNullOrWhiteSpace($browserName)) {
            $browserName = 'SystemDefault'
        }

        if ($browserName -eq 'SystemDefault') {
            Start-Process -FilePath $Url | Out-Null
            return
        }

        $exe = $script:BrowserMap[$browserName]
        if (-not $exe -or -not (Test-Path $exe)) {
            Write-GuiLog "Open-Url: Browser '$browserName' nicht gefunden, verwende SystemDefault." 'WARN'
            Start-Process -FilePath $Url | Out-Null
            return
        }

        Write-GuiLog "Open-Url: verwende Browser '$browserName' ($exe)" 'INFO'
        Start-Process -FilePath $exe -ArgumentList $Url | Out-Null
    }
    catch {
        $msg = "Konnte Browser nicht öffnen:`n$Url`nFehler: " + $_.Exception.Message
        Write-GuiLog $msg 'ERROR'
        try {
            [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "Browser-Fehler",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        } catch { }
    }
}

# ===================== Installationsfunktionen ===============================

function Install-QuantV {
    param(
        [string]$GtaPath,
        [string]$DownloadRoot,
        [string]$StagingRoot
    )

    Write-GuiLog "=== QuantV Installation / Vorbereitung ==="

    $archive = Find-ModArchive -Root $DownloadRoot -Patterns @(
        "*QuantV*.zip","*Quant-V*.zip","*Quant V*.zip",
        "*QuantV*.rar","*Quant-V*.rar","*Quant V*.rar",
        "*QuantV*.7z","*Quant-V*.7z","*Quant V*.7z"
    )

    if (-not $archive) {
        Write-GuiLog "Kein QuantV-Archiv gefunden. Bitte im Download-Ordner ablegen." 'WARN'
        return
    }

    $quantvStaging = Join-Path $StagingRoot "QuantV"
    Ensure-Directory -Path $StagingRoot

    if (Test-Path $quantvStaging) {
        if (-not (Confirm-Overwrite -ItemName "QuantV-Staging" -Path $quantvStaging)) {
            return
        }
        Remove-Item -LiteralPath $quantvStaging -Recurse -Force
    }

    $ext = [System.IO.Path]::GetExtension($archive).ToLowerInvariant()

    if ($ext -eq ".zip") {
        Expand-ZipFile -ZipPath $archive -Destination $quantvStaging
        Write-GuiLog "QuantV in Staging entpackt: $quantvStaging"
        Write-GuiLog "Bitte dort README/Installationsanweisungen beachten."
    }
    else {
        Ensure-Directory -Path $quantvStaging
        $targetFile = Join-Path $quantvStaging (Split-Path $archive -Leaf)
        Copy-Item -Path $archive -Destination $targetFile -Force
        Write-GuiLog "QuantV-Archiv ist kein ZIP ($ext). In $quantvStaging kopiert."
    }

    Start-Process explorer.exe $quantvStaging
}

function Install-LARoads {
    param(
        [string]$GtaPath,
        [string]$DownloadRoot,
        [string]$StagingRoot
    )

    Write-GuiLog "=== LA Roads Installation / Vorbereitung ==="

    $archive = Find-ModArchive -Root $DownloadRoot -Patterns @(
        "LA*Roads*.zip","LA*Roads*.rar","LA*Roads*.oiv","LA_Roads*.zip"
    )

    if (-not $archive) {
        Write-GuiLog "Kein LA-Roads-Archiv gefunden. Bitte im Download-Ordner ablegen." 'WARN'
        return
    }

    $laStaging = Join-Path $StagingRoot "LA_Roads"
    Ensure-Directory -Path $StagingRoot

    if (Test-Path $laStaging) {
        if (-not (Confirm-Overwrite -ItemName "LA Roads-Staging" -Path $laStaging)) {
            return
        }
        Remove-Item -LiteralPath $laStaging -Recurse -Force
    }

    $ext = [System.IO.Path]::GetExtension($archive).ToLowerInvariant()

    if ($ext -eq ".zip") {
        Expand-ZipFile -ZipPath $archive -Destination $laStaging
        Write-GuiLog "LA Roads in Staging entpackt: $laStaging"
    }
    else {
        Ensure-Directory -Path $laStaging
        $targetFile = Join-Path $laStaging (Split-Path $archive -Leaf)
        Copy-Item -Path $archive -Destination $targetFile -Force
        Write-GuiLog "LA Roads Archiv ist kein ZIP ($ext). In $laStaging kopiert."
    }

    Start-Process explorer.exe $laStaging
}

function Install-Forests {
    param(
        [string]$GtaPath,
        [string]$DownloadRoot,
        [string]$StagingRoot
    )

    Write-GuiLog "=== Forests of San Andreas Installation / Vorbereitung ==="

    $archive = Find-ModArchive -Root $DownloadRoot -Patterns @(
        "Forests*San*Andreas*.zip","Forests*.zip","Forests*.oiv","Forests*.rar"
    )

    if (-not $archive) {
        Write-GuiLog "Kein Forests-of-San-Andreas-Archiv gefunden. Bitte im Download-Ordner ablegen." 'WARN'
        return
    }

    $forestStaging = Join-Path $StagingRoot "Forests_Of_San_Andreas"
    Ensure-Directory -Path $StagingRoot

    if (Test-Path $forestStaging) {
        if (-not (Confirm-Overwrite -ItemName "Forests of San Andreas-Staging" -Path $forestStaging)) {
            return
        }
        Remove-Item -LiteralPath $forestStaging -Recurse -Force
    }

    $ext = [System.IO.Path]::GetExtension($archive).ToLowerInvariant()

    if ($ext -eq ".zip") {
        Expand-ZipFile -ZipPath $archive -Destination $forestStaging
        Write-GuiLog "Forests in Staging entpackt: $forestStaging"
    }
    else {
        Ensure-Directory -Path $forestStaging
        $targetFile = Join-Path $forestStaging (Split-Path $archive -Leaf)
        Copy-Item -Path $archive -Destination $targetFile -Force
        Write-GuiLog "Forests-Archiv ist kein ZIP ($ext). In $forestStaging kopiert."
    }

    Start-Process explorer.exe $forestStaging
}

function Install-ReShadePreset {
    param(
        [string]$GtaPath,
        [string]$DownloadRoot,
        [string]$StagingRoot
    )

    Write-GuiLog "=== ReShade-Preset Installation ==="

    $zip = Find-ModArchive -Root $DownloadRoot -Patterns @(
        "*ReShade*Preset*.zip","*QuantV*ReShade*.zip","*Photorealistic*ReShade*.zip"
    )

    $presetStaging = Join-Path $StagingRoot "ReShade_Preset"
    Ensure-Directory -Path $StagingRoot

    if (Test-Path $presetStaging) {
        if (-not (Confirm-Overwrite -ItemName "ReShade-Preset-Staging" -Path $presetStaging)) {
            return
        }
        Remove-Item -LiteralPath $presetStaging -Recurse -Force
    }

    if ($zip) {
        Expand-ZipFile -ZipPath $zip -Destination $presetStaging
        Write-GuiLog "ReShade-Preset ZIP entpackt: $presetStaging"
    }
    else {
        Write-GuiLog "Keine ReShade-Preset-ZIP gefunden – suche .ini-Dateien."
        Ensure-Directory -Path $presetStaging

        $presetFiles = Get-ChildItem -Path $DownloadRoot -Filter "*.ini" -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match "reshade|preset|quantv" }

        if (-not $presetFiles) {
            Write-GuiLog "Keine geeigneten .ini Preset-Dateien gefunden." 'WARN'
            return
        }

        foreach ($file in $presetFiles) {
            Copy-Item -Path $file.FullName -Destination $presetStaging -Force
            Write-GuiLog "Preset-Datei kopiert: $($file.FullName)"
        }
    }

    $iniFiles = Get-ChildItem -Path $presetStaging -Filter "*.ini" -Recurse -ErrorAction SilentlyContinue

    if (-not $iniFiles) {
        Write-GuiLog "Keine .ini-Dateien im Preset-Staging-Verzeichnis gefunden." 'WARN'
    }
    else {
        foreach ($file in $iniFiles) {
            $target = Join-Path $GtaPath $file.Name
            if (Test-Path $target) {
                if (-not (Confirm-Overwrite -ItemName "ReShade-Preset-Datei $($file.Name)" -Path $target)) {
                    Write-GuiLog "Preset-Datei $($file.Name) wird nicht überschrieben."
                    continue
                }
            }
            Copy-Item -Path $file.FullName -Destination $target -Force
            Write-GuiLog "Preset nach GTA-Ordner kopiert: $($file.Name)"
        }
    }

    Start-Process explorer.exe $GtaPath
}

# ===================== Settings Tuner: Hilfsfunktionen =======================

function Get-GtaSettingsPath {
    $docs = [Environment]::GetFolderPath('MyDocuments')

    $candidates = @(
        (Join-Path $docs 'Rockstar Games\GTAV Enhanced\settings.xml'),
        (Join-Path $docs 'Rockstar Games\GTA V Enhanced\settings.xml'),
        (Join-Path $docs 'Rockstar Games\GTA V\settings.xml')
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Falls es noch keine gibt → vermutlich Enhanced-Variante
    return $candidates[0]
}

function Backup-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "Backup-File: '$Path' existiert nicht."
    }

    $dir = Split-Path $Path -Parent
    $name = Split-Path $Path -Leaf
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $backupName = "$name.bak_$stamp"
    $backupPath = Join-Path $dir $backupName

    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    return $backupPath
}

function Set-XmlNumericValueInText {
    param(
        [Parameter(Mandatory = $true)][string]$XmlText,
        [Parameter(Mandatory = $true)][string]$TagName,
        [Parameter(Mandatory = $true)][string]$NewValue
    )

    $pattern = "<$TagName\b([^>]*?)value=""[^""]*""([^>]*)/>"
    $replacement = "<$TagName`$1value=""$NewValue""`$2/>"

    $newText = [System.Text.RegularExpressions.Regex]::Replace(
        $XmlText,
        $pattern,
        $replacement
    )

    return $newText
}

function Set-XmlBoolValueInText {
    param(
        [Parameter(Mandatory = $true)][string]$XmlText,
        [Parameter(Mandatory = $true)][string]$TagName,
        [Parameter(Mandatory = $true)][bool]$NewBool
    )

    $valueString = if ($NewBool) { 'true' } else { 'false' }

    $pattern = "<$TagName\b([^>]*?)value=""(true|false)""([^>]*)/>"
    $replacement = "<$TagName`$1value=""$valueString""`$2/>"

    $newText = [System.Text.RegularExpressions.Regex]::Replace(
        $XmlText,
        $pattern,
        $replacement
    )

    return $newText
}

function Apply-GraphicsPresetToSettingsXml {
    param(
        [Parameter(Mandatory = $true)][string]$SettingsPath,
        [Parameter(Mandatory = $true)][string]$PresetName
    )

    if (-not (Test-Path $SettingsPath)) {
        throw "settings.xml nicht gefunden: $SettingsPath"
    }

    # Presets (Performance für 1070/1080p, Balanced etwas höher)
    $presets = @{
        'Performance' = @{
            TextureQuality        = '2'        # hoch
            ShadowQuality         = '1'
            ReflectionQuality     = '1'
            WaterQuality          = '2'
            GrassQuality          = '1'
            ShaderQuality         = '2'
            ParticleQuality       = '1'
            SSAO                  = '0'
            AnisotropicFiltering  = '8'
            PostFX                = '2'
            CityDensity           = '0.700000'
            PedVarietyMultiplier  = '0.800000'
            VehicleVarietyMultiplier = '0.800000'
            FXAA_Enabled          = $true
            TXAA_Enabled          = $false
            MSAA                  = '0'
            MSAAFragments         = '0'
            MSAAQuality           = '0'
            Shadow_SoftShadows    = '1'
            UltraShadows_Enabled  = $false
            Shadow_ParticleShadows = $false
            Shadow_LongShadows    = $false
            Lighting_FogVolumes   = $false
            HdStreamingInFlight   = $true
        }
        'Balanced' = @{
            TextureQuality        = '2'
            ShadowQuality         = '2'
            ReflectionQuality     = '2'
            WaterQuality          = '2'
            GrassQuality          = '2'
            ShaderQuality         = '2'
            ParticleQuality       = '2'
            SSAO                  = '1'
            AnisotropicFiltering  = '8'
            PostFX                = '2'
            CityDensity           = '0.900000'
            PedVarietyMultiplier  = '1.000000'
            VehicleVarietyMultiplier = '1.000000'
            FXAA_Enabled          = $true
            TXAA_Enabled          = $false
            MSAA                  = '0'
            MSAAFragments         = '0'
            MSAAQuality           = '0'
            Shadow_SoftShadows    = '2'
            UltraShadows_Enabled  = $false
            Shadow_ParticleShadows = $true
            Shadow_LongShadows    = $false
            Lighting_FogVolumes   = $true
            HdStreamingInFlight   = $true
        }
    }

    if (-not $presets.ContainsKey($PresetName)) {
        throw "Unbekannter Preset: $PresetName"
    }

    $config = $presets[$PresetName]

    $xmlText = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8

    $graphicsPattern = '(?s)(<graphics>.*?</graphics>)'
    $graphicsMatch = [System.Text.RegularExpressions.Regex]::Match($xmlText, $graphicsPattern)

    if (-not $graphicsMatch.Success) {
        throw "Konnte <graphics>-Block in settings.xml nicht finden."
    }

    $graphicsBlock = $graphicsMatch.Groups[1].Value

    foreach ($key in $config.Keys) {
        switch ($key) {
            { $_ -in @(
                'TextureQuality','ShadowQuality','ReflectionQuality','WaterQuality',
                'GrassQuality','ShaderQuality','ParticleQuality',
                'AnisotropicFiltering','PostFX'
            ) } {
                $graphicsBlock = Set-XmlNumericValueInText -XmlText $graphicsBlock -TagName $key -NewValue $config[$key]
            }
            { $_ -in @('CityDensity','PedVarietyMultiplier','VehicleVarietyMultiplier') } {
                $graphicsBlock = Set-XmlNumericValueInText -XmlText $graphicsBlock -TagName $key -NewValue $config[$key]
            }
            { $_ -in @('MSAA','MSAAFragments','MSAAQuality','SSAO') } {
                $graphicsBlock = Set-XmlNumericValueInText -XmlText $graphicsBlock -TagName $key -NewValue $config[$key]
            }
            default { }
        }
    }

    foreach ($key in $config.Keys) {
        switch ($key) {
            { $_ -in @('FXAA_Enabled','TXAA_Enabled','UltraShadows_Enabled',
                       'Shadow_ParticleShadows','Shadow_LongShadows',
                       'Lighting_FogVolumes','HdStreamingInFlight') } {
                $graphicsBlock = Set-XmlBoolValueInText -XmlText $graphicsBlock -TagName $key -NewBool $config[$key]
            }
            default { }
        }
    }

    $newXmlText = [System.Text.RegularExpressions.Regex]::Replace(
        $xmlText,
        $graphicsPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            return $graphicsBlock
        }
    )

    $backupPath = Backup-File -Path $SettingsPath
    Write-Host "Backup von settings.xml erstellt: $backupPath"

    Set-Content -LiteralPath $SettingsPath -Value $newXmlText -Encoding UTF8
}

function Update-CommandLineFile {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][string]$PresetName
    )

    if (-not (Test-Path $GameRoot)) {
        throw "Game Root existiert nicht: $GameRoot"
    }

    $cmdPath = Join-Path $GameRoot 'commandline.txt'

    $existing = @()
    if (Test-Path $cmdPath) {
        $existing = Get-Content -LiteralPath $cmdPath -Encoding UTF8
    }

    $ourKeys = @(
        '-textureQuality',
        '-shadowQuality',
        '-grassQuality',
        '-postFX',
        '-fxaa',
        '-msaa',
        '-txaa',
        '-anisotropicQualityLevel',
        '-lodScale',
        '-frameLimit'
    )

    $filtered = $existing | Where-Object {
        $line = $_.Trim()
        if ($line -eq '') { return $true }
        $isOurs = $false
        foreach ($k in $ourKeys) {
            if ($line -like "$k*") {
                $isOurs = $true
                break
            }
        }
        return -not $isOurs
    }

    switch ($PresetName) {
        'Performance' {
            $newLines = @(
                '-textureQuality 2',
                '-shadowQuality 1',
                '-grassQuality 1',
                '-postFX 2',
                '-fxaa 1',
                '-msaa 0',
                '-txaa 0',
                '-anisotropicQualityLevel 8',
                '-lodScale 0.8',
                '-frameLimit 0'
            )
        }
        default {
            $newLines = @(
                '-textureQuality 2',
                '-shadowQuality 2',
                '-grassQuality 2',
                '-postFX 2',
                '-fxaa 1',
                '-msaa 0',
                '-txaa 0',
                '-anisotropicQualityLevel 8',
                '-lodScale 0.9',
                '-frameLimit 0'
            )
        }
    }

    $final = $filtered + '' + '# GTA5 SettingsTuner (auto-generated)' + $newLines

    Set-Content -LiteralPath $cmdPath -Value $final -Encoding UTF8
}

# ===================== Settings Tuner GUI ====================================

function Start-GtaSettingsTuner {

    $colorBg        = [System.Drawing.Color]::FromArgb(20, 24, 28)
    $colorPanel     = [System.Drawing.Color]::FromArgb(32, 37, 43)
    $colorAccent    = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $colorAccentAlt = [System.Drawing.Color]::FromArgb(45, 170, 220)
    $colorText      = [System.Drawing.Color]::WhiteSmoke
    $colorLogBg     = [System.Drawing.Color]::FromArgb(15, 18, 22)

    $form                = New-Object ShadowForm
    $form.Text           = 'GTA V Enhanced – Settings Tuner'
    $form.Size           = New-Object System.Drawing.Size(760, 440)
    $form.StartPosition  = 'CenterScreen'
    $form.MaximizeBox    = $false
    $form.FormBorderStyle = 'FixedDialog'
    $form.BackColor      = $colorBg
    $form.Font           = New-Object System.Drawing.Font("Segoe UI", 9)

    # DoubleBuffer
    $flags = [System.Reflection.BindingFlags] "NonPublic,Instance"
    $prop  = $form.GetType().GetProperty("DoubleBuffered", $flags)
    if ($prop) { $prop.SetValue($form, $true, $null) }

    # optionales Hintergrundbild
    try {
        if ($script:SettingsTunerBackgroundImageUrl) {
            $wc = New-Object System.Net.WebClient
            try {
                $stream = $wc.OpenRead($script:SettingsTunerBackgroundImageUrl)
                if ($stream) {
                    $img = [System.Drawing.Image]::FromStream($stream)
                    $form.BackgroundImage = $img
                    $form.BackgroundImageLayout = 'Stretch'
                    $stream.Dispose()
                }
            } finally {
                $wc.Dispose()
            }
        }
    } catch { }

    # Overlay für Lesbarkeit
    $overlay = New-Object System.Windows.Forms.Panel
    $overlay.BackColor = [System.Drawing.Color]::FromArgb(200, $colorBg.R, $colorBg.G, $colorBg.B)
    $overlay.Location = New-Object System.Drawing.Point(0,0)
    $overlay.Size = $form.ClientSize
    $overlay.Anchor = 'Top,Left,Right,Bottom'
    $form.Controls.Add($overlay)

    # Header
    $header = New-Object System.Windows.Forms.Panel
    $header.BackColor = $colorAccent
    $header.Dock = 'Top'
    $header.Height = 46
    $overlay.Controls.Add($header)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "GTA V Settings Tuner"
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(12, 12)
    $header.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "Grafik-Presets · commandline.txt · Crosshair/Sensitivität Tipps"
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(230,230,230)
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblSubtitle.AutoSize = $true
    $lblSubtitle.Location = New-Object System.Drawing.Point(230, 18)
    $header.Controls.Add($lblSubtitle)

    function New-ModernButtonLocal {
        param(
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height
        )
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Location = New-Object System.Drawing.Point($X, $Y)
        $btn.Size = New-Object System.Drawing.Size($Width, $Height)
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = $colorAccent
        $btn.ForeColor = $colorText
        $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)

        $btn.Add_MouseEnter({
            param($s,$e)
            $s.BackColor = $colorAccentAlt
        })
        $btn.Add_MouseLeave({
            param($s,$e)
            if ($s.Enabled) {
                $s.BackColor = $colorAccent
            } else {
                $s.BackColor = [System.Drawing.Color]::FromArgb(70,70,75)
            }
        })

        return $btn
    }

    # Game-Path
    $lblGamePath = New-Object System.Windows.Forms.Label
    $lblGamePath.Text = 'GTA V Game-Ordner:'
    $lblGamePath.Location = New-Object System.Drawing.Point(15, 60)
    $lblGamePath.AutoSize = $true
    $lblGamePath.ForeColor = $colorText
    $overlay.Controls.Add($lblGamePath)

    $txtGamePath = New-Object System.Windows.Forms.TextBox
    $txtGamePath.Location = New-Object System.Drawing.Point(140, 58)
    $txtGamePath.Size = New-Object System.Drawing.Size(460, 22)
    $txtGamePath.BackColor = [System.Drawing.Color]::FromArgb(32,32,36)
    $txtGamePath.ForeColor = $colorText
    $txtGamePath.BorderStyle = 'FixedSingle'
    $txtGamePath.Text = $script:DefaultGtaPath
    $overlay.Controls.Add($txtGamePath)

    $btnBrowseGame = New-ModernButtonLocal -Text "Ordner..." -X 610 -Y 56 -Width 90 -Height 26
    $overlay.Controls.Add($btnBrowseGame)

    $folderDlg = New-Object System.Windows.Forms.FolderBrowserDialog

    $btnBrowseGame.Add_Click({
        if ($folderDlg.ShowDialog() -eq 'OK') {
            $txtGamePath.Text = $folderDlg.SelectedPath
        }
    })

    # settings.xml Pfad
    $lblSettingsPath = New-Object System.Windows.Forms.Label
    $lblSettingsPath.Text = 'settings.xml:'
    $lblSettingsPath.Location = New-Object System.Drawing.Point(15, 90)
    $lblSettingsPath.AutoSize = $true
    $lblSettingsPath.ForeColor = $colorText
    $overlay.Controls.Add($lblSettingsPath)

    $txtSettingsPath = New-Object System.Windows.Forms.TextBox
    $txtSettingsPath.Location = New-Object System.Drawing.Point(140, 88)
    $txtSettingsPath.Size = New-Object System.Drawing.Size(460, 22)
    $txtSettingsPath.ReadOnly = $true
    $txtSettingsPath.BackColor = [System.Drawing.Color]::FromArgb(32,32,36)
    $txtSettingsPath.ForeColor = $colorText
    $txtSettingsPath.BorderStyle = 'FixedSingle'
    $overlay.Controls.Add($txtSettingsPath)

    $txtSettingsPath.Text = Get-GtaSettingsPath

    # Group: Grafik-Preset
    $grpGraphics = New-Object System.Windows.Forms.GroupBox
    $grpGraphics.Text = 'Grafik-Preset (settings.xml / commandline.txt)'
    $grpGraphics.Location = New-Object System.Drawing.Point(15, 120)
    $grpGraphics.Size = New-Object System.Drawing.Size(360, 170)
    $grpGraphics.BackColor = $colorPanel
    $grpGraphics.ForeColor = $colorText
    $overlay.Controls.Add($grpGraphics)

    $lblPreset = New-Object System.Windows.Forms.Label
    $lblPreset.Text = 'Preset:'
    $lblPreset.Location = New-Object System.Drawing.Point(10, 25)
    $lblPreset.AutoSize = $true
    $lblPreset.ForeColor = $colorText
    $grpGraphics.Controls.Add($lblPreset)

    $cmbPreset = New-Object System.Windows.Forms.ComboBox
    $cmbPreset.Location = New-Object System.Drawing.Point(80, 22)
    $cmbPreset.Size = New-Object System.Drawing.Size(150, 20)
    [void]$cmbPreset.Items.Add('Performance (empfohlen)')
    [void]$cmbPreset.Items.Add('Balanced')
    $cmbPreset.SelectedIndex = 0
    $grpGraphics.Controls.Add($cmbPreset)

    $chkUpdateCmd = New-Object System.Windows.Forms.CheckBox
    $chkUpdateCmd.Text = 'commandline.txt mit anpassen'
    $chkUpdateCmd.Location = New-Object System.Drawing.Point(10, 55)
    $chkUpdateCmd.AutoSize = $true
    $chkUpdateCmd.ForeColor = $colorText
    $chkUpdateCmd.Checked = $true
    $grpGraphics.Controls.Add($chkUpdateCmd)

    $btnApplyGraphics = New-ModernButtonLocal -Text "Preset anwenden" -X 10 -Y 90 -Width 150 -Height 28
    $grpGraphics.Controls.Add($btnApplyGraphics)

    $btnOpenSettings = New-ModernButtonLocal -Text "settings.xml öffnen" -X 180 -Y 90 -Width 150 -Height 28
    $grpGraphics.Controls.Add($btnOpenSettings)

    # Group: Crosshair / Sensitivity
    $grpAim = New-Object System.Windows.Forms.GroupBox
    $grpAim.Text = 'Crosshair & Maus-Sensitivität (Empfehlungen)'
    $grpAim.Location = New-Object System.Drawing.Point(390, 120)
    $grpAim.Size = New-Object System.Drawing.Size(340, 170)
    $grpAim.BackColor = $colorPanel
    $grpAim.ForeColor = $colorText
    $overlay.Controls.Add($grpAim)

    $lblCross = New-Object System.Windows.Forms.Label
    $lblCross.Text = 'Crosshair:'
    $lblCross.Location = New-Object System.Drawing.Point(10, 25)
    $lblCross.AutoSize = $true
    $lblCross.ForeColor = $colorText
    $grpAim.Controls.Add($lblCross)

    $cmbCross = New-Object System.Windows.Forms.ComboBox
    $cmbCross.Location = New-Object System.Drawing.Point(100, 22)
    $cmbCross.Size = New-Object System.Drawing.Size(200, 20)
    [void]$cmbCross.Items.Add('Unverändert lassen')
    [void]$cmbCross.Items.Add('Simple (kleiner Punkt)')
    [void]$cmbCross.Items.Add('Complex (größer, mehr Infos)')
    $cmbCross.SelectedIndex = 1
    $grpAim.Controls.Add($cmbCross)

    $lblSens = New-Object System.Windows.Forms.Label
    $lblSens.Text = 'Empfohlene Maus-Sens:'
    $lblSens.Location = New-Object System.Drawing.Point(10, 55)
    $lblSens.AutoSize = $true
    $lblSens.ForeColor = $colorText
    $grpAim.Controls.Add($lblSens)

    $lblSensDetails = New-Object System.Windows.Forms.Label
    $lblSensDetails.Location = New-Object System.Drawing.Point(10, 75)
    $lblSensDetails.Size = New-Object System.Drawing.Size(320, 80)
    $lblSensDetails.ForeColor = [System.Drawing.Color]::FromArgb(210,210,215)
    $lblSensDetails.Text = @"
Im Spiel unter:
  Einstellungen → Tastatur/Maus

Vorschlag (M+KB, 1080p):
  - Look Sensitivity: ca. 60–70 %
  - Aim Sensitivity: ca. 40–50 %
  - Input Method: RAW
  - Windows: Mausbeschleunigung AUS
"@
    $grpAim.Controls.Add($lblSensDetails)

    # Log
    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Location = New-Object System.Drawing.Point(15, 300)
    $txtLog.Size = New-Object System.Drawing.Size(715, 90)
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.ReadOnly = $true
    $txtLog.BackColor = $colorLogBg
    $txtLog.ForeColor = $colorText
    $txtLog.BorderStyle = 'None'
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $overlay.Controls.Add($txtLog)

    function Write-LogLocal {
        param([string]$Message)
        $timestamp = (Get-Date).ToString('HH:mm:ss')
        $txtLog.AppendText("[$timestamp] $Message`r`n")
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    }

    # Button-Ena/Disable-Logik
    function Update-ApplyButtonState {
        $settingsPath = $txtSettingsPath.Text
        $gamePath     = $txtGamePath.Text

        $settingsOk = (Test-Path $settingsPath)
        $gameOk = $true

        if ($chkUpdateCmd.Checked) {
            $gameOk = (-not [string]::IsNullOrWhiteSpace($gamePath)) -and (Test-Path $gamePath)
        }

        if ($settingsOk -and $gameOk) {
            $btnApplyGraphics.Enabled = $true
            $btnApplyGraphics.BackColor = $colorAccent
        } else {
            $btnApplyGraphics.Enabled = $false
            $btnApplyGraphics.BackColor = [System.Drawing.Color]::FromArgb(70,70,75)
        }
    }

    Update-ApplyButtonState

    $txtGamePath.Add_TextChanged({ Update-ApplyButtonState })
    $chkUpdateCmd.Add_CheckedChanged({ Update-ApplyButtonState })

    # Events
    $btnOpenSettings.Add_Click({
        $settingsPath = $txtSettingsPath.Text
        if (-not (Test-Path $settingsPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "settings.xml wurde nicht gefunden.`nAktueller Pfad:`n$settingsPath",
                "Fehler",
                'OK',
                'Error'
            ) | Out-Null
            return
        }
        Write-LogLocal "Öffne settings.xml im Editor: $settingsPath"
        Start-Process notepad.exe -ArgumentList "`"$settingsPath`""
    })

    $btnApplyGraphics.Add_Click({
        try {
            if (-not $btnApplyGraphics.Enabled) {
                Write-LogLocal "Voraussetzungen für Preset nicht erfüllt (Pfad prüfen)."
                return
            }

            $settingsPath = $txtSettingsPath.Text
            if (-not (Test-Path $settingsPath)) {
                throw "settings.xml nicht gefunden: $settingsPath"
            }

            $presetUi = $cmbPreset.SelectedItem
            $presetInternal = switch -Wildcard ($presetUi) {
                'Performance*' { 'Performance' }
                'Balanced'     { 'Balanced' }
                default        { 'Performance' }
            }

            Write-LogLocal "================= Neuer Lauf ================="
            Write-LogLocal "Wende Grafik-Preset '$presetInternal' an auf $settingsPath ..."
            Apply-GraphicsPresetToSettingsXml -SettingsPath $settingsPath -PresetName $presetInternal
            Write-LogLocal "settings.xml angepasst."

            if ($chkUpdateCmd.Checked) {
                $gamePath = $txtGamePath.Text
                Write-LogLocal "Aktualisiere commandline.txt im Game-Ordner '$gamePath' ..."
                Update-CommandLineFile -GameRoot $gamePath -PresetName $presetInternal
                Write-LogLocal "commandline.txt aktualisiert."
            } else {
                Write-LogLocal "commandline.txt wurde NICHT geändert (Checkbox aus)."
            }

            $crossChoice = $cmbCross.SelectedItem
            $crossText = if ($crossChoice -like 'Simple*') {
                'Simple'
            } elseif ($crossChoice -like 'Complex*') {
                'Complex'
            } else {
                'nach Wunsch'
            }

            $msg = "Grafik-Preset '$presetInternal' angewendet.`n`n" +
                   "Crosshair-Empfehlung: $crossChoice`n" +
                   "→ Im Spiel: Einstellungen → Anzeige → Fadenkreuz: $crossText.`n`n" +
                   "Maus-Sensitivität in Einstellungen → Tastatur/Maus setzen:" +
                   "`n  Look: ~60–70 % | Aim: ~40–50 % | Input Method: RAW."

            [System.Windows.Forms.MessageBox]::Show(
                $msg,
                "Fertig",
                'OK',
                'Information'
            ) | Out-Null
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-LogLocal "FEHLER: $errMsg"
            [System.Windows.Forms.MessageBox]::Show(
                "Fehler beim Anwenden des Presets:`n$errMsg",
                "Fehler",
                'OK',
                'Error'
            ) | Out-Null
        }
    })

    # Keyboard: Enter & Escape
    $form.AcceptButton = $btnApplyGraphics
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($s,$e)
        if ($e.KeyCode -eq 'Escape') {
            $form.Close()
        }
    })

    [void]$form.ShowDialog()
}

# ===================== Haupt-GUI (Installer) =================================

function Start-GtaModInstaller {

    Ensure-Directory -Path $script:DefaultDownloadPath
    Initialize-BrowserMap

    # OverwriteAll-Flag pro Run zurücksetzen
    $script:OverwriteAll = $false

    $colorBg        = [System.Drawing.Color]::FromArgb(20, 24, 28)
    $colorPanel     = [System.Drawing.Color]::FromArgb(32, 37, 43)
    $colorAccent    = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $colorAccentAlt = [System.Drawing.Color]::FromArgb(45, 170, 220)
    $colorText      = [System.Drawing.Color]::WhiteSmoke
    $colorLogBg     = [System.Drawing.Color]::FromArgb(15, 18, 22)
    $colorDisabled  = [System.Drawing.Color]::FromArgb(120,120,120)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "GTA V Mod Installer"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size(930, 600)
    $form.MaximizeBox = $false
    $form.FormBorderStyle = 'FixedDialog'
    $form.BackColor = $colorBg
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Header
    $header = New-Object System.Windows.Forms.Panel
    $header.BackColor = $colorAccent
    $header.Dock = 'Top'
    $header.Height = 46
    $form.Controls.Add($header)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "GTA V Mod Installer"
    $lblTitle.ForeColor = $colorText
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(12, 12)
    $header.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "QuantV · LA Roads · Forests of San Andreas · ReShade · Settings Tuner"
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(230,230,230)
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblSubtitle.AutoSize = $true
    $lblSubtitle.Location = New-Object System.Drawing.Point(220, 18)
    $header.Controls.Add($lblSubtitle)

    function New-ModernButton {
        param(
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height
        )

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Location = New-Object System.Drawing.Point($X, $Y)
        $btn.Size = New-Object System.Drawing.Size($Width, $Height)
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = $colorAccent
        $btn.ForeColor = $colorText
        $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)

        $btn.Add_MouseEnter({
            param($s,$e)
            if ($s.Enabled) { $s.BackColor = $colorAccentAlt }
        })
        $btn.Add_MouseLeave({
            param($s,$e)
            if ($s.Enabled) {
                $s.BackColor = $colorAccent
            } else {
                $s.BackColor = [System.Drawing.Color]::FromArgb(70,70,75)
            }
        })

        return $btn
    }

    # GTA Pfad
    $labelGta = New-Object System.Windows.Forms.Label
    $labelGta.Text = "GTA V Installationsordner (mit GTA5*.exe):"
    $labelGta.AutoSize = $true
    $labelGta.ForeColor = $colorText
    $labelGta.Location = New-Object System.Drawing.Point(15, 60)
    $form.Controls.Add($labelGta)

    $textGta = New-Object System.Windows.Forms.TextBox
    $textGta.Location = New-Object System.Drawing.Point(15, 80)
    $textGta.Size = New-Object System.Drawing.Size(600, 22)
    $textGta.BackColor = [System.Drawing.Color]::FromArgb(32,32,36)
    $textGta.ForeColor = $colorText
    $textGta.BorderStyle = 'FixedSingle'
    $form.Controls.Add($textGta)

    if (Test-GtaFolder -Path $script:DefaultGtaPath) {
        $textGta.Text = $script:DefaultGtaPath
        Write-GuiLog "Default-GTA-Pfad erkannt und gesetzt: $($script:DefaultGtaPath)"
    }

    $btnGtaBrowse = New-ModernButton -Text "Ordner..." -X 625 -Y 78 -Width 90 -Height 26
    $form.Controls.Add($btnGtaBrowse)

    # Download Pfad
    $labelDownload = New-Object System.Windows.Forms.Label
    $labelDownload.Text = "Download-Ordner (Mod-Archive):"
    $labelDownload.AutoSize = $true
    $labelDownload.ForeColor = $colorText
    $labelDownload.Location = New-Object System.Drawing.Point(15, 112)
    $form.Controls.Add($labelDownload)

    $textDownload = New-Object System.Windows.Forms.TextBox
    $textDownload.Location = New-Object System.Drawing.Point(15, 132)
    $textDownload.Size = New-Object System.Drawing.Size(600, 22)
    $textDownload.BackColor = [System.Drawing.Color]::FromArgb(32,32,36)
    $textDownload.ForeColor = $colorText
    $textDownload.BorderStyle = 'FixedSingle'
    $form.Controls.Add($textDownload)

    if (Test-Path $script:DefaultDownloadPath) {
        $textDownload.Text = $script:DefaultDownloadPath
        Write-GuiLog "Default-Download-Ordner gesetzt: $($script:DefaultDownloadPath)"
    }

    $btnDownloadBrowse = New-ModernButton -Text "Ordner..." -X 625 -Y 130 -Width 90 -Height 26
    $form.Controls.Add($btnDownloadBrowse)

    # Staging-Hinweis
    $labelStagingInfo = New-Object System.Windows.Forms.Label
    $labelStagingInfo.Text = "Staging wird unterhalb des Download-Ordners erzeugt: '_staging'"
    $labelStagingInfo.AutoSize = $true
    $labelStagingInfo.ForeColor = [System.Drawing.Color]::FromArgb(180,180,185)
    $labelStagingInfo.Location = New-Object System.Drawing.Point(15, 162)
    $form.Controls.Add($labelStagingInfo)

    # GroupBox Mods
    $groupMods = New-Object System.Windows.Forms.GroupBox
    $groupMods.Text = "Zu installierende / vorzubereitende Mods"
    $groupMods.Location = New-Object System.Drawing.Point(15, 190)
    $groupMods.Size = New-Object System.Drawing.Size(715, 90)
    $groupMods.BackColor = $colorPanel
    $groupMods.ForeColor = $colorText
    $form.Controls.Add($groupMods)

    $cbQuantV = New-Object System.Windows.Forms.CheckBox
    $cbQuantV.Text = "QuantV (Grafik-Mod)"
    $cbQuantV.Location = New-Object System.Drawing.Point(15, 25)
    $cbQuantV.AutoSize = $true
    $cbQuantV.ForeColor = $colorText

    $cbLARoads = New-Object System.Windows.Forms.CheckBox
    $cbLARoads.Text = "LA Roads (Straßen-Texturen/Map)"
    $cbLARoads.Location = New-Object System.Drawing.Point(220, 25)
    $cbLARoads.AutoSize = $true
    $cbLARoads.ForeColor = $colorText

    $cbForests = New-Object System.Windows.Forms.CheckBox
    $cbForests.Text = "Forests of San Andreas (Vegetation)"
    $cbForests.Location = New-Object System.Drawing.Point(465, 25)
    $cbForests.AutoSize = $true
    $cbForests.ForeColor = $colorText

    $cbReShade = New-Object System.Windows.Forms.CheckBox
    $cbReShade.Text = "ReShade Preset installieren"
    $cbReShade.Location = New-Object System.Drawing.Point(15, 50)
    $cbReShade.AutoSize = $true
    $cbReShade.ForeColor = $colorText

    $groupMods.Controls.AddRange(@($cbQuantV, $cbLARoads, $cbForests, $cbReShade))

    # Install-Button
    $btnInstall = New-ModernButton -Text "Installation starten" -X 15 -Y 290 -Width 200 -Height 32
    $form.Controls.Add($btnInstall)

    # Settings Tuner Button
    $btnSettingsTuner = New-ModernButton -Text "Settings Tuner öffnen" -X 230 -Y 290 -Width 200 -Height 32
    $form.Controls.Add($btnSettingsTuner)

    # Hinweis
    $labelHint = New-Object System.Windows.Forms.Label
    $labelHint.Text = "Tipp: Mods zuerst rechts herunterladen, dann hier installieren. Settings Tuner passt settings.xml / commandline.txt an."
    $labelHint.AutoSize = $true
    $labelHint.ForeColor = [System.Drawing.Color]::FromArgb(190,190,195)
    $labelHint.Location = New-Object System.Drawing.Point(15, 330)
    $form.Controls.Add($labelHint)

    # Log-Box
    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Location = New-Object System.Drawing.Point(15, 355)
    $logBox.Size = New-Object System.Drawing.Size(715, 190)
    $logBox.ReadOnly = $true
    $logBox.BackColor = $colorLogBg
    $logBox.ForeColor = $colorText
    $logBox.BorderStyle = 'None'
    $logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $logBox.WordWrap = $false
    $logBox.DetectUrls = $true
    $form.Controls.Add($logBox)

    $script:LogControl = $logBox

    $logBox.Add_LinkClicked({
        param($sender, $e)
        $url = $e.LinkText
        Write-GuiLog "URL im Log angeklickt: $url" 'INFO'
        Open-Url -Url $url
    })

    # Download-Links rechts
    $groupLinks = New-Object System.Windows.Forms.GroupBox
    $groupLinks.Text = "Downloads"
    $groupLinks.Location = New-Object System.Drawing.Point(740, 60)
    $groupLinks.Size = New-Object System.Drawing.Size(170, 270)
    $groupLinks.BackColor = $colorPanel
    $groupLinks.ForeColor = $colorText
    $form.Controls.Add($groupLinks)

    function New-LinkButton {
        param(
            [string]$Text,
            [int]$Y,
            [string]$Url
        )

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Location = New-Object System.Drawing.Point(15, $Y)
        $btn.Size = New-Object System.Drawing.Size(135, 26)
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = [System.Drawing.Color]::FromArgb(50, 55, 62)
        $btn.ForeColor = $colorText
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

        $btn.Tag = $Url

        $btn.Add_MouseEnter({
            param($s,$e)
            if ($s.Enabled) {
                $s.BackColor = [System.Drawing.Color]::FromArgb(70, 75, 82)
            }
        })
        $btn.Add_MouseLeave({
            param($s,$e)
            $s.BackColor = if ($s.Enabled) {
                [System.Drawing.Color]::FromArgb(50, 55, 62)
            } else {
                [System.Drawing.Color]::FromArgb(60, 60, 60)
            }
        })

        if ([string]::IsNullOrWhiteSpace($Url)) {
            $btn.Enabled   = $false
            $btn.ForeColor = $colorDisabled
            $btn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
            Write-GuiLog "Download-Button '$Text' ohne URL konfiguriert – Button deaktiviert." 'WARN'
        }
        else {
            $btn.Add_Click({
                param($sender, $eventArgs)
                $targetUrl = [string]$sender.Tag
                Write-GuiLog "Download-Button '$($sender.Text)' geklickt. URL: $targetUrl" 'INFO'
                Open-Url -Url $targetUrl
            })
        }

        return $btn
    }

    $y = 25
    $groupLinks.Controls.Add( (New-LinkButton -Text "QuantV Free"      -Y $y  -Url $script:Link_QuantV_Free) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "QuantV Patreon"   -Y $y  -Url $script:Link_QuantV_Patreon) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "LA Roads + Patch" -Y $y  -Url $script:Link_LA_Roads) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "Forests Revised"  -Y $y  -Url $script:Link_Forests_Revised) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "Forests Ultimate" -Y $y  -Url $script:Link_Forests_Ultimate) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "ReShade"          -Y $y  -Url $script:Link_ReShade_Official) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "Preset: QV Photo" -Y $y  -Url $script:Link_ReShade_QuantV_Preset) )
    $y += 30
    $groupLinks.Controls.Add( (New-LinkButton -Text "Preset: QV Real"  -Y $y  -Url $script:Link_ReShade_QuantV_Realism) )

    # Browser-Auswahl
    $groupBrowser = New-Object System.Windows.Forms.GroupBox
    $groupBrowser.Text = "Browser für Downloads"
    $groupBrowser.Location = New-Object System.Drawing.Point(740, 330)
    $groupBrowser.Size = New-Object System.Drawing.Size(170, 215)
    $groupBrowser.BackColor = $colorPanel
    $groupBrowser.ForeColor = $colorText
    $form.Controls.Add($groupBrowser)

    $rbSystem = New-Object System.Windows.Forms.RadioButton
    $rbSystem.Text = "System-Standard"
    $rbSystem.Location = New-Object System.Drawing.Point(15, 25)
    $rbSystem.AutoSize = $true
    $rbSystem.ForeColor = $colorText
    $rbSystem.Checked = $true
    $groupBrowser.Controls.Add($rbSystem)

    $browserButtons = @{}

    function New-BrowserRadio {
        param(
            [string]$Name,
            [string]$Label,
            [int]$Y
        )

        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $Label
        $rb.Location = New-Object System.Drawing.Point(15, $Y)
        $rb.AutoSize = $true

        if ($script:BrowserMap.ContainsKey($Name)) {
            $rb.Enabled   = $true
            $rb.ForeColor = $colorText
        } else {
            $rb.Enabled   = $false
            $rb.ForeColor = $colorDisabled
        }

        $groupBrowser.Controls.Add($rb)
        $browserButtons[$Name] = $rb
    }

    New-BrowserRadio -Name 'Edge'    -Label 'Microsoft Edge' -Y 50
    New-BrowserRadio -Name 'Chrome'  -Label 'Google Chrome'  -Y 75
    New-BrowserRadio -Name 'Firefox' -Label 'Mozilla Firefox'-Y 100

    $rbSystem.Add_CheckedChanged({
        if ($rbSystem.Checked) {
            $script:SelectedBrowserName = 'SystemDefault'
            Write-GuiLog "Browser-Auswahl: System-Standard" 'INFO'
        }
    })

    foreach ($name in $browserButtons.Keys) {
        $rb = $browserButtons[$name]
        $rb.Add_CheckedChanged({
            if ($rb.Checked -and $rb.Enabled) {
                $script:SelectedBrowserName = $name
                Write-GuiLog "Browser-Auswahl: $name" 'INFO'
            }
        })
    }

    if ($script:BrowserMap.Count -gt 0) {
        $first = $script:BrowserMap.Keys | Select-Object -First 1
        if ($browserButtons.ContainsKey($first)) {
            $browserButtons[$first].Checked = $true
        }
    }

    # ----------------- Button-Logik & Events ---------------------------------

    function Update-InstallButtonState {
        $gtaPath      = $textGta.Text.Trim()
        $downloadPath = $textDownload.Text.Trim()

        $validGta      = (-not [string]::IsNullOrWhiteSpace($gtaPath)) -and (Test-GtaFolder -Path $gtaPath)
        $validDownload = (-not [string]::IsNullOrWhiteSpace($downloadPath)) -and (Test-Path $downloadPath)

        if ($validGta -and $validDownload) {
            $btnInstall.Enabled = $true
            $btnInstall.BackColor = $colorAccent
        } else {
            $btnInstall.Enabled = $false
            $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 75)
        }
    }

    Update-InstallButtonState
    $textGta.Add_TextChanged({ Update-InstallButtonState })
    $textDownload.Add_TextChanged({ Update-InstallButtonState })

    $btnGtaBrowse.Add_Click({
        $path = Show-FolderDialog -Description "GTA V Installationsordner auswählen (Ordner mit GTA5*.exe)"
        if ($path) {
            if (Test-GtaFolder -Path $path) {
                $textGta.Text = $path
                Write-GuiLog "GTA V Pfad gesetzt: $path"
            } else {
                Write-GuiLog "Ungültiger GTA-Ordner gewählt: $path" 'WARN'
                try {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Keine GTA5*.exe in diesem Ordner gefunden.",
                        "Ungültiger GTA-Ordner",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    ) | Out-Null
                } catch { }
            }
        }
    })

    $btnDownloadBrowse.Add_Click({
        $path = Show-FolderDialog -Description "Download-Ordner mit Mod-Archiven auswählen"
        if ($path) {
            $textDownload.Text = $path
            Write-GuiLog "Download-Ordner gesetzt: $path"
        }
    })

    $btnSettingsTuner.Add_Click({
        Start-GtaSettingsTuner
    })

    $btnInstall.Add_Click({
        try {
            if (-not $btnInstall.Enabled) {
                Write-GuiLog "Install-Button ist deaktiviert (Pfad(e) ungültig)." 'WARN'
                return
            }

            $logBox.Clear()

            $gtaPath      = $textGta.Text.Trim()
            $downloadPath = $textDownload.Text.Trim()
            $stagingRoot  = Join-Path $downloadPath "_staging"
            Ensure-Directory -Path $stagingRoot

            Write-GuiLog "================= Neuer Lauf ================="
            Write-GuiLog "GTA V Pfad: $gtaPath"
            Write-GuiLog "Download-Ordner: $downloadPath"
            Write-GuiLog "Staging-Ordner: $stagingRoot"

            if (-not ($cbQuantV.Checked -or $cbLARoads.Checked -or $cbForests.Checked -or $cbReShade.Checked)) {
                Write-GuiLog "Keine Mods ausgewählt. Abbruch."
                return
            }

            if ($cbQuantV.Checked) {
                Install-QuantV -GtaPath $gtaPath -DownloadRoot $downloadPath -StagingRoot $stagingRoot
            }
            if ($cbLARoads.Checked) {
                Install-LARoads -GtaPath $gtaPath -DownloadRoot $downloadPath -StagingRoot $stagingRoot
            }
            if ($cbForests.Checked) {
                Install-Forests -GtaPath $gtaPath -DownloadRoot $downloadPath -StagingRoot $stagingRoot
            }
            if ($cbReShade.Checked) {
                Install-ReShadePreset -GtaPath $gtaPath -DownloadRoot $downloadPath -StagingRoot $stagingRoot
            }

            Write-GuiLog "Installation / Vorbereitung abgeschlossen."
            try {
                [System.Windows.Forms.MessageBox]::Show(
                    "Vorgang abgeschlossen. Details siehe Log.",
                    "Fertig",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            } catch { }
        }
        catch {
            $err = $_.Exception
            $errMsg = $err.Message
            Write-GuiLog "FEHLER: $errMsg" 'ERROR'

            $msg = "Fehler beim Installieren:" + [Environment]::NewLine + $errMsg
            try {
                [System.Windows.Forms.MessageBox]::Show(
                    $msg,
                    "Fehler",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            } catch { }

            if ($script:UseExternalLogViewer -and (Test-Path $script:ExternalLogViewerPath)) {
                try {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName  = "powershell.exe"
                    $psi.Arguments = "-WindowStyle Minimized -ExecutionPolicy Bypass -File `"$script:ExternalLogViewerPath`" -LogFile `"$script:LogFilePath`" -ErrorsOnly"
                    $psi.UseShellExecute = $true
                    [System.Diagnostics.Process]::Start($psi) | Out-Null

                    Write-GuiLog "Externer Log-Viewer gestartet." 'INFO'
                } catch {
                    Write-GuiLog "Konnte externen Log-Viewer nicht starten." 'WARN'
                }
            }
        }
    })

    $form.AcceptButton = $btnInstall
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($s,$e)
        if ($e.KeyCode -eq 'Escape') { $form.Close() }
    })

    [void]$form.ShowDialog()
}

# ===================== Top-Level Start / Fehler-Handling =====================

try {
    Write-GuiLog "=== GTA5 Mod Installer gestartet ==="
    Start-GtaModInstaller
}
catch {
    $err = $_.Exception
    $msg = "FATALER FEHLER beim Start oder im Hauptlauf:" + [Environment]::NewLine + $err.Message
    Write-GuiLog $msg 'ERROR'

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Fataler Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch { }

    if ($script:UseExternalLogViewer -and (Test-Path $script:ExternalLogViewerPath)) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName  = "powershell.exe"
            $psi.Arguments = "-WindowStyle Minimized -ExecutionPolicy Bypass -File `"$script:ExternalLogViewerPath`" -LogFile `"$script:LogFilePath`" -ErrorsOnly"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null

            Write-GuiLog "Externer Log-Viewer nach fatalem Fehler gestartet." 'INFO'
        } catch {
            Write-GuiLog "Konnte externen Log-Viewer nach fatalem Fehler nicht starten." 'WARN'
        }
    }
}
