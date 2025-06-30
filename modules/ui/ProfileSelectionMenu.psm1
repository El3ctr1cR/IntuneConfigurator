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

Export-ModuleMember -Function Show-AllProfilesSelectionMenu, Show-PolicySelectionMenu