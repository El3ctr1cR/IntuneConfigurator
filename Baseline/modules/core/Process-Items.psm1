function Invoke-SelectedItems {
    param(
        [Parameter(Mandatory = $true)]
        [array]$SelectedItems,
        [Parameter(Mandatory = $true)]
        [string]$ConfigFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$AutopilotFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$ESPFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$AppsFolderPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RemoveReadOnlyProperties,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ValidateDeviceNameTemplate,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetAutopilotAssignments,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetESPAssignments,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetPolicyAssignments,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetLegacyPolicyAssignments,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SetAppAssignments,
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestAutopilotProfileExists,
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestESPProfileExists,
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestPolicyExists,
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestAppExists,
        [Parameter(Mandatory = $true)]
        [scriptblock]$GetTenantId,
        [Parameter(Mandatory = $true)]
        [scriptblock]$UpdateOneDrivePolicyWithTenantId,
        [Parameter(Mandatory = $true)]
        [scriptblock]$UpdateTenantIdInChildren,
        [Parameter(Mandatory = $true)]
        [scriptblock]$EnableLAPSInEntraID,
        [Parameter(Mandatory = $true)]
        [scriptblock]$RequestEdgeSyncConfiguration
    )
    
    # Get tenant ID if needed
    $tenantId = $null
    $needsTenantId = $SelectedItems | Where-Object { $_.RequiresTenantId }
    if ($needsTenantId) {
        $tenantId = & $GetTenantId
        if (-not $tenantId) {
            Write-Error "Cannot proceed with OneDrive policies without Tenant ID"
            return
        }
    }
    
    # Process each selected item
    foreach ($item in $SelectedItems) {
        Write-Host "Processing: $($item.Name)" -ForegroundColor Yellow
        
        # Check if item exists
        $exists = $false
        switch ($item.Type) {
            "Autopilot" { $exists = & $TestAutopilotProfileExists -ProfileName $item.Name }
            "ESP" { $exists = & $TestESPProfileExists -ProfileName $item.Name }
            "App" { $exists = & $TestAppExists -AppName $item.Name }
            default { $exists = & $TestPolicyExists -PolicyName $item.Name }
        }
        
        if ($exists) {
            Write-Warning "Item '$($item.Name)' already exists. Skipping creation."
            continue
        }
        
        # Handle special requirements
        if ($item.Type -eq "Config") {
            if ($item.RequiresEntraConfig -and $item.Name -like "*LAPS*") {
                Write-Host "LAPS policy selected - enabling LAPS in Entra ID first..." -ForegroundColor Yellow
                & $EnableLAPSInEntraID
            }
            
            if ($item.RequiresEdgeSync) {
                & $RequestEdgeSyncConfiguration -PolicyName $item.Name
            }
            
            if ($item.RequiresTenantId -and $tenantId) {
                Write-Host "OneDrive policy selected - updating with Tenant ID..." -ForegroundColor Yellow
                $updated = & $UpdateOneDrivePolicyWithTenantId -PolicyData $item.Data -TenantId $tenantId -UpdateTenantIdInChildren $UpdateTenantIdInChildren
                if (-not $updated) {
                    Write-Warning "Failed to update OneDrive policy with Tenant ID. Proceeding anyway..."
                }
            }
        }
        
        # Create the item
        $result = $null
        switch ($item.Type) {
            "Autopilot" {
                $result = New-AutopilotProfile -ProfileData $item.Data -ProfileName $item.Name -RemoveReadOnlyProperties $RemoveReadOnlyProperties -ValidateDeviceNameTemplate $ValidateDeviceNameTemplate -SetAutopilotAssignments $SetAutopilotAssignments
            }
            "ESP" {
                $result = New-ESPProfile -ProfileData $item.Data -ProfileName $item.Name -RemoveReadOnlyProperties $RemoveReadOnlyProperties -SetESPAssignments $SetESPAssignments
            }
            "App" {
                $result = New-AppFromJson -AppData $item.Data -AppName $item.Name -RemoveReadOnlyProperties $RemoveReadOnlyProperties -SetAppAssignments $SetAppAssignments
            }
            "Config" {
                if ($item.IsManual) {
                    $result = New-ManualOmaUriPolicy -PolicyData $item.Data -PolicyName $item.Name -SetLegacyPolicyAssignments $SetLegacyPolicyAssignments
                }
                else {
                    $result = New-ConfigurationPolicyFromJson -PolicyData $item.Data -PolicyName $item.Name -SetPolicyAssignments $SetPolicyAssignments
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
    Write-Host "- Selected items: $($SelectedItems.Count)" -ForegroundColor Gray
    Write-Host "- Check Intune portal to verify group assignments" -ForegroundColor Gray
}

Export-ModuleMember -Function Invoke-SelectedItems