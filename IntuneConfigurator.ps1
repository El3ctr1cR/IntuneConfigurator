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
        
        if ($configFiles.Count -eq 0) {
            Write-Warning "No JSON configuration files found"
            return @()
        }
        
        $policies = @()
        
        foreach ($file in $configFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent -replace '^\uFEFF', ''
                $policyData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                
                $requiresEntraConfig = $baseName -like "*LAPS*"
                
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
                    FileName            = $file.Name
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
        
        if ($PolicyName -like "*OneDrive silently move Windows known folders*") {
            Write-Host "Detected OneDrive policy - retrieving Tenant ID..." -ForegroundColor Yellow
            $tenantId = Get-TenantId
            if (-not $tenantId) {
                Write-Error "Cannot proceed with OneDrive policy creation without Tenant ID"
                return $null
            }
            
            foreach ($setting in $policyBody.settings) {
                if ($setting.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance" -and 
                    $setting.settingDefinitionId -eq "device_vendor_msft_policy_config_onedrivengscv2.updates~policy~onedrivengsc_kfmoptinnowizard_kfmoptinnowizard_textbox") {
                    $setting.simpleSettingValue.value = $tenantId
                    Write-Host "Inserted Tenant ID ($tenantId) into OneDrive policy settings" -ForegroundColor Green
                    break
                }
            }
        }
        
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

function Test-PolicyExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq '$PolicyName'"
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
        
        $updateJson = $currentPolicy | ConvertTo-Json -Depth 10
        
        Invoke-MgGraphRequest -Method PUT -Uri $uri -Body $updateJson -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "✓ LAPS enabled in Entra ID successfully" -ForegroundColor Green
        return
    }
    catch {
        Write-Warning "Could not enable LAPS in Entra ID via API - please enable manually in the Entra ID portal: $($_.Exception.Message)"
        return
    }
}

function Show-PolicySelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailablePolicies
    )
    
    Write-Host "=== Configuration Policy Selection ===" -ForegroundColor Cyan
    Write-Host "Go through each policy and select Y (Yes) or N (No)" -ForegroundColor Yellow
    Write-Host ""
    
    $selectedPolicies = @()
    
    for ($i = 0; $i -lt $AvailablePolicies.Count; $i++) {
        $policy = $AvailablePolicies[$i]
        Write-Host "Policy: $($policy.Name)" -ForegroundColor White
        Write-Host "Description: $($policy.Description)" -ForegroundColor Gray
        Write-Host "Source: $($policy.FileName)" -ForegroundColor DarkGray
        
        do {
            Write-Host "Select this policy? (Y/N): " -ForegroundColor Yellow -NoNewline
            $selection = Read-Host
            $selection = $selection.Trim().ToUpper()
            
            if ($selection -eq 'Y') {
                $selectedPolicies += $policy
                Write-Host "✓ Added: $($policy.Name)" -ForegroundColor Green
                $validSelection = $true
            }
            elseif ($selection -eq 'N') {
                Write-Host "✗ Skipped: $($policy.Name)" -ForegroundColor Red
                $validSelection = $true
            }
            else {
                Write-Host "Invalid selection. Please enter Y or N." -ForegroundColor Red
                $validSelection = $false
            }
        } while (-not $validSelection)
        
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

Write-Host "Loaded $($availablePolicies.Count) configuration file(s)" -ForegroundColor Green
Write-Host ""

if (Connect-ToMSGraph) {
    Clear-Host
    
    $selectedPolicies = Show-PolicySelectionMenu -AvailablePolicies $availablePolicies
    
    if ($selectedPolicies.Count -eq 0) {
        Write-Host "No policies selected. Exiting..." -ForegroundColor Yellow
        Write-Host "Press any key to close..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
        
        $result = New-ConfigurationPolicyFromJson -PolicyData $policy.Data -PolicyName $policy.Name
        
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

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")