function Test-AutopilotProfileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$ProfileName'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        return ($response.value.Count -gt 0)
    }
    catch {
        Write-Warning "Could not check if Autopilot profile exists: $($_.Exception.Message)"
        return $false
    }
}

function Test-ESPProfileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=displayName eq '$ProfileName'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        return ($response.value.Count -gt 0)
    }
    catch {
        Write-Warning "Could not check if ESP profile exists: $($_.Exception.Message)"
        return $false
    }
}

function Test-PolicyExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq '$PolicyName'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        if ($response.value.Count -gt 0) {
            return $true
        }
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=displayName eq '$PolicyName'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        return ($response.value.Count -gt 0)
    }
    catch {
        Write-Warning "Could not check if policy exists: $($_.Exception.Message)"
        return $false
    }
}

function Test-AppExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=displayName eq '$AppName'"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        
        return ($response.value.Count -gt 0)
    }
    catch {
        Write-Warning "Could not check if application exists: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Test-AutopilotProfileExists, Test-ESPProfileExists, Test-PolicyExists, Test-AppExists