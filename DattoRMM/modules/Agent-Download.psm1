# modules/Agent-Download.psm1
# Downloads the Datto RMM agent installer to ./build/

function Get-AgentLink {
    Write-Host "=== Datto RMM Agent Configuration ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Enter the Datto RMM Agent download link for your tenant." -ForegroundColor Gray
    Write-Host "Example: https://xxxxxxx.rmm.datto.com/download-agent/windows/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        Write-Host "Agent link: " -ForegroundColor Yellow -NoNewline
        $link = Read-Host

        if ([string]::IsNullOrWhiteSpace($link)) {
            Write-Host "No link entered. Exiting." -ForegroundColor Yellow
            return $null
        }

        # Basic URL validation
        if ($link -notmatch '^https?://') {
            Write-Host "Invalid URL. Please enter a valid https:// link." -ForegroundColor Red
            Write-Host ""
            continue
        }

        # Confirm
        Write-Host ""
        Write-Host "Agent link: " -NoNewline -ForegroundColor White
        Write-Host $link -ForegroundColor Cyan
        Write-Host ""

        while ($true) {
            Write-Host "Is this correct? (Y/N): " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host

            if ($confirm -match '^[Yy]$') {
                Write-Host ""
                return $link
            }
            elseif ($confirm -match '^[Nn]$') {
                Write-Host ""
                break
            }
            else {
                Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
            }
        }
    }
}

function Invoke-AgentDownload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentLink,

        [Parameter(Mandatory = $true)]
        [string]$BuildPath
    )

    Write-Host ""
    Write-Host "=== Downloading Datto RMM Agent ===" -ForegroundColor Cyan
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

    try {
        $uri       = [System.Uri]$AgentLink
        $segments  = $uri.AbsolutePath.TrimEnd('/').Split('/')
        $lastSeg   = $segments[-1]
        $agentFileName = "DattoRMMAgent-$lastSeg.exe"
    }
    catch {
        $agentFileName = "DattoRMMAgent.exe"
    }

    $destinationPath = Join-Path $BuildPath $agentFileName

    if (Test-Path $destinationPath) {
        Write-Host "Agent installer already exists, skipping download." -ForegroundColor Yellow
        Write-Host "File: $destinationPath" -ForegroundColor Gray
        Write-Host ""
        return $destinationPath
    }

    Write-Host "Downloading from:" -ForegroundColor Gray
    Write-Host "  $AgentLink" -ForegroundColor DarkGray
    Write-Host "Saving to:" -ForegroundColor Gray
    Write-Host "  $destinationPath" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $webClient = New-Object System.Net.WebClient
        $progressHandler = {
            param($sender, $e)
            $pct = $e.ProgressPercentage
            Write-Host "`r  Downloading... $pct%" -NoNewline -ForegroundColor Yellow
        }
        $webClient.add_DownloadProgressChanged($progressHandler)
        $webClient.DownloadFile($AgentLink, $destinationPath)
        Write-Host "`r  Download complete.          " -ForegroundColor Green
    }
    catch {
        # Fallback to Invoke-WebRequest if WebClient fails
        Write-Host "`r  WebClient failed, retrying with Invoke-WebRequest..." -ForegroundColor Yellow
        try {
            Invoke-WebRequest -Uri $AgentLink -OutFile $destinationPath -UseBasicParsing -ErrorAction Stop
            Write-Host "  Download complete." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to download agent: $($_.Exception.Message)"
            return $null
        }
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

Export-ModuleMember -Function Invoke-AgentDownload
Export-ModuleMember -Function Get-AgentLink