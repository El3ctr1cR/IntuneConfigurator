# modules/core/Load-Modules.psm1
# Installs and imports required PowerShell modules for the Duo Security deployer

$Modules = @(
    @{ Name = "Microsoft.Graph.Authentication"; MinVersion = "1.0.0" },
    @{ Name = "Microsoft.Graph.Beta.DeviceManagement"; MinVersion = "1.0.0" }
)

function Install-RequiredModules {
    try {
        Write-Host "Checking for required PowerShell modules..." -ForegroundColor Yellow

        foreach ($module in $Modules) {
            $installed = Get-Module -Name $module.Name -ListAvailable |
                Where-Object { [System.Version]$_.Version -ge [System.Version]$module.MinVersion } |
                Sort-Object Version -Descending |
                Select-Object -First 1

            if (-not $installed) {
                Write-Host "Installing $($module.Name)..." -ForegroundColor Yellow
                Install-Module -Name $module.Name -MinimumVersion $module.MinVersion `
                    -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Write-Host "Installed $($module.Name)" -ForegroundColor Green
            }
            else {
                Write-Host "Module $($module.Name) v$($installed.Version) is already installed" -ForegroundColor Green
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to install required modules: $($_.Exception.Message)"
        return $false
    }
}

function Import-RequiredModules {
    try {
        Write-Host "Importing required PowerShell modules..." -ForegroundColor Yellow

        foreach ($module in $Modules) {
            $installed = Get-Module -Name $module.Name -ListAvailable |
                Where-Object { [System.Version]$_.Version -ge [System.Version]$module.MinVersion } |
                Sort-Object Version -Descending |
                Select-Object -First 1

            if ($installed) {
                Import-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -ErrorAction Stop
                Write-Host "Imported $($module.Name) v$($installed.Version)" -ForegroundColor Green
            }
            else {
                Write-Error "Module $($module.Name) is not installed."
                return $false
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to import required modules: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Install-RequiredModules, Import-RequiredModules