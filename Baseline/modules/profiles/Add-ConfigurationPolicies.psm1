function Get-ConfigurationPoliciesFromFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigFolderPath
    )
    
    try {
        if (-not (Test-Path $ConfigFolderPath)) {
            return @()
        }
        
        $configFiles = Get-ChildItem -Path $ConfigFolderPath -Filter "*.json" -ErrorAction Stop
        
        $policies = @()
        
        $manualPolicy = @{
            Name                = "VWC BL - Restrict local administrator"
            Description         = "🛡️ Dit is een standaard VWC Baseline policy"
            Data                = @{
                description       = "🛡️ Dit is een standaard VWC Baseline policy"
                isManualOmaUri    = $true
                omaUri            = "./Device/Vendor/MSFT/Policy/Config/LocalUsersAndGroups/Configure"
                dataType          = "String"
                value             = @"
<GroupConfiguration>
    <accessgroup desc="Administrators">
        <group action="R" />
        <add member="Administrator"/>
    </accessgroup>
</GroupConfiguration>
"@
                assignment        = "devices"
            }
            RequiresEntraConfig = $false
            RequiresEdgeSync    = $false
            RequiresTenantId    = $false
            FileName            = "Manual OMA-URI Policy"
            IsManual            = $true
            Type                = "Config"
        }
        
        $policies += $manualPolicy
        
        foreach ($file in $configFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent -replace '^\uFEFF', ''
                $policyData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                
                $requiresEntraConfig = $baseName -like "*LAPS*"
                $requiresEdgeSync = $baseName -like "*Edge force sync*"
                $requiresTenantId = $baseName -like "*OneDrive silently move Windows known folders*"
                
                $policy = @{
                    Name                = "VWC BL - $baseName"
                    Description         = "🛡️ Dit is een standaard VWC Baseline policy"
                    Data                = @{
                        description       = $policyData.description
                        platforms         = $policyData.platforms
                        technologies      = $policyData.technologies
                        templateReference = $policyData.templateReference
                        settings          = $policyData.settings
                        assignment        = $policyData.assignment
                    }
                    RequiresEntraConfig = $requiresEntraConfig
                    RequiresEdgeSync    = $requiresEdgeSync
                    RequiresTenantId    = $requiresTenantId
                    FileName            = $file.Name
                    IsManual            = $false
                    Type                = "Config"
                }
                
                $policies += $policy
            }
            catch {
                Write-Warning "Failed to load configuration from $($file.Name): $($_.Exception.Message)"
                continue
            }
        }
        
        return $policies
    }
    catch {
        Write-Error "Failed to load configuration files: $($_.Exception.Message)"
        return @()
    }
}

function New-ConfigurationPolicyFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetPolicyAssignments
    )
    
    try {
        Write-Host "Creating configuration policy: $PolicyName..." -ForegroundColor Yellow
        
        $isEndpointSecurity = $false
        if ($PolicyData.templateReference -and 
            $PolicyData.templateReference.templateFamily -ne "none" -and 
            $PolicyData.templateReference.templateId -ne "") {
            $isEndpointSecurity = $true
        }
        
        $policyBody = $PolicyData | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        
        $policyBody = @{
            name         = $PolicyName
            description  = "🛡️ Dit is een standaard VWC Baseline policy"
            platforms    = $PolicyData.platforms
            technologies = $PolicyData.technologies
            settings     = $policyBody.settings
        }
        
        if ($isEndpointSecurity) {
            $policyBody.templateReference = $PolicyData.templateReference
        }
        
        $jsonBody = $policyBody | ConvertTo-Json -Depth 20
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created policy: $PolicyName (ID: $($response.id))" -ForegroundColor Green
                
                $assignmentSuccess = & $SetPolicyAssignments -PolicyId $response.id -PolicyName $PolicyName -AssignmentType $PolicyData.assignment
                
                if (!$assignmentSuccess) {
                    Write-Warning "Policy '$PolicyName' created but assignment failed"
                }
                
                return $response
            }
            else {
                Write-Error "Failed to create policy: $PolicyName - No ID returned"
                return $null
            }
        }
        catch {
            Write-Error "Graph API request failed: $($_.Exception.Message)"
            throw
        }
    }
    catch {
        Write-Error "Error creating policy $PolicyName : $($_.Exception.Message)"
        return $null
    }
}

function New-ManualOmaUriPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetLegacyPolicyAssignments
    )
    
    try {
        Write-Host "Creating manual OMA-URI policy: $PolicyName..." -ForegroundColor Yellow
        
        $policyBody = @{
            name = $PolicyName
            description = "🛡️ Dit is een standaard VWC Baseline policy"
            platforms = "windows10"
            technologies = "mdm"
            settings = @(
                @{
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
                    settingInstance = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance"
                        settingDefinitionId = "custom_" + [guid]::NewGuid().ToString()
                        simpleSettingValue = @{
                            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationStringSettingValue"
                            value = $PolicyData.value
                        }
                    }
                }
            )
        }
        
        $legacyPolicyBody = @{
            "@odata.type" = "#microsoft.graph.windows10CustomConfiguration"
            displayName = $PolicyName
            description = "🛡️ Dit is een standaard VWC Baseline policy"
            omaSettings = @(
                @{
                    "@odata.type" = "#microsoft.graph.omaSettingString"
                    displayName = "Restrict Local Administrator"
                    description = "Restricts local administrator access"
                    omaUri = $PolicyData.omaUri
                    value = $PolicyData.value
                }
            )
        }
        
        $jsonBody = $legacyPolicyBody | ConvertTo-Json -Depth 20
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created OMA-URI policy: $PolicyName (ID: $($response.id))" -ForegroundColor Green
                
                $assignmentSuccess = & $SetLegacyPolicyAssignments -PolicyId $response.id -PolicyName $PolicyName -AssignmentType $PolicyData.assignment
                
                if (!$assignmentSuccess) {
                    Write-Warning "Policy '$PolicyName' created but assignment failed"
                }
                
                return $response
            }
            else {
                Write-Error "Failed to create OMA-URI policy: $PolicyName - No ID returned"
                return $null
            }
        }
        catch {
            Write-Error "Graph API request failed for OMA-URI policy: $($_.Exception.Message)"
            return $null
        }
    }
    catch {
        Write-Error "Error creating OMA-URI policy $PolicyName : $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-ConfigurationPoliciesFromFolder, New-ConfigurationPolicyFromJson, New-ManualOmaUriPolicy