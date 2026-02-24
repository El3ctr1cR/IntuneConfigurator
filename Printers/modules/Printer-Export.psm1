# modules/Printer-Export.psm1

$PrintBrm = "$env:windir\System32\spool\tools\PrintBrm.exe"

#region - Helpers

function Invoke-PrintBrm {
    param([string]$ArgString)

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    try {
        $proc = Start-Process -FilePath $PrintBrm `
            -ArgumentList $ArgString `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr

        $stdout = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
        $combined = @($stdout, $stderr) -join "`n"

        if ($proc.ExitCode -ne 0) {
            throw "PrintBrm.exe failed (exit $($proc.ExitCode)): $combined"
        }

        return $combined
    }
    finally {
        Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
    }
}

function Get-SafeFileName {
    param([string]$Name)
    $safe = $Name -replace '[\\/:*?"<>|]', '_'
    $safe = $safe.Trim()
    return $safe
}

#endregion

#region - Main export function

function Select-Printer {

    Write-Host ""
    Write-Host "=== Printer Selection ===" -ForegroundColor Cyan
    Write-Host ""

    $printBrm = "$env:windir\System32\spool\tools\PrintBrm.exe"

    if (-not (Test-Path $printBrm)) {
        Write-Error "PrintBrm.exe not found at: $printBrm"
        return $null
    }

    # Query local printers
    Write-Host "Querying local print queues..." -ForegroundColor Yellow

    try {
        $output = & $printBrm -q 2>&1
    }
    catch {
        Write-Error "Failed to run PrintBrm.exe: $($_.Exception.Message)"
        return $null
    }

    # Parse print queues section only
    $queues = @()
    $inSection = $false

    foreach ($line in $output) {
        $trimmed = $line.ToString().Trim()

        if ($trimmed -eq "LISTING PRINT QUEUES") {
            $inSection = $true
            continue
        }

        if ($inSection -and $trimmed -match "^LISTING ") {
            break
        }

        if ($inSection -and $trimmed -ne "" -and $trimmed -notmatch "^Successfully") {
            $queues += $trimmed
        }
    }

    if ($queues.Count -eq 0) {
        Write-Host "No local print queues found." -ForegroundColor Yellow
        return $null
    }

    Write-Host "Available printers on this machine:" -ForegroundColor Gray
    Write-Host ""

    for ($i = 0; $i -lt $queues.Count; $i++) {
        Write-Host "  [$($i + 1)] $($queues[$i])" -ForegroundColor White
    }

    Write-Host ""

    while ($true) {
        Write-Host "Enter number to deploy (1-$($queues.Count)): " -ForegroundColor Yellow -NoNewline
        $input = Read-Host

        if ($input -match '^\d+$') {
            $idx = [int]$input - 1
            if ($idx -ge 0 -and $idx -lt $queues.Count) {
                $chosen = $queues[$idx]
                Write-Host ""
                Write-Host "Selected : $chosen" -ForegroundColor Green
                Write-Host ""
                return $chosen
            }
        }

        Write-Host "Invalid selection. Please enter a number between 1 and $($queues.Count)." -ForegroundColor Red
    }
}

Export-ModuleMember -Function Select-Printer

function Invoke-PrinterExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrinterName,

        [Parameter(Mandatory = $true)]
        [string]$BuildPath,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    Write-Host ""
    Write-Host "=== Exporting Printer ===" -ForegroundColor Cyan
    Write-Host "Printer : $PrinterName" -ForegroundColor Gray
    Write-Host ""

    $fullExportFile   = Join-Path $BuildPath "full.printerExport"
    $unpackDir        = Join-Path $BuildPath "unpack"
    $singleExportFile = Join-Path $BuildPath "single.printerExport"
    $packageDir       = Join-Path $BuildPath "package"
    $intunewinDir     = Join-Path $BuildPath "intunewin"

    foreach ($dir in @($BuildPath, $unpackDir, $packageDir, $intunewinDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Step 1: Full export
    Write-Host "Step 1/7 : Exporting all printers to full.printerExport..." -ForegroundColor Yellow

    if (Test-Path $fullExportFile) { Remove-Item $fullExportFile -Force }

    try {
        Invoke-PrintBrm -ArgString "-b -f $fullExportFile" | Out-Null
        Write-Host "  Exported to: $fullExportFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Export failed: $($_.Exception.Message)"
        return $null
    }

    # Step 2: Unpack
    Write-Host "Step 2/7 : Unpacking export..." -ForegroundColor Yellow

    if (Test-Path $unpackDir) { Remove-Item $unpackDir -Recurse -Force }
    New-Item -ItemType Directory -Path $unpackDir -Force | Out-Null

    try {
        $unpackOutput = Invoke-PrintBrm -ArgString "-r -d $unpackDir -f $fullExportFile"
        Write-Host "  Unpacked to: $unpackDir" -ForegroundColor Green
        if ($unpackOutput) {
            Write-Host "  PrintBrm output:" -ForegroundColor DarkGray
            $unpackOutput -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Error "Unpack failed: $($_.Exception.Message)"
        return $null
    }

    # Step 3: Parse BrmPrinters.xml
    Write-Host "Step 3/7 : Editing BrmPrinters.xml..." -ForegroundColor Yellow

    $brmPrintersPath = Get-ChildItem -Path $unpackDir -Filter "BrmPrinters.xml" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $brmPrintersPath) {
        Write-Host ""
        Write-Host "[!] BrmPrinters.xml not found. Unpack directory contents:" -ForegroundColor Yellow
        Get-ChildItem -Path $unpackDir -Recurse | ForEach-Object {
            Write-Host "    $($_.FullName)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Error "BrmPrinters.xml not found in unpack directory."
        return $null
    }

    $unpackRoot = [System.IO.Path]::GetDirectoryName($brmPrintersPath)
    Write-Host "  Unpack root : $unpackRoot" -ForegroundColor DarkGray

    [xml]$brmPrinters = Get-Content $brmPrintersPath -Encoding UTF8

    $chosenEntry = $brmPrinters.PRINTERS.PRINTQUEUE |
        Where-Object { $_.PrinterName -eq $PrinterName } |
        Select-Object -First 1

    if (-not $chosenEntry) {
        Write-Error "Printer '$PrinterName' not found in BrmPrinters.xml."
        return $null
    }

    $printerXmlFileName = $chosenEntry.FileName
    Write-Host "  Printer XML file : $printerXmlFileName" -ForegroundColor Green

    $toRemove = $brmPrinters.PRINTERS.PRINTQUEUE | Where-Object { $_.PrinterName -ne $PrinterName }
    foreach ($node in @($toRemove)) {
        $brmPrinters.PRINTERS.RemoveChild($node) | Out-Null
    }

    $brmPrinters.Save($brmPrintersPath)
    Write-Host "  BrmPrinters.xml updated (kept: $PrinterName)" -ForegroundColor Green

    # Step 4: Parse printer XML for PortName and DriverName
    Write-Host "Step 4/7 : Reading printer config from $printerXmlFileName..." -ForegroundColor Yellow

    $printerXmlPath = Join-Path $unpackRoot "Printers" $printerXmlFileName
    if (-not (Test-Path $printerXmlPath)) {
        Write-Error "Printer XML not found: $printerXmlPath"
        return $null
    }

    [xml]$printerXml = Get-Content $printerXmlPath -Encoding UTF8
    $printerQueue    = $printerXml.PRINTQUEUE

    $portName   = $printerQueue.PortName
    $driverName = $printerQueue.DriverName

    Write-Host "  PortName   : $portName" -ForegroundColor Green
    Write-Host "  DriverName : $driverName" -ForegroundColor Green

    $printersDir = Join-Path $unpackRoot "Printers"
    Get-ChildItem -Path $printersDir -Filter "*.xml" |
        Where-Object { $_.Name -ne $printerXmlFileName } |
        ForEach-Object { Remove-Item $_.FullName -Force }
    Write-Host "  Removed other printer XMLs." -ForegroundColor Green

    # Step 5: Edit BrmDrivers.xml
    Write-Host "Step 5/7 : Editing BrmDrivers.xml..." -ForegroundColor Yellow

    $brmDriversPath = Join-Path $unpackRoot "BrmDrivers.xml"
    if (-not (Test-Path $brmDriversPath)) {
        Write-Error "BrmDrivers.xml not found."
        return $null
    }

    [xml]$brmDrivers = Get-Content $brmDriversPath -Encoding UTF8

    $driversToRemove = $brmDrivers.PRINTERDRIVERS.DRIVER |
        Where-Object { $_.DriverName -ne $driverName }

    foreach ($node in @($driversToRemove)) {
        $brmDrivers.PRINTERDRIVERS.RemoveChild($node) | Out-Null
    }

    $brmDrivers.Save($brmDriversPath)
    $keptCount = ($brmDrivers.PRINTERDRIVERS.DRIVER | Measure-Object).Count
    Write-Host "  BrmDrivers.xml updated (kept $keptCount DRIVER entry for: $driverName)" -ForegroundColor Green

    # Step 6: Edit BrmPorts.xml
    Write-Host "Step 6/7 : Editing BrmPorts.xml..." -ForegroundColor Yellow

    $brmPortsPath = Join-Path $unpackRoot "BrmPorts.xml"
    if (-not (Test-Path $brmPortsPath)) {
        Write-Error "BrmPorts.xml not found."
        return $null
    }

    [xml]$brmPorts = Get-Content $brmPortsPath -Encoding UTF8

    $portsToRemove = $brmPorts.PRINTERPORTS.SPM |
        Where-Object { $_.PortName -ne $portName }

    foreach ($node in @($portsToRemove)) {
        $brmPorts.PRINTERPORTS.RemoveChild($node) | Out-Null
    }

    $brmPorts.Save($brmPortsPath)
    Write-Host "  BrmPorts.xml updated (kept port: $portName)" -ForegroundColor Green

    Write-Host "Step 7/7 : Repacking single-printer export..." -ForegroundColor Yellow

    if (Test-Path $singleExportFile) { Remove-Item $singleExportFile -Force }

    try {
        Invoke-PrintBrm -ArgString "-b -d $unpackRoot -f $singleExportFile" | Out-Null
        Write-Host "  Repacked to: $singleExportFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Repack failed: $($_.Exception.Message)"
        return $null
    }

    Remove-Item $fullExportFile  -Force -ErrorAction SilentlyContinue
    Remove-Item $unpackDir       -Recurse -Force -ErrorAction SilentlyContinue

    # Assemble package folder
    Write-Host ""
    Write-Host "=== Assembling Package ===" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $packageDir) { Remove-Item $packageDir -Recurse -Force }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

    $exportFileName = "single.printerExport"
    Copy-Item $singleExportFile -Destination (Join-Path $packageDir $exportFileName)
    Write-Host "  Copied $exportFileName" -ForegroundColor Green

    $scriptsSourceDir = Join-Path $RootPath "scripts"
    foreach ($scriptName in @("deploy.ps1", "detect.ps1", "remove.ps1")) {
        $src = Join-Path $scriptsSourceDir $scriptName
        if (-not (Test-Path $src)) {
            Write-Error "Source script not found: $src"
            return $null
        }

        $content = Get-Content $src -Raw

        $content = $content -replace [regex]::Escape("<REPLACE_WITH_PRINTER_NAME>"), $PrinterName

        $dest = Join-Path $packageDir $scriptName
        Set-Content -Path $dest -Value $content -Encoding UTF8 -Force
        Write-Host "  Written $scriptName (placeholders filled)" -ForegroundColor Green
    }

    # Build .intunewin
    Write-Host ""
    Write-Host "=== Building .intunewin Package ===" -ForegroundColor Cyan
    Write-Host ""

    $toolPath = Join-Path $RootPath "tools" "IntuneWinAppUtil.exe"

    if (-not (Test-Path $intunewinDir)) {
        New-Item -ItemType Directory -Path $intunewinDir -Force | Out-Null
    }

    $intunewinFile = Join-Path $intunewinDir "deploy.intunewin"

    if (Test-Path $intunewinFile) {
        Write-Host "Package already exists, skipping build." -ForegroundColor Yellow
        Write-Host "File: $intunewinFile" -ForegroundColor Gray
    }
    else {
        Write-Host "Running IntuneWinAppUtil..." -ForegroundColor Yellow
        Write-Host "  Source  : $packageDir" -ForegroundColor DarkGray
        Write-Host "  Setup   : deploy.ps1" -ForegroundColor DarkGray
        Write-Host "  Output  : $intunewinDir" -ForegroundColor DarkGray
        Write-Host ""

        try {
            $proc = Start-Process -FilePath $toolPath `
                -ArgumentList "-c `"$packageDir`" -s deploy.ps1 -o `"$intunewinDir`" -q" `
                -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) {
                throw "IntuneWinAppUtil exited with code $($proc.ExitCode)"
            }
        }
        catch {
            Write-Error "IntuneWinAppUtil failed: $($_.Exception.Message)"
            return $null
        }

        if (-not (Test-Path $intunewinFile)) {
            Write-Error "Expected .intunewin not found at: $intunewinFile"
            return $null
        }

        Write-Host "  Package built successfully." -ForegroundColor Green
    }

    Write-Host ""

    return @{
        IntuneWinFile    = $intunewinFile
        DetectScriptPath = Join-Path $packageDir "detect.ps1"
        ExportFileName   = $exportFileName
    }
}

#endregion

Export-ModuleMember -Function Invoke-PrinterExport