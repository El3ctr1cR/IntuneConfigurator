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

Export-ModuleMember -Function Enable-LAPSInEntraID