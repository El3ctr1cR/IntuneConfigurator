# modules/IntuneWin-Build.psm1
# Wraps IntuneWinAppUtil.exe to produce a .intunewin package

$IntuneWinAppUtilUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
$IntuneWinAppUtilName = "IntuneWinAppUtil.exe"

function Assert-IntuneWinAppUtil {
    <#
        .SYNOPSIS
            Ensures IntuneWinAppUtil.exe is available, downloading it if needed.
        .OUTPUTS
            $true if available, $false otherwise.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $toolPath = Join-Path $RootPath "tools"
    $exePath  = Join-Path $toolPath $IntuneWinAppUtilName

    if (Test-Path $exePath) {
        Write-Host "IntuneWinAppUtil.exe found at: $exePath" -ForegroundColor Green
        return $true
    }

    Write-Host ""
    Write-Host "=== IntuneWinAppUtil Setup ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IntuneWinAppUtil.exe was not found." -ForegroundColor Yellow
    Write-Host "It will be downloaded from the official Microsoft GitHub repository." -ForegroundColor Gray
    Write-Host ""

    try {
        if (-not (Test-Path $toolPath)) {
            New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
        }

        Write-Host "Downloading IntuneWinAppUtil.exe..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $IntuneWinAppUtilUrl -OutFile $exePath -UseBasicParsing -ErrorAction Stop
        Write-Host "Downloaded successfully: $exePath" -ForegroundColor Green
        Write-Host ""
        return $true
    }
    catch {
        Write-Error "Failed to download IntuneWinAppUtil.exe: $($_.Exception.Message)"
        Write-Host "Please download it manually from:" -ForegroundColor Yellow
        Write-Host "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool" -ForegroundColor DarkGray
        Write-Host "and place it in: $toolPath" -ForegroundColor DarkGray
        return $false
    }
}

function Invoke-IntuneWinBuild {
    <#
        .SYNOPSIS
            Calls IntuneWinAppUtil.exe to package the agent installer.
        .OUTPUTS
            Full path to the generated .intunewin file, or $null on failure.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentFilePath,

        [Parameter(Mandatory = $true)]
        [string]$BuildPath,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    Write-Host ""
    Write-Host "=== Building .intunewin Package ===" -ForegroundColor Cyan
    Write-Host ""

    $toolPath    = Join-Path $RootPath "tools"
    $exePath     = Join-Path $toolPath $IntuneWinAppUtilName
    $agentDir    = [System.IO.Path]::GetDirectoryName($AgentFilePath)
    $agentName   = [System.IO.Path]::GetFileName($AgentFilePath)
    $outputDir   = Join-Path $BuildPath "intunewin"

    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # IntuneWinAppUtil produces <setupfile>.intunewin in the output folder
    $expectedOutput = Join-Path $outputDir ($agentName -replace '\.exe$', '.intunewin')

    if (Test-Path $expectedOutput) {
        Write-Host "Package already exists, skipping build." -ForegroundColor Yellow
        Write-Host "File: $expectedOutput" -ForegroundColor Gray
        Write-Host ""
        return $expectedOutput
    }

    Write-Host "Source folder : $agentDir" -ForegroundColor Gray
    Write-Host "Setup file    : $agentName" -ForegroundColor Gray
    Write-Host "Output folder : $outputDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Running IntuneWinAppUtil..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $proc = Start-Process -FilePath $exePath `
            -ArgumentList "-c `"$agentDir`" -s `"$agentName`" -o `"$outputDir`" -q" `
            -Wait -PassThru -NoNewWindow

        if ($proc.ExitCode -ne 0) {
            Write-Error "IntuneWinAppUtil exited with code $($proc.ExitCode)"
            return $null
        }
    }
    catch {
        Write-Error "Failed to run IntuneWinAppUtil: $($_.Exception.Message)"
        return $null
    }

    if (-not (Test-Path $expectedOutput)) {
        Write-Error "Expected .intunewin file not found after build: $expectedOutput"
        return $null
    }

    $sizeMB = [math]::Round((Get-Item $expectedOutput).Length / 1MB, 2)
    Write-Host "Package built successfully." -ForegroundColor Green
    Write-Host "File : $expectedOutput" -ForegroundColor Gray
    Write-Host "Size : $sizeMB MB" -ForegroundColor Gray
    Write-Host ""

    return $expectedOutput
}

Export-ModuleMember -Function Assert-IntuneWinAppUtil, Invoke-IntuneWinBuild
