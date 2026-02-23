# modules/Duo-Download.psm1
# Downloads the Duo Security Windows Logon installer to ./build/

$DuoDownloadUrl  = "https://dl.duosecurity.com/duo-win-login-latest.exe"
$DuoInstallerName = "duo-win-login.exe"

function Invoke-DuoDownload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildPath
    )

    Write-Host ""
    Write-Host "=== Downloading Duo Security Installer ===" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $BuildPath)) {
        try {
            New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
            Write-Host "Created build folder: $BuildPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to create build folder: $($_.Exception.Message)"
            return $null
        }
    }

    $destinationPath = Join-Path $BuildPath $DuoInstallerName

    if (Test-Path $destinationPath) {
        Write-Host "Installer already exists, skipping download." -ForegroundColor Yellow
        Write-Host "File: $destinationPath" -ForegroundColor Gray
        Write-Host ""
        return $destinationPath
    }

    Write-Host "Downloading from:" -ForegroundColor Gray
    Write-Host "  $DuoDownloadUrl" -ForegroundColor DarkGray
    Write-Host "Saving to:" -ForegroundColor Gray
    Write-Host "  $destinationPath" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "IntuneConfigurator/1.0")
        $wc.DownloadFile($DuoDownloadUrl, $destinationPath)
        $wc.Dispose()
        Write-Host "  Download complete." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download Duo installer: $($_.Exception.Message)"
        if (Test-Path $destinationPath) { Remove-Item $destinationPath -Force -ErrorAction SilentlyContinue }
        return $null
    }

    if (-not (Test-Path $destinationPath) -or (Get-Item $destinationPath).Length -eq 0) {
        Write-Error "Downloaded file is missing or empty: $destinationPath"
        return $null
    }

    $sizeMB = [math]::Round((Get-Item $destinationPath).Length / 1MB, 2)
    Write-Host "  Size: $sizeMB MB" -ForegroundColor Gray
    Write-Host ""

    return $destinationPath
}

Export-ModuleMember -Function Invoke-DuoDownload

function Get-DuoConfig {
    Write-Host "=== Duo Security Configuration ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Enter your Duo Security integration credentials." -ForegroundColor Gray
    Write-Host "These can be found in the Duo Admin Panel under Applications > Windows Logon." -ForegroundColor DarkGray
    Write-Host ""

    # IKEY
    while ($true) {
        Write-Host "Integration Key (IKEY): " -ForegroundColor Yellow -NoNewline
        $ikey = Read-Host
        if (-not [string]::IsNullOrWhiteSpace($ikey)) { break }
        Write-Host "IKEY cannot be empty." -ForegroundColor Red
    }

    # SKEY
    while ($true) {
        Write-Host "Secret Key (SKEY)     : " -ForegroundColor Yellow -NoNewline
        $skey = Read-Host
        if (-not [string]::IsNullOrWhiteSpace($skey)) { break }
        Write-Host "SKEY cannot be empty." -ForegroundColor Red
    }

    # HOST
    while ($true) {
        Write-Host "API Hostname (HOST)   : " -ForegroundColor Yellow -NoNewline
        $host_ = Read-Host
        if (-not [string]::IsNullOrWhiteSpace($host_)) { break }
        Write-Host "HOST cannot be empty." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "-------------------------------------" -ForegroundColor DarkGray
    Write-Host "IKEY : " -NoNewline -ForegroundColor White
    Write-Host $ikey -ForegroundColor Cyan
    Write-Host "SKEY : " -NoNewline -ForegroundColor White
    Write-Host ($skey.Substring(0, [Math]::Min(4, $skey.Length)) + "****") -ForegroundColor Cyan
    Write-Host "HOST : " -NoNewline -ForegroundColor White
    Write-Host $host_ -ForegroundColor Cyan
    Write-Host "-------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        Write-Host "Is this correct? (Y/N): " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -match '^[Yy]$') {
            Write-Host ""
            return @{
                IKEY = $ikey
                SKEY = $skey
                HOST = $host_
            }
        }
        elseif ($confirm -match '^[Nn]$') {
            Write-Host ""
            return Get-DuoConfig
        }
        else {
            Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
        }
    }
}

Export-ModuleMember -Function Get-DuoConfig