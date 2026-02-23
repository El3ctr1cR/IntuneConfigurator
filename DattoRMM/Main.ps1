# Main.ps1
# Datto RMM Agent - Intune Deployer
$version = "v0.1.0"
Clear-Host

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

Write-Host "Easily deploy Datto RMM to your Intune environment as a Win32 app." -ForegroundColor Gray
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

# Get agent
$agentLink = Get-AgentLink

if ([string]::IsNullOrWhiteSpace($agentLink)) {
    Write-Host "No agent link provided. Exiting..." -ForegroundColor Yellow
    return
}

# Download agent
$buildPath  = Join-Path $PSScriptRoot "build"
$agentFile  = Invoke-AgentDownload -AgentLink $agentLink -BuildPath $buildPath

if (-not $agentFile) {
    Write-Error "Cannot proceed without the downloaded agent"
    return
}

# Build .intunewin file
$intuneWinFile = Invoke-IntuneWinBuild -AgentFilePath $agentFile `
                                       -BuildPath $buildPath `
                                       -RootPath $PSScriptRoot

if (-not $intuneWinFile) {
    Write-Error "Cannot proceed without a valid .intunewin package"
    return
}

# Deploy to intune
$agentFileName = [System.IO.Path]::GetFileName($agentFile)
Invoke-IntuneDeploy -IntuneWinFilePath $intuneWinFile `
                    -AgentFileName $agentFileName `
                    -AgentFilePath $agentFile

Write-Host ""
Read-Host -Prompt "Press Enter to close the script..."

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}