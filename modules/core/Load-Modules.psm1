$Modules = @(
    @{Name = "Microsoft.Graph.Authentication"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.DeviceManagement"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Identity.SignIns"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Groups"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Beta.Identity.SignIns"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Users"; MinVersion = "1.0.0" },
    @{Name = "Microsoft.Graph.Beta.DeviceManagement"; MinVersion = "1.0.0" }
)

function Install-RequiredModules {
    try {
        Write-Host "Checking for required PowerShell modules..." -ForegroundColor Yellow
        
        foreach ($module in $Modules) {
            $installedModule = Get-Module -Name $module.Name -ListAvailable | 
                Where-Object { [System.Version]$_.Version -ge [System.Version]$module.MinVersion } | 
                Sort-Object Version -Descending | 
                Select-Object -First 1
                
            if (-not $installedModule) {
                Write-Host "Installing module $($module.Name)..." -ForegroundColor Yellow
                Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Write-Host "Successfully installed $($module.Name)" -ForegroundColor Green
            }
            else {
                Write-Host "Module $($module.Name) version $($installedModule.Version) is already installed" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "Failed to install required modules: $($_.Exception.Message)"
        return $false
    }
    return $true
}

function Import-RequiredModules {
    try {
        Write-Host "Importing required PowerShell modules..." -ForegroundColor Yellow
        
        foreach ($module in $Modules) {
            $installedModule = Get-Module -Name $module.Name -ListAvailable | 
                Where-Object { [System.Version]$_.Version -ge [System.Version]$module.MinVersion } | 
                Sort-Object Version -Descending | 
                Select-Object -First 1
                
            if ($installedModule) {
                Import-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -ErrorAction Stop
                Write-Host "Successfully imported $($module.Name) version $($installedModule.Version)" -ForegroundColor Green
            }
            else {
                Write-Error "Module $($module.Name) version $($module.MinVersion) or higher is not installed"
                return $false
            }
        }
    }
    catch {
        Write-Error "Failed to import required modules: $($_.Exception.Message)"
        return $false
    }
    return $true
}

Export-ModuleMember -Function Install-RequiredModules, Import-RequiredModules