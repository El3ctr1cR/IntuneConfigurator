# Main.ps1
# Printer - Intune Deployer
Clear-Host
$version = "v0.1.0"

$modulePaths = Get-ChildItem -Path (Join-Path $PSScriptRoot "modules") -Recurse -Include *.psm1
foreach ($module in $modulePaths) {
    Import-Module $module.FullName -Force
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[!] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "    PrintBrm.exe requires elevated privileges to export printers." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to exit"
    return
}

if (-not (Install-RequiredModules) -or -not (Import-RequiredModules)) {
    Write-Error "Cannot proceed without required modules"
    return
}

if (-not (Assert-IntuneWinAppUtil -RootPath $PSScriptRoot)) {
    Write-Error "Cannot proceed without IntuneWinAppUtil"
    return
}

Clear-Host

Write-Host "Exports a printer and deploys it to Intune as a Win32 app." -ForegroundColor Gray
Write-Host "Created by El3ctr1cR" -ForegroundColor Gray
Write-Host "[$version] https://github.com/El3ctr1cR/IntuneConfigurator" -ForegroundColor Gray
Write-Host ""
Read-Host -Prompt "Press Enter to login and begin deployment"
Clear-Host

if (-not (Connect-ToMSGraph)) {
    Write-Error "Cannot proceed without Microsoft Graph connection"
    return
}

# Printer selection (returns one or more printer names)
$selectedPrinters = Select-Printers

if (-not $selectedPrinters -or $selectedPrinters.Count -eq 0) {
    Write-Host "No printers selected. Exiting..." -ForegroundColor Yellow
    return
}

# Export + deploy loop
$buildRootPath = Join-Path $PSScriptRoot "build"

$succeeded = @()
$failed    = @()
$total     = $selectedPrinters.Count
$current   = 0

foreach ($printerName in $selectedPrinters) {
    $current++

    Write-Host ""
    Write-Host "=== Processing $current / $total : $printerName ===" -ForegroundColor Cyan
    Write-Host ""

    # Each printer builds into its own subfolder to avoid collisions
    $safeName  = ($printerName -replace '[\\/:*?"<>|]', '_').Trim()
    $buildPath = Join-Path $buildRootPath $safeName

    # Export, edit, repack, package
    $result = Invoke-PrinterExport -PrinterName $printerName `
                                   -BuildPath   $buildPath `
                                   -RootPath    $PSScriptRoot

    if (-not $result) {
        Write-Host "[FAILED] Export failed for '$printerName' - skipping deploy." -ForegroundColor Red
        $failed += $printerName
        continue
    }

    # Deploy to Intune
    $deployed = Invoke-PrinterDeploy -PrinterName       $printerName `
                                     -IntuneWinFilePath $result.IntuneWinFile `
                                     -DetectScriptPath  $result.DetectScriptPath

    if ($deployed) {
        Write-Host "[OK] '$printerName' deployed successfully." -ForegroundColor Green
        $succeeded += $printerName
    }
    else {
        Write-Host "[FAILED] Deploy failed for '$printerName'." -ForegroundColor Red
        $failed += $printerName
    }
}

# Summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "$($succeeded.Count) succeeded / $($failed.Count) failed" -ForegroundColor Gray
Write-Host ""

foreach ($name in $succeeded) {
    Write-Host "  [OK]     $name" -ForegroundColor Green
}

foreach ($name in $failed) {
    Write-Host "  [FAILED] $name" -ForegroundColor Red
}

Write-Host ""
Read-Host -Prompt "Press Enter to clean up and close the script..."
Write-Host ""

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch { }