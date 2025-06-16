# Define required modules and scopes
$Modules = @(
    @{Name = "Microsoft.Graph.Authentication"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.DeviceManagement"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.Identity.SignIns"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.Groups"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.Beta.Identity.SignIns"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.Users"; MinVersion = "1.0.0"},
    @{Name = "Microsoft.Graph.Beta.DeviceManagement"; MinVersion = "1.0.0"}
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

# Configuration folder path
$ConfigFolderPath = Join-Path $env:APPDATA "IntuneConfigurator"

# Install required modules if not already installed
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

# Import required modules
foreach ($module in $Modules) {
    try {
        Import-Module -Name $module.Name -MinimumVersion $module.MinVersion -ErrorAction Stop
        Write-Host "Successfully imported $($module.Name)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import $($module.Name): $($_.Exception.Message)"
    }
}

# Function to ensure configuration folder exists
function Initialize-ConfigFolder {
    try {
        if (-not (Test-Path $ConfigFolderPath)) {
            New-Item -ItemType Directory -Path $ConfigFolderPath -Force | Out-Null
            Write-Host "Created configuration folder: $ConfigFolderPath" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Error "Failed to create configuration folder: $($_.Exception.Message)"
        return $false
    }
}

# Function to load JSON configuration files from folder
function Get-ConfigurationPoliciesFromFolder {
    try {
        $configFiles = Get-ChildItem -Path $ConfigFolderPath -Filter "*.json" -ErrorAction Stop
        
        if ($configFiles.Count -eq 0) {
            Write-Warning "No JSON configuration files found in: $ConfigFolderPath"
            Write-Host "Please place your Intune configuration JSON files in this folder and run the script again." -ForegroundColor Yellow
            return @()
        }
        
        $policies = @()
        
        foreach ($file in $configFiles) {
            try {
                Write-Host "Loading configuration from: $($file.Name)" -ForegroundColor Cyan
                
                # Read and parse JSON file
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $policyData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                # Extract policy name from filename (remove .json extension)
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                
                # Determine if this policy requires Entra config (currently only LAPS)
                $requiresEntraConfig = $baseName -like "*LAPS*"
                
                # Create policy object
                $policy = @{
                    Name = "VWC BL - $baseName"
                    Description = "🛡️ Dit is een standaard VWC Baseline policy"
                    Data = @{
                        description = $policyData.description
                        platforms = $policyData.platforms
                        technologies = $policyData.technologies
                        templateReference = $policyData.templateReference
                        settings = $policyData.settings
                    }
                    RequiresEntraConfig = $requiresEntraConfig
                    FileName = $file.Name
                }
                
                $policies += $policy
                Write-Host "✓ Loaded policy: $($policy.Name)" -ForegroundColor Green
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

# Function to create sample configuration files
function New-SampleConfigurationFiles {
    param(
        [switch]$Force
    )
    
    try {
        $sampleConfigs = @{
            "Edge-Force-SignIn.json" = @{
                description = "Forces users to sign into Microsoft Edge"
                platforms = "windows10"
                technologies = "mdm"
                templateReference = @{
                    templateId = ""
                    templateFamily = "none"
                    templateDisplayName = $null
                    templateDisplayVersion = $null
                }
                settings = @(
                    @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
                        settingInstance = @{
                            "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                            settingDefinitionId = "device_vendor_msft_policy_config_microsoft_edge~policy~microsoft_edge_browsersignin"
                            settingInstanceTemplateReference = $null
                            choiceSettingValue = @{
                                settingValueTemplateReference = $null
                                value = "device_vendor_msft_policy_config_microsoft_edge~policy~microsoft_edge_browsersignin_1"
                                children = @(
                                    @{
                                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                                        settingDefinitionId = "device_vendor_msft_policy_config_microsoft_edge~policy~microsoft_edge_browsersignin_browsersignin"
                                        settingInstanceTemplateReference = $null
                                        choiceSettingValue = @{
                                            settingValueTemplateReference = $null
                                            value = "device_vendor_msft_policy_config_microsoft_edge~policy~microsoft_edge_browsersignin_browsersignin_2"
                                            children = @()
                                        }
                                    }
                                )
                            }
                        }
                    }
                )
            }
        }
        
        $created = 0
        foreach ($fileName in $sampleConfigs.Keys) {
            $filePath = Join-Path $ConfigFolderPath $fileName
            
            if ((Test-Path $filePath) -and -not $Force) {
                Write-Host "Sample file already exists: $fileName (use -Force to overwrite)" -ForegroundColor Yellow
                continue
            }
            
            $sampleConfigs[$fileName] | ConvertTo-Json -Depth 20 | Out-File -FilePath $filePath -Encoding UTF8
            Write-Host "Created sample configuration: $fileName" -ForegroundColor Green
            $created++
        }
        
        if ($created -gt 0) {
            Write-Host "`nCreated $created sample configuration file(s) in: $ConfigFolderPath" -ForegroundColor Cyan
            Write-Host "You can use these as templates for your own configurations." -ForegroundColor Gray
        }
        
        return $created
    }
    catch {
        Write-Error "Failed to create sample configuration files: $($_.Exception.Message)"
        return 0
    }
}

# Function to connect to Microsoft Graph
function Connect-ToMSGraph {
    try {
        # Connect with required scopes
        Connect-MgGraph -Scopes $GraphScopes -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph with specified scopes" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        return $false
    }
}

# Function to create configuration policy from JSON
function New-ConfigurationPolicyFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Creating configuration policy: $PolicyName" -ForegroundColor Yellow
        
        # Check if this is an endpoint security policy based on templateReference
        $isEndpointSecurity = $false
        if ($PolicyData.templateReference -and 
            $PolicyData.templateReference.templateFamily -ne "none" -and 
            $PolicyData.templateReference.templateId -ne "") {
            $isEndpointSecurity = $true
            Write-Host "Detected Endpoint Security policy type: $($PolicyData.templateReference.templateFamily)" -ForegroundColor Cyan
        }
        
        # Create the policy body - include templateReference if it exists
        $policyBody = @{
            name = $PolicyName
            description = $PolicyData.description
            platforms = $PolicyData.platforms
            technologies = $PolicyData.technologies
            settings = $PolicyData.settings
        }
        
        # Add templateReference if this is an endpoint security policy
        if ($isEndpointSecurity) {
            $policyBody.templateReference = $PolicyData.templateReference
        }
        
        # Convert to JSON for the API call
        $jsonBody = $policyBody | ConvertTo-Json -Depth 20
        
        # Use the same endpoint - Graph API handles different policy types via templateReference
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json"
        
        if ($response.id) {
            Write-Host "Successfully created policy: $PolicyName (ID: $($response.id))" -ForegroundColor Green
            return $response
        }
        else {
            Write-Error "Failed to create policy: $PolicyName"
            return $null
        }
    }
    catch {
        Write-Error "Error creating policy $PolicyName : $($_.Exception.Message)"
        return $null
    }
}

# Function to check if policy already exists
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

# Function to enable LAPS in Entra ID
function Enable-LAPSInEntraID {
    try {
        Write-Host "Enabling LAPS in Entra ID..." -ForegroundColor Yellow
        
        # Define the URI for device registration policy
        $uri = "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy"
        
        # Attempt to get current device registration policy
        try {
            $currentPolicy = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
            Write-Host "Retrieved device registration policy" -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Device registration policy not found. Please ensure the policy exists or create it manually in the Entra ID portal."
            throw "Failed to retrieve device registration policy: $($_.Exception.Message)"
        }
        
        # Check if LAPS is already enabled
        if ($currentPolicy.localAdminPassword.isEnabled -eq $true) {
            Write-Host "✓ LAPS is already enabled in Entra ID" -ForegroundColor Green
            return
        }
        
        # Modify the existing policy to enable LAPS
        $currentPolicy.localAdminPassword.isEnabled = $true
        
        # Convert the updated policy to JSON
        $updateJson = $currentPolicy | ConvertTo-Json -Depth 10
        
        # Update the policy using PUT
        Invoke-MgGraphRequest -Method PUT -Uri $uri -Body $updateJson -ContentType "application/json" -ErrorAction Stop
        
        Write-Host "✓ LAPS enabled in Entra ID successfully" -ForegroundColor Green
        return
    }
    catch {
        Write-Warning "Could not enable LAPS in Entra ID via API - please enable manually in the Entra ID portal: $($_.Exception.Message)"
        return
    }
}

# Function to display menu and get user selections
function Show-PolicySelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailablePolicies
    )
    
    Write-Host "=== Available Configuration Policies ===" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $AvailablePolicies.Count; $i++) {
        $policy = $AvailablePolicies[$i]
        Write-Host "[$($i + 1)] $($policy.Name)" -ForegroundColor White
        Write-Host "    Description: $($policy.Description)" -ForegroundColor Gray
        Write-Host "    Source: $($policy.FileName)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    Write-Host "[A] Select All" -ForegroundColor Green
    Write-Host "[N] Select None" -ForegroundColor Red
    Write-Host ""
    
    $selectedPolicies = @()
    
    while ($true) {
        Write-Host "Enter your selection (number, A for all, N for none, or Q to finish): " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        
        if ($selection -eq 'Q' -or $selection -eq 'q') {
            break
        }
        elseif ($selection -eq 'A' -or $selection -eq 'a') {
            $selectedPolicies = $AvailablePolicies
            Write-Host "All policies selected" -ForegroundColor Green
            break
        }
        elseif ($selection -eq 'N' -or $selection -eq 'n') {
            $selectedPolicies = @()
            Write-Host "No policies selected" -ForegroundColor Red
            break
        }
        elseif ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $AvailablePolicies.Count) {
            $selectedPolicy = $AvailablePolicies[[int]$selection - 1]
            if ($selectedPolicies -notcontains $selectedPolicy) {
                $selectedPolicies += $selectedPolicy
                Write-Host "Added: $($selectedPolicy.Name)" -ForegroundColor Green
            }
            else {
                Write-Host "Already selected: $($selectedPolicy.Name)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    }
    
    return $selectedPolicies
}

# Main execution
Write-Host "=== Intune Configuration Profile Creation Script ===" -ForegroundColor Cyan
Write-Host "This script will create configuration profiles from JSON files" -ForegroundColor Cyan
Write-Host ""

# Initialize configuration folder
if (-not (Initialize-ConfigFolder)) {
    Write-Error "Cannot proceed without configuration folder"
    return
}

Write-Host "Configuration folder: $ConfigFolderPath" -ForegroundColor Gray
Write-Host ""

# Load configuration policies from folder
$availablePolicies = Get-ConfigurationPoliciesFromFolder

# If no policies found, offer to create sample files
if ($availablePolicies.Count -eq 0) {
    Write-Host "No configuration files found. Would you like to create sample configuration files? (Y/N): " -ForegroundColor Yellow -NoNewline
    $createSamples = Read-Host
    
    if ($createSamples -eq 'Y' -or $createSamples -eq 'y') {
        $samplesCreated = New-SampleConfigurationFiles
        if ($samplesCreated -gt 0) {
            Write-Host "`nPlease customize the sample files and run the script again." -ForegroundColor Cyan
        }
    }
    
    Write-Host "Exiting..." -ForegroundColor Yellow
    return
}

Write-Host "Found $($availablePolicies.Count) configuration file(s)" -ForegroundColor Green
Write-Host ""

# Connect to Microsoft Graph
if (Connect-ToMSGraph) {
    Write-Host ""
    
    # Show menu and get user selections
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
    
    # Process each selected policy
    foreach ($policy in $selectedPolicies) {
        Write-Host "Processing policy: $($policy.Name)" -ForegroundColor Yellow
        
        # Check if policy already exists
        if (Test-PolicyExists -PolicyName $policy.Name) {
            Write-Warning "Policy '$($policy.Name)' already exists. Skipping creation."
            continue
        }
        
        # Handle special requirements (like LAPS Entra ID enablement)
        if ($policy.RequiresEntraConfig -and $policy.Name -like "*LAPS*") {
            Write-Host "LAPS policy selected - enabling LAPS in Entra ID first..." -ForegroundColor Yellow
            Enable-LAPSInEntraID
        }
        
        # Create the policy
        $result = New-ConfigurationPolicyFromJson -PolicyData $policy.Data -PolicyName $policy.Name
        
        if ($result) {
            Write-Host "✓ Policy '$($policy.Name)' created successfully!" -ForegroundColor Green
        }
        else {
            Write-Error "✗ Failed to create policy: $($policy.Name)"
        }
        
        Write-Host ""
    }
    
    Write-Host "=== Script Execution Completed ===" -ForegroundColor Cyan
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "- Selected policies: $($selectedPolicies.Count)" -ForegroundColor Gray
    Write-Host "- Configuration folder: $ConfigFolderPath" -ForegroundColor Gray
    Write-Host "- Check the Intune portal to verify policy creation and assignment" -ForegroundColor Gray
}
else {
    Write-Error "Cannot proceed without Microsoft Graph connection"
}

# Disconnect from Microsoft Graph
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}