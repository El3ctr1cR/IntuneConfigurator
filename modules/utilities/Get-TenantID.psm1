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
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [scriptblock]$UpdateTenantIdInChildren
    )
    
    try {
        Write-Host "Updating OneDrive policy with Tenant ID ($TenantId)..." -ForegroundColor Yellow
        
        foreach ($setting in $PolicyData.settings) {
            if ($setting.settingInstance -and 
                $setting.settingInstance.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance") {
                
                $updated = & $UpdateTenantIdInChildren -Children $setting.settingInstance.choiceSettingValue.children -TenantId $TenantId
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
            $nestedUpdated = & $UpdateTenantIdInChildren -Children $child.choiceSettingValue.children -TenantId $TenantId
            if ($nestedUpdated) {
                $updated = $true
            }
        }
    }
    
    return $updated
}

Export-ModuleMember -Function Get-TenantId, Update-OneDrivePolicyWithTenantId, Update-TenantIdInChildren