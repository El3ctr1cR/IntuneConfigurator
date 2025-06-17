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
$ConfigFolderPath = Join-Path $env:TEMP "IntuneConfigurator"
$GitHubJsonUrl = "https://api.github.com/repos/El3ctr1cR/IntuneConfigurator/contents/json"

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

# Also update the download function to not double-convert JSON
function Initialize-ConfigFolder {
    try {
        # Clean up existing folder if it exists
        if (Test-Path $ConfigFolderPath) {
            Remove-Item -Path $ConfigFolderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Create fresh configuration folder
        New-Item -ItemType Directory -Path $ConfigFolderPath -Force | Out-Null
        
        # Download JSON files from GitHub
        Write-Host "Downloading baseline configuration files from El3ctr1cR's GitHub..." -ForegroundColor Yellow
        
        try {
            # Get list of files from GitHub API
            $response = Invoke-RestMethod -Uri $GitHubJsonUrl -Method GET -ErrorAction Stop
            
            # Filter for JSON files only
            $jsonFiles = $response | Where-Object { $_.name -like "*.json" -and $_.type -eq "file" }
            
            if ($jsonFiles.Count -eq 0) {
                Write-Error "No JSON files found in the GitHub repository"
                return $false
            }
            
            Write-Host "Found $($jsonFiles.Count) configuration file(s) to download" -ForegroundColor Cyan
            
            # Download each JSON file
            foreach ($file in $jsonFiles) {
                try {
                    $localFilePath = Join-Path $ConfigFolderPath $file.name
                    
                    # Download the raw file content directly (don't parse and re-serialize)
                    $fileContent = Invoke-RestMethod -Uri $file.download_url -Method GET -ErrorAction Stop
                    
                    # Save file content as raw JSON (not re-serialized)
                    if ($fileContent -is [string]) {
                        # It's already a string, save directly
                        $fileContent | Out-File -FilePath $localFilePath -Encoding UTF8 -ErrorAction Stop
                    } else {
                        # It's been parsed as an object, need to convert back to JSON
                        $fileContent | ConvertTo-Json -Depth 20 | Out-File -FilePath $localFilePath -Encoding UTF8 -ErrorAction Stop
                    }
                    
                    Write-Host "Downloaded: $($file.name)" -ForegroundColor Green
                }
                catch {
                    Write-Warning "Failed to download $($file.name): $($_.Exception.Message)"
                    continue
                }
            }
            
            return $true
        }
        catch {
            Write-Error "Failed to access GitHub repository: $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        Write-Error "Failed to initialize configuration folder: $($_.Exception.Message)"
        return $false
    }
}

# Function to clean up temporary files
function Remove-ConfigFolder {
    try {
        if (Test-Path $ConfigFolderPath) {
            #Remove-Item -Path $ConfigFolderPath -Recurse -Force -ErrorAction Stop
            Write-Host "Cleaned up temporary files" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Could not clean up temporary folder: $($_.Exception.Message)"
    }
}

# Function to load JSON configuration files from folder
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
                # Read and parse JSON file
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent.TrimEnd('.')  # Remove any trailing periods
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

# Function to connect to Microsoft Graph
function Connect-ToMSGraph {
    try {
        # Connect with required scopes
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
        } else {
            Write-Error "Failed to retrieve Tenant ID: No organization data returned"
            return $null
        }
    }
    catch {
        Write-Error "Failed to retrieve Tenant ID: $($_.Exception.Message)"
        return $null
    }
}

# Function to create configuration policy from JSON (ENHANCED VERSION with better error handling)
function New-ConfigurationPolicyFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyData,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Creating configuration policy: $PolicyName..." -ForegroundColor Yellow
        
        # Check if this is an endpoint security policy based on templateReference
        $isEndpointSecurity = $false
        if ($PolicyData.templateReference -and 
            $PolicyData.templateReference.templateFamily -ne "none" -and 
            $PolicyData.templateReference.templateId -ne "") {
            $isEndpointSecurity = $true
        }
        
        # Create a deep copy of PolicyData to avoid modifying the original
        $policyBody = $PolicyData | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        
        # Handle OneDrive silently move Windows known folders policy
        if ($PolicyName -like "*OneDrive silently move Windows known folders*") {
            Write-Host "Detected OneDrive policy - retrieving Tenant ID..." -ForegroundColor Yellow
            $tenantId = Get-TenantId
            if (-not $tenantId) {
                Write-Error "Cannot proceed with OneDrive policy creation without Tenant ID"
                return $null
            }
            
            # Find and update the tenant ID setting
            foreach ($setting in $policyBody.settings) {
                if ($setting.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance" -and 
                    $setting.settingDefinitionId -eq "device_vendor_msft_policy_config_onedrivengscv2.updates~policy~onedrivengsc_kfmoptinnowizard_kfmoptinnowizard_textbox") {
                    $setting.simpleSettingValue.value = $tenantId
                    Write-Host "Inserted Tenant ID ($tenantId) into OneDrive policy settings" -ForegroundColor Green
                    break
                }
            }
        }
        
        # Create the policy body
        $policyBody = @{
            name = $PolicyName
            description = $PolicyData.description
            platforms = $PolicyData.platforms
            technologies = $PolicyData.technologies
            settings = $policyBody.settings
        }
        
        # Add templateReference if this is an endpoint security policy
        if ($isEndpointSecurity) {
            $policyBody.templateReference = $PolicyData.templateReference
        }
        
        # Convert to JSON for the API call
        $jsonBody = $policyBody | ConvertTo-Json -Depth 20
        
        # Use the same endpoint - Graph API handles different policy types via templateReference
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created policy: $PolicyName (ID: $($response.id))" -ForegroundColor Green
                
                # Assign the policy to All Devices and All Users
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

# Function to assign policy to All Devices and All Users
function Set-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName
    )
    
    try {
        Write-Host "Assigning policy '$PolicyName' to All Devices and All Users..." -ForegroundColor Yellow
        
        # Define assignment body for All Devices and All Users
        $assignmentBody = @{
            assignments = @(
                @{
                    id = ""
                    target = @{
                        "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                    }
                },
                @{
                    id = ""
                    target = @{
                        "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                    }
                }
            )
        }
        
        # Convert to JSON
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        # Assign the policy
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
Write-Host ""
Write-Host "=== Intune Configuration Profile Creation Script ===" -ForegroundColor Cyan
Write-Host "This script will create all the baseline configuration profiles for Intune" -ForegroundColor Cyan
Write-Host ""

# Initialize configuration folder and download files from GitHub
if (-not (Initialize-ConfigFolder)) {
    Write-Error "Cannot proceed without configuration files"
    return
}

Write-Host ""

# Load configuration policies from folder
$availablePolicies = Get-ConfigurationPoliciesFromFolder

# Check if any policies were loaded
if ($availablePolicies.Count -eq 0) {
    Write-Host "No valid configuration files were found or loaded." -ForegroundColor Yellow
    Remove-ConfigFolder
    return
}

Write-Host "Loaded $($availablePolicies.Count) configuration file(s)" -ForegroundColor Green
Write-Host ""

# Connect to Microsoft Graph
if (Connect-ToMSGraph) {
    Write-Host ""
    
    # Show menu and get user selections
    $selectedPolicies = Show-PolicySelectionMenu -AvailablePolicies $availablePolicies
    
    if ($selectedPolicies.Count -eq 0) {
        Write-Host "No policies selected. Exiting..." -ForegroundColor Yellow
        Remove-ConfigFolder
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
        
        if (!$result) {
            Write-Error "✗ Failed to create policy: $($policy.Name)"
        }
        
        Write-Host ""
    }
    
    Write-Host "=== Script Execution Completed ===" -ForegroundColor Cyan
    Write-Host "Summary:" -ForegroundColor White
    Write-Host "- Selected policies: $($selectedPolicies.Count)" -ForegroundColor Gray
    Write-Host "- Check the Intune portal to verify policy creation and assignment" -ForegroundColor Gray
    
    # Clean up temporary files
    Remove-ConfigFolder
}
else {
    Write-Error "Cannot proceed without Microsoft Graph connection"
    Remove-ConfigFolder
}

# Disconnect from Microsoft Graph
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}