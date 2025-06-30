function Get-AutopilotProfilesFromFolder {
    param (
        [string]$AutopilotFolderPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties
    )
    try {
        if (-not (Test-Path $AutopilotFolderPath)) {
            return @()
        }
        
        $configFiles = Get-ChildItem -Path $AutopilotFolderPath -Filter "*.json" -ErrorAction Stop
        $profiles = @()
        
        foreach ($file in $configFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent -replace '^\uFEFF', ''
                $profileData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $profileName = "VWC BL $baseName"
                
                $profile = @{
                    Name = $profileName
                    Description = "🛡️ Dit is een standaard VWC Baseline Autopilot profile"
                    Data = & $RemoveReadOnlyProperties -JsonObject $profileData
                    FileName = $file.Name
                    Type = "Autopilot"
                }
                
                $profiles += $profile
            }
            catch {
                Write-Warning "Failed to load Autopilot profile from $($file.Name): $($_.Exception.Message)"
                continue
            }
        }
        
        return $profiles
    }
    catch {
        Write-Error "Failed to load Autopilot profile files: $($_.Exception.Message)"
        return @()
    }
}

function New-AutopilotProfile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProfileData,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ValidateDeviceNameTemplate,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetAutopilotAssignments
    )
    
    try {
        Write-Host "Creating Autopilot profile: $ProfileName..." -ForegroundColor Yellow
        
        $cleanProfileData = & $RemoveReadOnlyProperties -JsonObject $ProfileData
        
        Write-Host "Enter a device name template for '$ProfileName' (e.g., DESKTOP-%SERIAL%, PC-%RAND:5%)" -ForegroundColor Yellow
        Write-Host "Requirements: 15 characters or less, letters/numbers/hyphens only, no spaces, not only numbers, supports %SERIAL% or %RAND:x%." -ForegroundColor Yellow
        
        $deviceNameTemplate = $null
        while (-not $deviceNameTemplate) {
            $inputTemplate = Read-Host "Device Name Template"
            if (& $ValidateDeviceNameTemplate -Template $inputTemplate) {
                $deviceNameTemplate = $inputTemplate
            }
            else {
                Write-Host "Invalid template. Please try again." -ForegroundColor Red
            }
        }
        
        $cleanProfileData.deviceNameTemplate = $deviceNameTemplate
        
        $autopilotProfileData = @{
            "@odata.type" = "#microsoft.graph.azureADWindowsAutopilotDeploymentProfile"
            displayName = $ProfileName
            description = "🛡️ Dit is een standaard VWC Baseline Autopilot profile"
        }
        
        $propertiesToCopy = @(
            'outOfBoxExperienceSettings',
            'enrollmentStatusScreenSettings',
            'extractHardwareHash',
            'deviceNameTemplate',
            'deviceType',
            'enableWhiteGlove',
            'roleScopeTagIds',
            'hybridAzureADJoinSkipConnectivityCheck'
        )
        
        foreach ($property in $propertiesToCopy) {
            if ($cleanProfileData.PSObject.Properties.Name -contains $property) {
                $autopilotProfileData[$property] = $cleanProfileData.$property
            }
        }
        
        if (-not $autopilotProfileData.ContainsKey('deviceType')) {
            $autopilotProfileData['deviceType'] = 'windowsPc'
        }
        
        $jsonBody = $autopilotProfileData | ConvertTo-Json -Depth 20
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created Autopilot profile: $ProfileName (ID: $($response.id))" -ForegroundColor Green
                
                $assignmentSuccess = & $SetAutopilotAssignments -ProfileId $response.id -ProfileName $ProfileName -AssignmentType $cleanProfileData.assignment
                
                if (!$assignmentSuccess) {
                    Write-Warning "Autopilot profile '$ProfileName' created but assignment failed"
                }
                
                return $response
            }
            else {
                Write-Error "Failed to create Autopilot profile: $ProfileName - No ID returned"
                return $null
            }
        }
        catch {
            Write-Error "Graph API request failed for Autopilot profile: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $null
        }
    }
    catch {
        Write-Error "Error creating Autopilot profile $ProfileName : $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-AutopilotProfilesFromFolder, New-AutopilotProfile