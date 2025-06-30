# Main.ps1
# Import modules
$modulePaths = Get-ChildItem -Path (Join-Path $PSScriptRoot "modules") -Recurse -Include *.psm1
foreach ($module in $modulePaths) {
    Import-Module $module.FullName -Force
}

# Main execution
Write-Host ""
Write-Host "=== Enhanced Intune Configuration Script ===" -ForegroundColor Cyan
Write-Host "This script will create configuration profiles, Autopilot profiles, ESP profiles, and applications for Intune" -ForegroundColor Cyan
Write-Host ""

# Get configuration paths
$paths = Get-ConfigurationPaths -RootPath $PSScriptRoot

# Initialize configuration folders
if (-not (Initialize-ConfigFolders -ConfigFolderPath $paths.ConfigFolderPath -AutopilotFolderPath $paths.AutopilotFolderPath -ESPFolderPath $paths.ESPFolderPath -AppsFolderPath $paths.AppsFolderPath)) {
    Write-Error "Cannot proceed without configuration files"
    return
}

Write-Host ""

# Install and import required modules
if (-not (Install-RequiredModules) -or -not (Import-RequiredModules)) {
    Write-Error "Cannot proceed without required modules"
    return
}

# Connect to Microsoft Graph
if (-not (Connect-ToMSGraph)) {
    Write-Error "Cannot proceed without Microsoft Graph connection"
    return
}

# Load all profiles
$removeReadOnlyProperties = (Get-Command Remove-ReadOnlyProperties).ScriptBlock
$profiles = Get-AllProfiles -ConfigFolderPath $paths.ConfigFolderPath `
    -AutopilotFolderPath $paths.AutopilotFolderPath `
    -ESPFolderPath $paths.ESPFolderPath `
    -AppsFolderPath $paths.AppsFolderPath `
    -RemoveReadOnlyProperties $removeReadOnlyProperties

if ($profiles.TotalItems -eq 0) {
    Write-Host "No valid configuration files were found or loaded." -ForegroundColor Yellow
    return
}

Write-Host ""

# Show selection menu
$selectedItems = Show-AllProfilesSelectionMenu -ConfigPolicies $profiles.ConfigPolicies `
    -AutopilotProfiles $profiles.AutopilotProfiles `
    -ESPProfiles $profiles.ESPProfiles `
    -Apps $profiles.Apps

if ($selectedItems.Count -eq 0) {
    Write-Host "No items selected. Exiting..." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "=== Selected Items ===" -ForegroundColor Cyan
foreach ($item in $selectedItems) {
    $typeText = switch ($item.Type) {
        "Autopilot" { " (Autopilot Profile)" }
        "ESP" { " (ESP Profile)" }
        "App" { " (Application)" }
        default { " (Configuration Policy)" }
    }
    Write-Host "- $($item.Name)$typeText" -ForegroundColor Green
}
Write-Host ""
Write-Host "Press any key to continue with item creation..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# Process selected items
$validateDeviceNameTemplate = (Get-Command Test-DeviceNameTemplate).ScriptBlock
$setAutopilotAssignments = (Get-Command Set-AutopilotAssignments).ScriptBlock
$setESPAssignments = (Get-Command Set-ESPAssignments).ScriptBlock
$setPolicyAssignments = (Get-Command Set-PolicyAssignments).ScriptBlock
$setLegacyPolicyAssignments = (Get-Command Set-LegacyPolicyAssignments).ScriptBlock
$setAppAssignments = (Get-Command Set-AppAssignments).ScriptBlock
$testAutopilotProfileExists = (Get-Command Test-AutopilotProfileExists).ScriptBlock
$testESPProfileExists = (Get-Command Test-ESPProfileExists).ScriptBlock
$testPolicyExists = (Get-Command Test-PolicyExists).ScriptBlock
$testAppExists = (Get-Command Test-AppExists).ScriptBlock
$getTenantId = (Get-Command Get-TenantId).ScriptBlock
$updateOneDrivePolicyWithTenantId = (Get-Command Update-OneDrivePolicyWithTenantId).ScriptBlock
$updateTenantIdInChildren = (Get-Command Update-TenantIdInChildren).ScriptBlock
$enableLAPSInEntraID = (Get-Command Enable-LAPSInEntraID).ScriptBlock
$requestEdgeSyncConfiguration = (Get-Command Request-EdgeSyncConfiguration).ScriptBlock

Invoke-SelectedItems -SelectedItems $selectedItems `
    -ConfigFolderPath $paths.ConfigFolderPath `
    -AutopilotFolderPath $paths.AutopilotFolderPath `
    -ESPFolderPath $paths.ESPFolderPath `
    -AppsFolderPath $paths.AppsFolderPath `
    -RemoveReadOnlyProperties $removeReadOnlyProperties `
    -ValidateDeviceNameTemplate $validateDeviceNameTemplate `
    -SetAutopilotAssignments $setAutopilotAssignments `
    -SetESPAssignments $setESPAssignments `
    -SetPolicyAssignments $setPolicyAssignments `
    -SetLegacyPolicyAssignments $setLegacyPolicyAssignments `
    -SetAppAssignments $setAppAssignments `
    -TestAutopilotProfileExists $testAutopilotProfileExists `
    -TestESPProfileExists $testESPProfileExists `
    -TestPolicyExists $testPolicyExists `
    -TestAppExists $testAppExists `
    -GetTenantId $getTenantId `
    -UpdateOneDrivePolicyWithTenantId $updateOneDrivePolicyWithTenantId `
    -UpdateTenantIdInChildren $updateTenantIdInChildren `
    -EnableLAPSInEntraID $enableLAPSInEntraID `
    -RequestEdgeSyncConfiguration $requestEdgeSyncConfiguration

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}