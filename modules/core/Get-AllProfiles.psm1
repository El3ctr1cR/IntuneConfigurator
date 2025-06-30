function Get-AllProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$AutopilotFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$ESPFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$AppsFolderPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties
    )
    
    $result = @{
        ConfigPolicies    = @()
        AutopilotProfiles = @()
        ESPProfiles       = @()
        Apps              = @()
        TotalItems        = 0
    }
    
    # Load configuration policies
    $result.ConfigPolicies = Get-ConfigurationPoliciesFromFolder -ConfigFolderPath $ConfigFolderPath
    
    # Load Autopilot profiles
    $result.AutopilotProfiles = Get-AutopilotProfilesFromFolder -AutopilotFolderPath $AutopilotFolderPath -RemoveReadOnlyProperties $RemoveReadOnlyProperties
    
    # Load ESP profiles
    $result.ESPProfiles = Get-ESPProfilesFromFolder -ESPFolderPath $ESPFolderPath -RemoveReadOnlyProperties $RemoveReadOnlyProperties
    
    # Load applications
    $result.Apps = Get-AppConfigurationsFromFolder -AppsFolderPath $AppsFolderPath -RemoveReadOnlyProperties $RemoveReadOnlyProperties
    
    # Calculate total items
    $result.TotalItems = $result.ConfigPolicies.Count + $result.AutopilotProfiles.Count + $result.ESPProfiles.Count + $result.Apps.Count
    
    return $result
}

Export-ModuleMember -Function Get-AllProfiles