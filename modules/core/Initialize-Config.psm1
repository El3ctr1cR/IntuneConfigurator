function Initialize-ConfigFolders {
    param (
        [string]$ConfigFolderPath,
        [string]$AutopilotFolderPath,
        [string]$ESPFolderPath,
        [string]$AppsFolderPath
    )
    
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

Export-ModuleMember -Function Initialize-ConfigFolders