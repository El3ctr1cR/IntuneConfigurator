# modules/core/Connect-MSGraph.psm1
# Duo Security deployer - Graph connection with all required scopes

$GraphScopes = @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementScripts.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Group.ReadWrite.All",
    "Device.ReadWrite.All",
    "Directory.ReadWrite.All"
)

function Connect-ToMSGraph {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes $GraphScopes -NoWelcome -ContextScope Process -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Connect-ToMSGraph