# modules/Duo-Remediation.psm1
# Deploys an Intune Proactive Remediation (deviceHealthScript) that checks
# and enforces the Duo Security ParseUsernameAndDomain registry key.

#region - Script content

$DetectionScript = @'
$regPath  = "HKLM:\SOFTWARE\Duo Security\DuoCredProv"
$regName  = "ParseUsernameAndDomain"
$expected = 1

try {
    if (-not (Test-Path $regPath)) {
        Write-Output "Non-compliant: Registry path does not exist."
        exit 1
    }

    $current = $null
    try {
        $current = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop).$regName
    }
    catch {
        Write-Output "Non-compliant: Value '$regName' not found."
        exit 1
    }

    if ($current -eq $expected) {
        Write-Output "Compliant: $regName = $current"
        exit 0
    }
    else {
        Write-Output "Non-compliant: $regName = $current (expected $expected)"
        exit 1
    }
}
catch {
    Write-Output "Non-compliant: Unexpected error - $($_.Exception.Message)"
    exit 1
}
'@

$RemediationScript = @'
$regPath  = "HKLM:\SOFTWARE\Duo Security\DuoCredProv"
$regName  = "ParseUsernameAndDomain"
$value    = 1

try {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-Output "Created registry path: $regPath"
    }

    Set-ItemProperty -Path $regPath -Name $regName -Value $value -Type DWord -Force
    Write-Output "Remediated: $regName set to $value"
    exit 0
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
'@

#endregion

#region - Helper

function Get-GraphErrorDetail {
    param($Exception)
    $detail = $null
    try { $detail = $_.ErrorDetails.Message } catch {}
    if (-not $detail) {
        try { $detail = $Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch {}
    }
    return $detail
}

#endregion

#region - Main deploy function

function Invoke-DuoRemediationDeploy {

    Write-Host ""
    Write-Host "=== Deploying Proactive Remediation ===" -ForegroundColor Cyan
    Write-Host ""

    $baseUri     = "https://graph.microsoft.com/beta/deviceManagement"
    $scriptName  = "Duo Security - ParseUsernameAndDomain Fix"
    $description = "Checks and enforces HKLM\SOFTWARE\Duo Security\DuoCredProv\ParseUsernameAndDomain = 1. Required for Entra ID-joined devices to send correct usernames to Duo."
    $publisher   = "DUO Security Inc."

    $detectionB64   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($DetectionScript))
    $remediationB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemediationScript))

    # Verify scope
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.Scopes -notcontains "DeviceManagementConfiguration.ReadWrite.All") {
        Write-Host ""
        Write-Host "[!] Warning: Current Graph session is missing DeviceManagementConfiguration.ReadWrite.All" -ForegroundColor Yellow
        Write-Host "    The remediation deployment may fail. Re-run the script to reconnect with the correct scopes." -ForegroundColor Yellow
        Write-Host ""
    }

    # Check for existing remediation
    Write-Host "Checking if remediation already exists in Intune..." -ForegroundColor Yellow

    try {
        $existingResp = Invoke-MgGraphRequest -Method GET `
            -Uri "$baseUri/deviceHealthScripts?`$filter=displayName eq '$scriptName'" `
            -ErrorAction Stop
        $existingScript = $existingResp.value | Select-Object -First 1
    }
    catch {
        $detail = Get-GraphErrorDetail $_.Exception
        Write-Error "Failed to query existing remediations: $($_.Exception.Message)$(if ($detail) {"`n  Graph response: $detail"})"
        return
    }

    if ($existingScript) {
        Write-Host ""
        Write-Host "A remediation named '$scriptName' already exists." -ForegroundColor Yellow
        while ($true) {
            Write-Host "Do you want to overwrite it? (Y/N): " -ForegroundColor Yellow -NoNewline
            $overwrite = Read-Host
            if ($overwrite -match '^[Yy]$') {
                try {
                    Invoke-MgGraphRequest -Method DELETE `
                        -Uri "$baseUri/deviceHealthScripts/$($existingScript.id)" `
                        -ErrorAction Stop | Out-Null
                    Write-Host "Removed existing remediation: $($existingScript.id)" -ForegroundColor Gray
                }
                catch {
                    $detail = Get-GraphErrorDetail $_.Exception
                    Write-Error "Failed to remove: $($_.Exception.Message)$(if ($detail) {"`n  Graph response: $detail"})"
                    return
                }
                break
            }
            elseif ($overwrite -match '^[Nn]$') {
                Write-Host "Skipping remediation deployment." -ForegroundColor Yellow
                return
            }
            else { Write-Host "Please enter Y or N." -ForegroundColor Red }
        }
    }

    # Create remediation
    Write-Host ""
    Write-Host "Creating Proactive Remediation in Intune..." -ForegroundColor Yellow

    $scriptBody = @{
        "@odata.type"            = "#microsoft.graph.deviceHealthScript"
        displayName              = $scriptName
        description              = $description
        publisher                = $publisher
        runAs32Bit               = $false
        runAsAccount             = "system"
        enforceSignatureCheck    = $false
        detectionScriptContent   = $detectionB64
        remediationScriptContent = $remediationB64
        roleScopeTagIds          = @()
    } | ConvertTo-Json -Depth 5

    try {
        $created = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/deviceHealthScripts" `
            -Body $scriptBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "Remediation created: $($created.id)" -ForegroundColor Green
    }
    catch {
        $detail = Get-GraphErrorDetail $_.Exception
        Write-Error "Failed to create remediation: $($_.Exception.Message)$(if ($detail) {"`n  Graph response: $detail"})"
        return
    }

    $scriptId = $created.id

    # Assign to All Devices
    Write-Host "Assigning remediation to All Devices..." -ForegroundColor Yellow

    $assignBody = @{
        deviceHealthScriptAssignments = @(
            @{
                "@odata.type"        = "#microsoft.graph.deviceHealthScriptAssignment"
                target               = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
                runRemediationScript = $true
                runSchedule          = @{
                    "@odata.type" = "#microsoft.graph.deviceHealthScriptHourlySchedule"
                    interval      = 1
                }
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/deviceHealthScripts/$scriptId/assign" `
            -Body $assignBody -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Assigned to All Devices (runs every hour)." -ForegroundColor Green
    }
    catch {
        $detail = Get-GraphErrorDetail $_.Exception
        Write-Error "Failed to assign remediation: $($_.Exception.Message)$(if ($detail) {"`n  Graph response: $detail"})"
        return
    }
    Write-Host ""
    Write-Host "=== Proactive Remediation Deployed ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Script Name : $scriptName" -ForegroundColor Green
    Write-Host "Script ID   : $scriptId" -ForegroundColor Green
    Write-Host "Assignment  : All Devices (hourly)" -ForegroundColor Green
    Write-Host ""
}

#endregion

Export-ModuleMember -Function Invoke-DuoRemediationDeploy