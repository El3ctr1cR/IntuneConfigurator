$Modules = @(
    @{Name = "Microsoft.Graph.Authentication"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.DeviceManagement"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Identity.SignIns"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Groups"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Beta.Identity.SignIns"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Users"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Beta.DeviceManagement"; MinVersion = "1.0.0" }
)
$GraphScopes = @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All",
    "Group.ReadWrite.All",
    "User.ReadWrite.All",
    "Policy.ReadWrite.AuthenticationMethod",
    "Policy.ReadWrite.DeviceConfiguration",
    "DeviceManagementManagedDevices.ReadWrite.All",
    "Directory.ReadWrite.All"
)

$ConfigFolderPath = Join-Path $PSScriptRoot "json"

foreach ($module in $Modules) {
    if (!(Get-Module -ListAvailable -Name $module.Name | Where-Object { [version]$_.Version -ge [version]$module.MinVersion })) {
        try {
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -AllowClobber -ErrorAction Stop
            Write-Host "Successfully installed $($module.Name) version $(${module}.MinVersion) or higher" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install $($module.Name): $($_.Exception.Message)"
        }
    }
}

foreach ($module in $Modules) {
    try {
        Import-Module -Name $module.Name -MinimumVersion $module.MinVersion -ErrorAction Stop
        Write-Host "Successfully imported $($module.Name)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import $($module.Name): $($_.Exception.Message)"
    }
}

function Initialize-ConfigFolder {
    try {
        if (-not (Test-Path $ConfigFolderPath)) {
            Write-Error "The 'json' folder does not exist in the script directory: $ConfigFolderPath"
            return $false
        }
        
        $jsonFiles = Get-ChildItem -Path $ConfigFolderPath -Filter "*.json" -ErrorAction Stop
        if ($jsonFiles.Count -eq 0) {
            Write-Error "No JSON files found in the 'json' folder: $ConfigFolderPath"
            return $false
        }
        
        Write-Host "Found $($jsonFiles.Count) JSON file(s) in the 'json' folder" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to initialize configuration folder: $($_.Exception.Message)"
        return $false
    }
}

function Get-ConfigurationPoliciesFromFolder {
    try {
        $configFiles = Get-ChildItem -Path $ConfigFolderPath -Filter "*.json" -ErrorAction Stop
        
        $policies = @()
        
        $manualPolicy = @{
            Name                = "VWC BL - Restrict local administrator"
            Description         = "🛡️ Dit is een standaard VWC Baseline policy"
            Data                = @{
                description       = "Restricts local administrator access using OMA-URI"
                isManualOmaUri    = $true
                omaUri           = "./Device/Vendor/MSFT/Policy/Config/LocalUsersAndGroups/Configure"
                dataType         = "String"
                value            = @"
<GroupConfiguration>
    <accessgroup desc="Administrators">
        <group action="R" />
        <add member="Administrator"/>
    </accessgroup>
</GroupConfiguration>
"@
            }
            RequiresEntraConfig = $false
            RequiresEdgeSync    = $false
            RequiresTenantId    = $false
            FileName            = "Manual OMA-URI Policy"
            IsManual            = $true
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
                    }
                    RequiresEntraConfig = $requiresEntraConfig
                    RequiresEdgeSync    = $requiresEdgeSync
                    RequiresTenantId    = $requiresTenantId
                    FileName            = $file.Name
                    IsManual            = $false
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

function Connect-ToMSGraph {
    try {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes $GraphScopes -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

function Get-TenantId {
    try {
        $uri = "https://graph.microsoft.com/v1.0/organization"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $tenantId = $response.value[0].id
        if ($tenantId) {
            Write-Host "Retrieved Tenant ID: $tenantId" -ForegroundColor Green
            return $tenantId
        }
        else {
            Write-Error "Failed to retrieve Tenant ID: No organization data returned"
            return $null
        }
    }
    catch {
        Write-Error "Failed to retrieve Tenant ID: $($_.Exception.Message)"
        return $null
    }
}

function Update-OneDrivePolicyWithTenantId {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    try {
        Write-Host "Updating OneDrive policy with Tenant ID ($TenantId)..." -ForegroundColor Yellow
        
        foreach ($setting in $PolicyData.settings) {
            if ($setting.settingInstance -and 
                $setting.settingInstance.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance") {
                
                $updated = Update-TenantIdInChildren -Children $setting.settingInstance.choiceSettingValue.children -TenantId $TenantId
                if ($updated) {
                    Write-Host "✓ Successfully updated Tenant ID in OneDrive policy settings" -ForegroundColor Green
                    return $true
                }
            }
        }
        
        Write-Warning "Could not find tenant ID setting in OneDrive policy"
        return $false
    }
    catch {
        Write-Error "Failed to update OneDrive policy with Tenant ID: $($_.Exception.Message)"
        return $false
    }
}

function Update-TenantIdInChildren {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Children,
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    foreach ($child in $Children) {
        if ($child.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance" -and 
            $child.settingDefinitionId -eq "device_vendor_msft_policy_config_onedrivengscv2.updates~policy~onedrivengsc_kfmoptinnowizard_kfmoptinnowizard_textbox") {
            
            $child.simpleSettingValue.value = $TenantId
            Write-Host "✓ Found and updated tenant ID setting" -ForegroundColor Green
            return $true
        }
        
        if ($child.choiceSettingValue -and $child.choiceSettingValue.children) {
            $updated = Update-TenantIdInChildren -Children $child.choiceSettingValue.children -TenantId $TenantId
            if ($updated) {
                return $true
            }
        }
    }
    
    return $false
}

function New-ManualOmaUriPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Creating manual OMA-URI policy: $PolicyName..." -ForegroundColor Yellow
        
        $policyBody = @{
            name = $PolicyName
            description = $PolicyData.description
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
            description = $PolicyData.description
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
                
                $assignmentSuccess = Set-LegacyPolicyAssignments -PolicyId $response.id -PolicyName $PolicyName
                
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

function New-ConfigurationPolicyFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
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
            description  = $PolicyData.description
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
                
                $assignmentSuccess = Set-PolicyAssignments -PolicyId $response.id -PolicyName $PolicyName
                
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
            throw "Graph API request failed: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Error "Error creating policy $PolicyName : $($_.Exception.Message)"
        return $null
    }
}

function Set-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Assigning policy '$PolicyName' to All Devices and All Users..." -ForegroundColor Yellow
        
        $assignmentBody = @{
            assignments = @(
                @{
                    id     = ""
                    target = @{
                        "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                    }
                },
                @{
                    id     = ""
                    target = @{
                        "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned policy '$PolicyName' to All Devices and All Users" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign policy '$PolicyName': $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign policy '$PolicyName': $($_.Exception.Message)"
        return $false
    }
}

function Set-LegacyPolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Assigning legacy policy '$PolicyName' to All Devices..." -ForegroundColor Yellow
        
        $assignmentBody = @{
            deviceConfigurationGroupAssignments = @(
                @{
                    targetGroupId = "00000000-0000-0000-0000-000000000000"
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('$PolicyId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned legacy policy '$PolicyName' to All Devices" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign legacy policy '$PolicyName': $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign legacy policy '$PolicyName': $($_.Exception.Message)"
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

function Enable-LAPSInEntraID {
    try {
        Write-Host "Enabling LAPS in Entra ID..." -ForegroundColor Yellow
        
        $uri = "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy"
        
        try {
            $currentPolicy = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
            Write-Host "Retrieved device registration policy" -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Device registration policy not found. Please ensure the policy exists or create it manually in the Entra ID portal."
            throw "Failed to retrieve device registration policy: $($_.Exception.Message)"
        }
        
        if ($currentPolicy.localAdminPassword.isEnabled -eq $true) {
            Write-Host "✓ LAPS is already enabled in Entra ID" -ForegroundColor Green
            return
        }
        
        $currentPolicy.localAdminPassword.isEnabled = $true
        
        $updateson = $currentPolicy | ConvertTo-Json -Depth 10
        
        Invoke-MgGraphRequest -Method PUT -Uri $uri -Body $updateJson -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "✓ LAPS enabled in Entra ID successfully" -ForegroundColor Green
        return
    }
    catch {
        Write-Warning "Could not enable LAPS in Entra ID via API - please enable manually in the Entra ID portal: $($_.Exception.Message)"
        return
    }
}

function Request-EdgeSyncConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    Write-Host ""
    Write-Host "⚠️  MANUAL CONFIGURATION REQUIRED FOR: $PolicyName" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Before continuing, you need to enable Enterprise State Roaming:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Go to: https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/RoamingSettings/menuId/Devices?Microsoft_AAD_IAM_legacyAADRedirect=true" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Enable 'Users may sync settings and app data across devices' in Enterprise State Roaming" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Press any key here to continue after completing the above steps..." -ForegroundColor Yellow
    
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
    Write-Host "✓ Continuing with policy creation..." -ForegroundColor Green
    Write-Host ""
}

function Show-PolicySelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailablePolicies
    )
    
    Write-Host "=== Available Configuration Policies ===" -ForegroundColor Cyan
    Write-Host ""
    
    $selectedPolicies = @()
    
    foreach ($policy in $AvailablePolicies) {
        $policyType = if ($policy.IsManual) { " [OMA-URI]" } else { "" }
        $specialReqs = @()
        if ($policy.RequiresEntraConfig) { $specialReqs += "LAPS Config" }
        if ($policy.RequiresEdgeSync) { $specialReqs += "Edge Sync Config" }
        if ($policy.RequiresTenantId) { $specialReqs += "Tenant ID" }
        $reqText = if ($specialReqs.Count -gt 0) { " [Requires: $($specialReqs -join ', ')]" } else { "" }
        
        Write-Host "Policy: $($policy.Name)$policyType$reqText" -ForegroundColor White
        Write-Host "Description: $($policy.Description)" -ForegroundColor Gray
        Write-Host "Source: $($policy.FileName)" -ForegroundColor DarkGray
        Write-Host ""
        
        while ($true) {
            Write-Host "Do you want to select this policy? (Y/N): " -ForegroundColor Yellow -NoNewline
            $selection = Read-Host
            
            if ($selection -match '^[Yy]$') {
                $selectedPolicies += $policy
                Write-Host "Selected: $($policy.Name)" -ForegroundColor Green
                break
            }
            elseif ($selection -match '^[Nn]$') {
                Write-Host "Skipped: $($policy.Name)" -ForegroundColor Yellow
                break
            }
            else {
                Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
            }
        }
        Write-Host ""
    }
    
    return $selectedPolicies
}

Write-Host ""
Write-Host "=== Intune Configuration Profile Creation Script ===" -ForegroundColor Cyan
Write-Host "This script will create all the baseline configuration profiles for Intune" -ForegroundColor Cyan
Write-Host ""

if (-not (Initialize-ConfigFolder)) {
    Write-Error "Cannot proceed without configuration files"
    return
}

Write-Host ""

$availablePolicies = Get-ConfigurationPoliciesFromFolder

if ($availablePolicies.Count -eq 0) {
    Write-Host "No valid configuration files were found or loaded." -ForegroundColor Yellow
    return
}

Write-Host "Loaded $($availablePolicies.Count) configuration file(s) (including manual policies)" -ForegroundColor Green
Write-Host ""

if (Connect-ToMSGraph) {
    Write-Host ""
    
    $selectedPolicies = Show-PolicySelectionMenu -AvailablePolicies $availablePolicies
    
    if ($selectedPolicies.Count -eq 0) {
        Write-Host "No policies selected. Exiting..." -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "=== Selected Policies ===" -ForegroundColor Cyan
    foreach ($policy in $selectedPolicies) {
        Write-Host "- $($policy.Name)" -ForegroundColor Green
    }
    Write-Host ""
    
    Write-Host "Press any key to continue with policy creation..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
    
    $tenantId = $null
    $needsTenantId = $selectedPolicies | Where-Object { $_.RequiresTenantId }
    if ($needsTenantId) {
        $tenantId = Get-TenantId
        if (-not $tenantId) {
            Write-Error "Cannot proceed with OneDrive policies without Tenant ID"
            return
        }
    }
    
    foreach ($policy in $selectedPolicies) {
        Write-Host "Processing policy: $($policy.Name)" -ForegroundColor Yellow
        
        if (Test-PolicyExists -PolicyName $policy.Name) {
            Write-Warning "Policy '$($policy.Name)' already exists. Skipping creation."
            continue
        }
        
        if ($policy.RequiresEntraConfig -and $policy.Name -like "*LAPS*") {
            Write-Host "LAPS policy selected - enabling LAPS in Entra ID first..." -ForegroundColor Yellow
            Enable-LAPSInEntraID
        }
        
        if ($policy.RequiresEdgeSync) {
            Request-EdgeSyncConfiguration -PolicyName $policy.Name
        }
        
        if ($policy.RequiresTenantId -and $tenantId) {
            Write-Host "OneDrive policy selected - updating with Tenant ID..." -ForegroundColor Yellow
            $updated = Update-OneDrivePolicyWithTenantId -PolicyData $policy.Data -TenantId $tenantId
            if (-not $updated) {
                Write-Warning "Failed to update OneDrive policy with Tenant ID. Proceeding anyway..."
            }
        }
        
        $result = $null
        if ($policy.IsManual) {
            $result = New-ManualOmaUriPolicy -PolicyData $policy.Data -PolicyName $policy.Name
        }
        else {
            $result = New-ConfigurationPolicyFromJson -PolicyData $policy.Data -PolicyName $policy.Name
        }
        
        if (!$result) {
            Write-Error "✗ Failed to create policy: $($policy.Name)"
        }
        
        Write-Host ""
    }
    
    Write-Host "=== Script Execution Completed ===" -ForegroundColor Cyan
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "- Selected policies: $($selectedPolicies.Count)" -ForegroundColor Gray
    Write-Host "- Check the Intune portal to verify policy creation and assignment" -ForegroundColor Gray
}
else {
    Write-Error "Cannot proceed without Microsoft Graph connection"
}

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
}