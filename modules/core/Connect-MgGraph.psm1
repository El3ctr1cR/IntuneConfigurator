$GraphScopes = @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All",
    "Group.ReadWrite.All",
    "User.ReadWrite.All",
    "Policy.ReadWrite.AuthenticationMethod",
    "Policy.ReadWrite.DeviceConfiguration",
    "DeviceManagementManagedDevices.ReadWrite.All",
    "Directory.ReadWrite.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Device.ReadWrite.All",
    "WindowsUpdates.ReadWrite.All"
)

function Connect-ToMSGraph {
    try {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
        
        $context = Get-MgContext
        if ($context -and $context.Scopes -and ($GraphScopes | ForEach-Object { $_ -in $context.Scopes }) -eq $true) {
            Write-Host "Already connected to Microsoft Graph with required scopes" -ForegroundColor Green
            return $true
        }
        
        Connect-MgGraph -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Connect-ToMSGraph