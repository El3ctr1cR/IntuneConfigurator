function Test-DeviceNameTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template
    )
    
    if ($Template.Length -gt 15) {
        Write-Error "Device name template must be 15 characters or less (current length: $($Template.Length))."
        return $false
    }
    
    if ($Template -match '\s') {
        Write-Error "Device name template cannot contain spaces."
        return $false
    }
    
    if ($Template -match '^[0-9]+$') {
        Write-Error "Device name template cannot consist only of numbers."
        return $false
    }
    
    if ($Template -notmatch '^[a-zA-Z0-9\-]+(%SERIAL%|%RAND:\d+%)?$') {
        Write-Error "Device name template can only contain letters (a-z, A-Z), numbers (0-9), hyphens, %SERIAL%, or %RAND:x% (where x is a number)."
        return $false
    }
    
    return $true
}

Export-ModuleMember -Function Test-DeviceNameTemplate