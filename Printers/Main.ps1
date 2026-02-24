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

# Printer selection
$selectedPrinter = Select-Printer

if ([string]::IsNullOrWhiteSpace($selectedPrinter)) {
    Write-Host "No printer selected. Exiting..." -ForegroundColor Yellow
    return
}

# Export, edit, repack, package
$buildPath = Join-Path $PSScriptRoot "build"

$result = Invoke-PrinterExport -PrinterName $selectedPrinter `
                               -BuildPath $buildPath `
                               -RootPath $PSScriptRoot

if (-not $result) {
    Write-Error "Cannot proceed - printer export or packaging failed"
    return
}

# Deploy to Intune
Invoke-PrinterDeploy -PrinterName $selectedPrinter `
                     -IntuneWinFilePath $result.IntuneWinFile `
                     -DetectScriptPath $result.DetectScriptPath

Write-Host ""
Read-Host -Prompt "Press Enter to clean up and close the script..."

Write-Host ""

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch { }
