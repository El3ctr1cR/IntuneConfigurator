function Get-AppConfigurationsFromFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppsFolderPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties
    )
    
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
                    Data = & $RemoveReadOnlyProperties -JsonObject $appData
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

function New-AppFromJson {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AppData,
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetAppAssignments
    )
    
    try {
        Write-Host "Creating application: $AppName..." -ForegroundColor Yellow
        
        $cleanAppData = & $RemoveReadOnlyProperties -JsonObject $AppData
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
                
                $assignmentType = $AppData.Assignment
                if (-not $assignmentType) {
                    Write-Warning "No assignment type specified for $AppName. Defaulting to devices."
                    $assignmentType = "devices"
                }
                
                $assignmentSuccess = & $SetAppAssignments -AppId $response.id -AppName $AppName -AssignmentType $assignmentType
                
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

Export-ModuleMember -Function Get-AppConfigurationsFromFolder, New-AppFromJson