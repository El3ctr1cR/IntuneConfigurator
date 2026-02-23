# Main.ps1
# Duo Security - Intune Deployer
Clear-Host
$version = "v0.1.0"

$modulePaths = Get-ChildItem -Path (Join-Path $PSScriptRoot "modules") -Recurse -Include *.psm1
foreach ($module in $modulePaths) {
    Import-Module $module.FullName -Force
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

# Reprint banner after clear
Write-Host "Packages and deploys Duo Security Windows Logon to Intune automatically." -ForegroundColor Gray
Write-Host "Created by El3ctr1cR" -ForegroundColor Gray
Write-Host "[$version] https://github.com/El3ctr1cR/IntuneConfigurator" -ForegroundColor Gray
Write-Host ""

# Login
Read-Host -Prompt "Press Enter to login and begin deployment"
Clear-Host

if (-not (Connect-ToMSGraph)) {
    Write-Error "Cannot proceed without Microsoft Graph connection"
    return
}

# Collect Duo credentials
$duoConfig = Get-DuoConfig

if (-not $duoConfig) {
    Write-Host "No Duo configuration provided. Exiting..." -ForegroundColor Yellow
    return
}

# Download installer
$buildPath    = Join-Path $PSScriptRoot "build"
$installerFile = Invoke-DuoDownload -BuildPath $buildPath

if (-not $installerFile) {
    Write-Error "Cannot proceed without the downloaded installer"
    return
}

# Build .intunewin
$intuneWinFile = Invoke-IntuneWinBuild -AgentFilePath $installerFile `
                                       -BuildPath $buildPath `
                                       -RootPath $PSScriptRoot

if (-not $intuneWinFile) {
    Write-Error "Cannot proceed without a valid .intunewin package"
    return
}

# Deploy Win32 app to Intune
$installerFileName = [System.IO.Path]::GetFileName($installerFile)
Invoke-DuoDeploy -IntuneWinFilePath $intuneWinFile `
                 -InstallerFileName $installerFileName `
                 -InstallerFilePath $installerFile `
                 -DuoConfig $duoConfig

# Deploy Remediation script
Invoke-DuoRemediationDeploy

Write-Host ""
Read-Host -Prompt "Press Enter to close the script..."

Write-Host ""

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}
