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

Export-ModuleMember -Function Request-EdgeSyncConfiguration