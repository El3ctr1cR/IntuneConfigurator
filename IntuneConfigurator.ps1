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
    "Directory.ReadWrite.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Device.ReadWrite.All",
    "WindowsUpdates.ReadWrite.All"
)

$ConfigFolderPath = Join-Path $PSScriptRoot "json"
$AutopilotFolderPath = Join-Path $PSScriptRoot "autopilot"
$ESPFolderPath = Join-Path $PSScriptRoot "esp"
$AppsFolderPath = Join-Path $PSScriptRoot "apps"

foreach ($module in $Modules) {
    if (!(Get-Module -ListAvailable -Name $module.Name | Where-Object { [version]$_.Version -ge [version]$module.MinVersion })) {
        try {
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -AllowClobber -ErrorAction Stop
            Write-Host "Successfully installed $($module.Name) version $($module.MinVersion) or higher" -ForegroundColor Green
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

function Initialize-ConfigFolders {
    $foldersToCheck = @(
        @{Path = $ConfigFolderPath; Name = "Configuration Policies"},
        @{Path = $AutopilotFolderPath; Name = "Autopilot Profiles"},
        @{Path = $ESPFolderPath; Name = "Enrollment Status Page Profiles"},
        @{Path = $AppsFolderPath; Name = "Applications"}
    )
    
    $foundConfigs = $false
    
    foreach ($folder in $foldersToCheck) {
        if (Test-Path $folder.Path) {
            $jsonFiles = Get-ChildItem -Path $folder.Path -Filter "*.json" -ErrorAction SilentlyContinue
            if ($jsonFiles.Count -gt 0) {
                Write-Host "Found $($jsonFiles.Count) JSON file(s) in $($folder.Name) folder" -ForegroundColor Green
                $foundConfigs = $true
            }
        }
    }
    
    if (-not $foundConfigs) {
        Write-Warning "No JSON files found in any configuration folders"
        Write-Host "Expected folders:" -ForegroundColor Yellow
        Write-Host "  - $ConfigFolderPath (for configuration policies)" -ForegroundColor Yellow
        Write-Host "  - $AutopilotFolderPath (for autopilot profiles)" -ForegroundColor Yellow
        Write-Host "  - $ESPFolderPath (for enrollment status page profiles)" -ForegroundColor Yellow
        Write-Host "  - $AppsFolderPath (for applications)" -ForegroundColor Yellow
        return $false
    }
    
    return $true
}

function Remove-ReadOnlyProperties {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$JsonObject
    )
    
    $propertiesToRemove = @(
        '@odata.context',
        '@odata.id',
        '@odata.editLink',
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'version',
        'assignments',
        'assignedDevices',
        'roleScopeTagIds',
        'supportsScopeTags',
        'deviceEnrollmentConfigurationType'
    )
    
    $cleanObject = @{}
    
    $JsonObject.PSObject.Properties | ForEach-Object {
        $propertyName = $_.Name
        $propertyValue = $_.Value
        
        if ($propertyName -in $propertiesToRemove) {
            return
        }
        
        if ($propertyName.StartsWith('@') -and $propertyName -ne '@odata.type') {
            return
        }
        
        if ($propertyValue -is [PSCustomObject]) {
            $cleanObject[$propertyName] = Remove-ReadOnlyProperties -JsonObject $propertyValue
        }
        elseif ($propertyValue -is [Array]) {
            $cleanArray = @()
            foreach ($item in $propertyValue) {
                if ($item -is [PSCustomObject]) {
                    $cleanArray += Remove-ReadOnlyProperties -JsonObject $item
                }
                else {
                    $cleanArray += $item
                }
            }
            $cleanObject[$propertyName] = $cleanArray
        }
        else {
            $cleanObject[$propertyName] = $propertyValue
        }
    }
    
    return [PSCustomObject]$cleanObject
}

function Get-ConfigurationPoliciesFromFolder {
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

function Get-AutopilotProfilesFromFolder {
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
                    Data = Remove-ReadOnlyProperties -JsonObject $profileData
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

function Get-ESPProfilesFromFolder {
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
                    Data = Remove-ReadOnlyProperties -JsonObject $profileData
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

function Get-AppConfigurationsFromFolder {
    try {
        if (-not (Test-Path $AppsFolderPath)) {
            return @()
        }
        
        $configFiles = Get-ChildItem -Path $AppsFolderPath -Filter "*.json" -ErrorAction Stop
        $apps = @()
        
        foreach ($file in $configFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $jsonContent = $jsonContent -replace '^\uFEFF', ''
                $appData = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                
                $app = @{
                    Name = "VWC BL - $baseName"
                    Description = "🛡️ Dit is een standaard VWC Baseline application"
                    Data = Remove-ReadOnlyProperties -JsonObject $appData
                    FileName = $file.Name
                    Type = "App"
                    Assignment = if ($appData.PSObject.Properties.Name -contains 'assignment') { $appData.assignment } else { "devices" }
                }
                
                $apps += $app
            }
            catch {
                Write-Warning "Failed to load app configuration from $($file.Name): $($_.Exception.Message)"
                continue
            }
        }
        
        return $apps
    }
    catch {
        Write-Error "Failed to load app configuration files: $($_.Exception.Message)"
        return @()
    }
}

function Validate-DeviceNameTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template
    )
    
    if ($Template.Length -gt 15) {
        Write-Error "Device name template must be 15 characters or less (current length: $($Template.Length))."
        return $false
    }
    
    if ($Template -match '\s') {
        Write-Error "Device name template cannot contain spaces."
        return $false
    }
    
    if ($Template -match '^[0-9]+$') {
        Write-Error "Device name template cannot consist only of numbers."
        return $false
    }
    
    if ($Template -notmatch '^[a-zA-Z0-9\-]+(%SERIAL%|%RAND:\d+%)?$') {
        Write-Error "Device name template can only contain letters (a-z, A-Z), numbers (0-9), hyphens, %SERIAL%, or %RAND:x% (where x is a number)."
        return $false
    }
    
    return $true
}

function New-AutopilotProfile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProfileData,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )
    
    try {
        Write-Host "Creating Autopilot profile: $ProfileName..." -ForegroundColor Yellow
        
        $cleanProfileData = Remove-ReadOnlyProperties -JsonObject $ProfileData
        
        Write-Host "Enter a device name template for '$ProfileName' (e.g., DESKTOP-%SERIAL%, PC-%RAND:5%)" -ForegroundColor Yellow
        Write-Host "Requirements: 15 characters or less, letters/numbers/hyphens only, no spaces, not only numbers, supports %SERIAL% or %RAND:x%." -ForegroundColor Yellow
        
        $deviceNameTemplate = $null
        while (-not $deviceNameTemplate) {
            $inputTemplate = Read-Host "Device Name Template"
            if (Validate-DeviceNameTemplate -Template $inputTemplate) {
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
                
                $assignmentSuccess = Set-AutopilotAssignments -ProfileId $response.id -ProfileName $ProfileName -AssignmentType $cleanProfileData.assignment
                
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

function New-ESPProfile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProfileData,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )
    
    try {
        Write-Host "Creating ESP profile: $ProfileName..." -ForegroundColor Yellow
        
        $cleanProfileData = Remove-ReadOnlyProperties -JsonObject $ProfileData
        
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
                
                $assignmentSuccess = Set-ESPAssignments -ProfileId $response.id -ProfileName $ProfileName -AssignmentType $cleanProfileData.assignment
                
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
                
                $assignmentSuccess = Set-PolicyAssignments -PolicyId $response.id -PolicyName $PolicyName -AssignmentType $PolicyData.assignment
                
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
        [string]$PolicyName
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
                
                $assignmentSuccess = Set-LegacyPolicyAssignments -PolicyId $response.id -PolicyName $PolicyName -AssignmentType $PolicyData.assignment
                
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

function New-AppFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AppData,
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    
    try {
        Write-Host "Creating application: $AppName..." -ForegroundColor Yellow
        
        $cleanAppData = Remove-ReadOnlyProperties -JsonObject $AppData
        $odataType = $cleanAppData.'@odata.type'
        
        if (-not $odataType) {
            Write-Error "Missing @odata.type in app configuration for $AppName. Please ensure the JSON includes a valid @odata.type (e.g., #microsoft.graph.officeSuiteApp or #microsoft.graph.winGetApp)."
            return $null
        }
        
        $appBody = @{
            "@odata.type" = $odataType
            displayName = $AppName
            description = "🛡️ Dit is een standaard VWC Baseline application"
        }
        
        $commonProperties = @(
            'publisher',
            'isFeatured',
            'privacyInformationUrl',
            'informationUrl',
            'owner',
            'developer',
            'notes',
            'largeIcon',
            'categories'
        )
        
        foreach ($property in $commonProperties) {
            if ($cleanAppData.PSObject.Properties.Name -contains $property) {
                $appBody[$property] = $cleanAppData.$property
            }
        }
        
        if ($odataType -eq "#microsoft.graph.officeSuiteApp") {
            $officeProperties = @(
                'autoAcceptEula',
                'productIds',
                'useSharedComputerActivation',
                'updateChannel',
                'officeSuiteAppDefaultFileFormat',
                'officePlatformArchitecture',
                'localesToInstall',
                'installProgressDisplayLevel',
                'shouldUninstallOlderVersionsOfOffice',
                'targetVersion',
                'updateVersion',
                'officeConfigurationXml',
                'excludedApps'
            )
            
            foreach ($property in $officeProperties) {
                if ($cleanAppData.PSObject.Properties.Name -contains $property) {
                    $appBody[$property] = $cleanAppData.$property
                }
            }
        }
        elseif ($odataType -eq "#microsoft.graph.winGetApp") {
            $winGetProperties = @(
                'packageIdentifier',
                'installExperience',
                'manifestHash'
            )
            
            foreach ($property in $winGetProperties) {
                if ($cleanAppData.PSObject.Properties.Name -contains $property) {
                    $appBody[$property] = $cleanAppData.$property
                }
            }
        }
        else {
            Write-Warning "Unsupported app type: $odataType. Only #microsoft.graph.officeSuiteApp and #microsoft.graph.winGetApp are currently supported."
            return $null
        }
        
        if ($appBody.largeIcon -and ($appBody.largeIcon.value -eq "" -or $appBody.largeIcon.value -eq $null)) {
            $appBody.largeIcon = $null
        }
        
        if ($appBody.categories) {
            $appBody.categories = @($appBody.categories | ForEach-Object {
                @{
                    displayName = $_.displayName
                }
            })
        }
        
        $jsonBody = $appBody | ConvertTo-Json -Depth 20
        
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            
            if ($response.id) {
                Write-Host "Successfully created application: $AppName (ID: $($response.id))" -ForegroundColor Green
                
                $assignmentType = $item.Assignment
                if (-not $assignmentType) {
                    Write-Warning "No assignment type specified for $AppName. Defaulting to devices."
                    $assignmentType = "devices"
                }
                
                $assignmentSuccess = Set-AppAssignments -AppId $response.id -AppName $AppName -AssignmentType $assignmentType
                
                if (!$assignmentSuccess) {
                    Write-Warning "Application '$AppName' created but assignment failed"
                }
                
                return $response
            }
            else {
                Write-Error "Failed to create application: $AppName - No ID returned"
                return $null
            }
        }
        catch {
            Write-Error "Graph API request failed for application: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $null
        }
    }
    catch {
        Write-Error "Error creating application $AppName : $($_.Exception.Message)"
        return $null
    }
}

function Set-AutopilotAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileId,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning Autopilot profile '$ProfileName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            target = @{
                "@odata.type" = $odataType
            }
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned Autopilot profile '$ProfileName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign Autopilot profile '$ProfileName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign Autopilot profile '$ProfileName': $($_.Exception.Message)"
        return $false
    }
}

function Set-ESPAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileId,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning ESP profile '$ProfileName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            enrollmentConfigurationAssignments = @(
                @{
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations('$ProfileId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned ESP profile '$ProfileName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign ESP profile '$ProfileName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign ESP profile '$ProfileName': $($_.Exception.Message)"
        return $false
    }
}

function Set-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning policy '$PolicyName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            assignments = @(
                @{
                    id = ""
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned policy '$PolicyName' to $AssignmentType" -ForegroundColor Green
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
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning legacy policy '$PolicyName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('$PolicyId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned legacy policy '$PolicyName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign legacy policy '$PolicyName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign legacy policy '$PolicyName': $($_.Exception.Message)"
        return $false
    }
}

function Set-AppAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning application '$AppName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            mobileAppAssignments = @(
                @{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent = "Required"
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$AppId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned application '$AppName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign application '$AppName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign application '$AppName': $($_.Exception.Message)"
        return $false
    }
}

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

function Show-AllProfilesSelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [array]$ConfigPolicies,
        [Parameter(Mandatory = $true)]
        [array]$AutopilotProfiles,
        [Parameter(Mandatory = $true)]
        [array]$ESPProfiles,
        [Parameter(Mandatory = $true)]
        [array]$Apps
    )
    
    Write-Host "=== Available Profiles, Policies, and Applications ===" -ForegroundColor Cyan
    Write-Host ""
    
    $selectedItems = @()
    $allItems = @()
    
    $allItems += $ConfigPolicies
    $allItems += $AutopilotProfiles
    $allItems += $ESPProfiles
    $allItems += $Apps
    
    foreach ($item in $allItems) {
        $itemType = switch ($item.Type) {
            "Autopilot" { " [Autopilot Profile]" }
            "ESP" { " [ESP Profile]" }
            "App" { " [Application]" }
            default { if ($item.IsManual) { " [OMA-URI Policy]" } else { " [Config Policy]" } }
        }
        
        $specialReqs = @()
        if ($item.RequiresEntraConfig) { $specialReqs += "LAPS Config" }
        if ($item.RequiresEdgeSync) { $specialReqs += "Edge Sync Config" }
        if ($item.RequiresTenantId) { $specialReqs += "Tenant ID" }
        $reqText = if ($specialReqs.Count -gt 0) { " [Requires: $($specialReqs -join ', ')]" } else { "" }
        
        Write-Host "Item: $($item.Name)$itemType$reqText" -ForegroundColor White
        Write-Host "Description: $($item.Data.description)" -ForegroundColor Gray
        Write-Host "Source: $($item.FileName)" -ForegroundColor DarkGray
        Write-Host ""
        
        while ($true) {
            Write-Host "Do you want to select this item? (Y/N): " -ForegroundColor Yellow -NoNewline
            $selection = Read-Host
            
            if ($selection -match '^[Yy]$') {
                $selectedItems += $item
                Write-Host "Selected: $($item.Name)" -ForegroundColor Green
                break
            }
            elseif ($selection -match '^[Nn]$') {
                Write-Host "Skipped: $($item.Name)" -ForegroundColor Yellow
                break
            }
            else {
                Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
            }
        }
        Write-Host ""
    }
    
    return $selectedItems
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
    
    $updated = $false
    
    foreach ($child in $Children) {
        if ($child.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance" -and 
            $child.settingDefinitionId -match "onedrivengsc.*_kfmoptinnowizard_textbox") {
            
            $child.simpleSettingValue.value = $TenantId
            Write-Host "✓ Found and updated Tenant ID setting ($($child.settingDefinitionId))" -ForegroundColor Green
            $updated = $true
        }
        elseif ($child.choiceSettingValue -and $child.choiceSettingValue.children) {
            $nestedUpdated = Update-TenantIdInChildren -Children $child.choiceSettingValue.children -TenantId $TenantId
            if ($nestedUpdated) {
                $updated = $true
            }
        }
    }
    
    return $updated
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
        Write-Host "Description: $($policy.Data.description)" -ForegroundColor Gray
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

# Main execution
Write-Host ""
Write-Host "=== Enhanced Intune Configuration Script ===" -ForegroundColor Cyan
Write-Host "This script will create configuration profiles, Autopilot profiles, ESP profiles, and applications for Intune" -ForegroundColor Cyan
Write-Host ""

if (-not (Initialize-ConfigFolders)) {
    Write-Error "Cannot proceed without configuration files"
    return
}

Write-Host ""

# Connect to MS Graph
if (-not (Connect-ToMSGraph)) {
    Write-Error "Cannot proceed without Microsoft Graph connection"
    return
}

# Load all profile types
$configPolicies = Get-ConfigurationPoliciesFromFolder
$autopilotProfiles = Get-AutopilotProfilesFromFolder
$espProfiles = Get-ESPProfilesFromFolder
$apps = Get-AppConfigurationsFromFolder

$totalItems = $configPolicies.Count + $autopilotProfiles.Count + $espProfiles.Count + $apps.Count

if ($totalItems -eq 0) {
    Write-Host "No valid configuration files were found or loaded." -ForegroundColor Yellow
    return
}

Write-Host ""

$selectedItems = Show-AllProfilesSelectionMenu -ConfigPolicies $configPolicies -AutopilotProfiles $autopilotProfiles -ESPProfiles $espProfiles -Apps $apps

if ($selectedItems.Count -eq 0) {
    Write-Host "No items selected. Exiting..." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "=== Selected Items ===" -ForegroundColor Cyan
foreach ($item in $selectedItems) {
    $typeText = switch ($item.Type) {
        "Autopilot" { " (Autopilot Profile)" }
        "ESP" { " (ESP Profile)" }
        "App" { " (Application)" }
        default { " (Configuration Policy)" }
    }
    Write-Host "- $($item.Name)$typeText" -ForegroundColor Green
}
Write-Host ""
Write-Host "Press any key to continue with item creation..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# Get tenant ID if needed
$tenantId = $null
$needsTenantId = $selectedItems | Where-Object { $_.RequiresTenantId }
if ($needsTenantId) {
    $tenantId = Get-TenantId
    if (-not $tenantId) {
        Write-Error "Cannot proceed with OneDrive policies without Tenant ID"
        return
    }
}

# Process each selected item
foreach ($item in $selectedItems) {
    Write-Host "Processing: $($item.Name)" -ForegroundColor Yellow
    
    # Check if item exists
    $exists = $false
    switch ($item.Type) {
        "Autopilot" { $exists = Test-AutopilotProfileExists -ProfileName $item.Name }
        "ESP" { $exists = Test-ESPProfileExists -ProfileName $item.Name }
        "App" { $exists = Test-AppExists -AppName $item.Name }
        default { $exists = Test-PolicyExists -PolicyName $item.Name }
    }
    
    if ($exists) {
        Write-Warning "Item '$($item.Name)' already exists. Skipping creation."
        continue
    }
    
    # Handle special requirements
    if ($item.Type -eq "Config") {
        if ($item.RequiresEntraConfig -and $item.Name -like "*LAPS*") {
            Write-Host "LAPS policy selected - enabling LAPS in Entra ID first..." -ForegroundColor Yellow
            Enable-LAPSInEntraID
        }
        
        if ($item.RequiresEdgeSync) {
            Request-EdgeSyncConfiguration -PolicyName $item.Name
        }
        
        if ($item.RequiresTenantId -and $tenantId) {
            Write-Host "OneDrive policy selected - updating with Tenant ID..." -ForegroundColor Yellow
            $updated = Update-OneDrivePolicyWithTenantId -PolicyData $item.Data -TenantId $tenantId
            if (-not $updated) {
                Write-Warning "Failed to update OneDrive policy with Tenant ID. Proceeding anyway..."
            }
        }
    }
    
    # Create the item
    $result = $null
    switch ($item.Type) {
        "Autopilot" {
            $result = New-AutopilotProfile -ProfileData $item.Data -ProfileName $item.Name
        }
        "ESP" {
            $result = New-ESPProfile -ProfileData $item.Data -ProfileName $item.Name
        }
        "App" {
            $result = New-AppFromJson -AppData $item.Data -AppName $item.Name
        }
        "Config" {
            if ($item.IsManual) {
                $result = New-ManualOmaUriPolicy -PolicyData $item.Data -PolicyName $item.Name
            }
            else {
                $result = New-ConfigurationPolicyFromJson -PolicyData $item.Data -PolicyName $item.Name
            }
        }
    }
    
    if (!$result) {
        Write-Error "✗ Failed to create: $($item.Name)"
    }
    
    Write-Host ""
}

Write-Host "=== Script Execution Completed ===" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor White
Write-Host "- Selected items: $($selectedItems.Count)" -ForegroundColor Gray
Write-Host "- Check Intune portal to verify group assignments" -ForegroundColor Gray

try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
}
catch {
    # Ignore disconnect errors
}