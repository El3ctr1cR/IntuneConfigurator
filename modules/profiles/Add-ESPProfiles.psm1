function Get-ESPProfilesFromFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ESPFolderPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties
    )
    
    try {
        if (-not (Test-Path $ESPFolderPath)) {
            return @()
        }
        
        $configFiles = Get-ChildItem -Path $ESPFolderPath -Filter "*.json" -ErrorAction Stop
        $profiles = @()
        
        foreach ($file in $configFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent -replace '^\uFEFF', ''
                $profileData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $profileName = "VWC BL - $baseName"
                
                $profile = @{
                    Name = $profileName
                    Description = "🛡️ Dit is een standaard VWC Baseline ESP profile"
                    Data = & $RemoveReadOnlyProperties -JsonObject $profileData
                    FileName = $file.Name
                    Type = "ESP"
                }
                
                $profiles += $profile
            }
            catch {
                Write-Warning "Failed to load ESP profile from $($file.Name): $($_.Exception.Message)"
                continue
            }
        }
        
        return $profiles
    }
    catch {
        Write-Error "Failed to load ESP profile files: $($_.Exception.Message)"
        return @()
    }
}

function New-ESPProfile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProfileData,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetESPAssignments
    )
    
    try {
        Write-Host "Creating ESP profile: $ProfileName..." -ForegroundColor Yellow
        
        $cleanProfileData = & $RemoveReadOnlyProperties -JsonObject $ProfileData
        
        $espProfileData = @{
            "@odata.type" = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
            displayName = $ProfileName
            description = "🛡️ Dit is een standaard VWC Baseline ESP profile"
        }
        
        $propertiesToCopy = @(
            'showInstallationProgress',
            'blockDeviceSetupRetryByUser',
            'allowDeviceResetOnInstallFailure',
            'allowLogCollectionOnInstallFailure',
            'customErrorMessage',
            'installProgressTimeoutInMinutes',
            'allowDeviceUseOnInstallFailure',
            'selectedMobileAppIds',
            'trackInstallProgressForAutopilotOnly',
            'disableUserStatusTrackingAfterFirstUser',
            'priority',
            'roleScopeTagIds'
        )
        
        foreach ($property in $propertiesToCopy) {
            if ($cleanProfileData.PSObject.Properties.Name -contains $property) {
                $espProfileData[$property] = $cleanProfileData.$property
            }
        }
        
        if (-not $espProfileData.ContainsKey('showInstallationProgress')) {
            $espProfileData['showInstallationProgress'] = $true
        }
        if (-not $espProfileData.ContainsKey('blockDeviceSetupRetryByUser')) {
            $espProfileData['blockDeviceSetupRetryByUser'] = $true
        }
        if (-not $espProfileData.ContainsKey('allowDeviceResetOnInstallFailure')) {
            $espProfileData['allowDeviceResetOnInstallFailure'] = $true
        }
        if (-not $espProfileData.ContainsKey('allowLogCollectionOnInstallFailure')) {
            $espProfileData['allowLogCollectionOnInstallFailure'] = $true
        }
        if (-not $espProfileData.ContainsKey('installProgressTimeoutInMinutes')) {
            $espProfileData['installProgressTimeoutInMinutes'] = 60
        }
        if (-not $espProfileData.ContainsKey('allowDeviceUseOnInstallFailure')) {
            $espProfileData['allowDeviceUseOnInstallFailure'] = $true
        }
        
        $jsonBody = $espProfileData | ConvertTo-Json -Depth 20
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created ESP profile: $ProfileName (ID: $($response.id))" -ForegroundColor Green
                
                $assignmentSuccess = & $SetESPAssignments -ProfileId $response.id -ProfileName $ProfileName -AssignmentType $cleanProfileData.assignment
                
                if (!$assignmentSuccess) {
                    Write-Warning "ESP profile '$ProfileName' created but assignment failed"
                }
                
                return $response
            }
            else {
                Write-Error "Failed to create ESP profile: $ProfileName - No ID returned"
                return $null
            }
        }
        catch {
            Write-Error "Graph API request failed for ESP profile: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $null
        }
    }
    catch {
        Write-Error "Error creating ESP profile $ProfileName : $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-ESPProfilesFromFolder, New-ESPProfile