function Get-ConfigurationPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )
    
    $jsonPath = Join-Path $RootPath "json"
    $paths = @{
        JsonPath            = $jsonPath
        ConfigFolderPath    = Join-Path $jsonPath "configuration"
        AutopilotFolderPath = Join-Path $jsonPath "autopilot"
        ESPFolderPath       = Join-Path $jsonPath "esp"
        AppsFolderPath      = Join-Path $jsonPath "apps"
    }
    
    return $paths
}

Export-ModuleMember -Function Get-ConfigurationPaths