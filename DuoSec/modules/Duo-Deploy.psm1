# modules/Duo-Deploy.psm1
# Uploads the Duo Security Win32 app to Intune via Microsoft Graph.

#region - Helpers

function Get-IntuneWinMetadata {
    param([string]$SourceFile)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($SourceFile)
    try {
        $entry = $zip.Entries | Where-Object { $_.Name -eq "Detection.xml" } | Select-Object -First 1
        if (-not $entry) { throw "Detection.xml not found inside $SourceFile" }
        $reader  = New-Object System.IO.StreamReader($entry.Open())
        $xmlText = $reader.ReadToEnd()
        $reader.Close()
        [xml]$xml = $xmlText
        return $xml.ApplicationInfo
    }
    finally { $zip.Dispose() }
}

function Get-IntuneWinInnerFile {
    param(
        [string]$SourceFile,
        [string]$FileName
    )

    $directory = [System.IO.Path]::GetDirectoryName($SourceFile)
    $outputDir = Join-Path $directory "win32"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($SourceFile)
    try {
        $entry = $zip.Entries | Where-Object { $_.Name -eq $FileName } | Select-Object -First 1
        if (-not $entry) { throw "Inner file '$FileName' not found inside $SourceFile" }
        $destPath = Join-Path $outputDir $FileName
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
        return $destPath
    }
    finally { $zip.Dispose() }
}

function Invoke-AzureBlobPut {
    # Raw PUT via HttpClient — bypasses PS7.4 UTF-8 encoding that causes commitFileFailed
    param(
        [string]$Uri,
        [byte[]]$Body,
        [string]$ContentType = "application/octet-stream",
        [hashtable]$ExtraHeaders = @{}
    )

    $client = [System.Net.Http.HttpClient]::new()
    try {
        $content = [System.Net.Http.ByteArrayContent]::new($Body)
        $content.Headers.Remove("Content-Type") | Out-Null
        $content.Headers.Add("Content-Type", $ContentType)

        foreach ($kv in $ExtraHeaders.GetEnumerator()) {
            $client.DefaultRequestHeaders.TryAddWithoutValidation($kv.Key, $kv.Value) | Out-Null
        }

        $response = $client.PutAsync($Uri, $content).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "Azure Blob PUT failed ($($response.StatusCode)): $body"
        }
    }
    finally { $client.Dispose() }
}

function Send-AzureStorageChunk {
    param([string]$SasUri, [string]$BlockId, [byte[]]$Body)

    Invoke-AzureBlobPut -Uri "$SasUri&comp=block&blockid=$BlockId" -Body $Body `
        -ContentType "application/octet-stream" `
        -ExtraHeaders @{ "x-ms-blob-type" = "BlockBlob" }
}

function Complete-AzureStorageUpload {
    param([string]$SasUri, [string[]]$BlockIds)

    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
    foreach ($id in $BlockIds) { $xml += "<Latest>$id</Latest>" }
    $xml += '</BlockList>'

    Invoke-AzureBlobPut -Uri "$SasUri&comp=blocklist" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($xml)) `
        -ContentType "application/xml"
}

function Invoke-AzureStorageUpload {
    param([string]$SasUri, [string]$FilePath)

    $chunkSizeBytes = 6 * 1024 * 1024
    $fileSize       = (Get-Item $FilePath).Length
    $chunks         = [Math]::Ceiling($fileSize / $chunkSizeBytes)
    $reader         = New-Object System.IO.BinaryReader(
                          [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open))
    $reader.BaseStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    $blockIds = @()

    try {
        for ($chunk = 0; $chunk -lt $chunks; $chunk++) {
            $blockId  = [System.Convert]::ToBase64String(
                            [System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")))
            $blockIds += $blockId

            $length = [Math]::Min($chunkSizeBytes, $fileSize - ($chunk * $chunkSizeBytes))
            $bytes  = $reader.ReadBytes($length)

            Send-AzureStorageChunk -SasUri $SasUri -BlockId $blockId -Body $bytes

            $current = $chunk + 1
            $pct     = [math]::Round(($current / $chunks) * 100)
            Write-Host "`r  Uploading... $pct% ($current of $chunks chunks)" -NoNewline -ForegroundColor Yellow
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }

    Write-Host "`r  Upload complete.                              " -ForegroundColor Green
    Complete-AzureStorageUpload -SasUri $SasUri -BlockIds $blockIds
}

function Wait-FileProcessing {
    param([string]$FileUri, [string]$Stage)

    $successState = "${Stage}Success"
    $pendingState = "${Stage}Pending"
    $maxAttempts  = 60
    $waitSeconds  = 5

    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $FileUri

        if ($file.uploadState -eq $successState) { return $file }
        if ($file.uploadState -ne $pendingState) {
            throw "File processing reached unexpected state: $($file.uploadState)"
        }

        Start-Sleep -Seconds $waitSeconds
        Write-Host "`r  Waiting... ($($i * $waitSeconds) s)" -NoNewline -ForegroundColor Yellow
    }

    throw "File processing timed out (stage: $Stage)"
}

#endregion

#region - Main deploy function

function Invoke-DuoDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IntuneWinFilePath,

        [Parameter(Mandatory = $true)]
        [string]$InstallerFileName,     # duo-win-login.exe

        [Parameter(Mandatory = $true)]
        [string]$InstallerFilePath,     # full path to downloaded .exe

        [Parameter(Mandatory = $true)]
        [hashtable]$DuoConfig           # IKEY, SKEY, HOST
    )

    Write-Host ""
    Write-Host "=== Deploying to Intune ===" -ForegroundColor Cyan
    Write-Host ""

    $LOBType      = "microsoft.graph.win32LobApp"
    $appName      = "Duo Security"
    $publisher    = "DUO Security Inc."
    $installCmd   = "`"$InstallerFileName`" /S /V`"/qn IKEY=`"$($DuoConfig.IKEY)`" SKEY=`"$($DuoConfig.SKEY)`" HOST=`"$($DuoConfig.HOST)`" AUTOPUSH=`"#1`" UAC_PROTECTMODE=`"#2`" USERNAMEFORMAT=`"#2`" FAILOPEN=`"#0`" SMARTCARD=`"#0`" ENABLEOFFLINE=`"#1`" RDPONLY=`"#0`"`""
    $uninstallCmd = "`"$InstallerFileName`" /x /s /v/qn"
    $description  = "Duo Security Windows Logon - deployed via IntuneConfigurator"
    $baseUri      = "https://graph.microsoft.com/beta/deviceAppManagement"

    Write-Host "App name       : $appName" -ForegroundColor Gray
    Write-Host "Publisher      : $publisher" -ForegroundColor Gray
    Write-Host "Install cmd    : $installCmd" -ForegroundColor Gray
    Write-Host "Uninstall cmd  : $uninstallCmd" -ForegroundColor Gray
    Write-Host ""

    # Read Detection.xml
    Write-Host "Reading .intunewin metadata..." -ForegroundColor Yellow
    try {
        $detXml = Get-IntuneWinMetadata -SourceFile $IntuneWinFilePath
    }
    catch {
        Write-Error "Failed to read metadata: $($_.Exception.Message)"
        return
    }

    $encInfo       = $detXml.EncryptionInfo
    $setupFileName = $detXml.SetupFile
    $innerFileName = $detXml.FileName
    $unencSize     = [long]$detXml.UnencryptedContentSize

    Write-Host "Setup file     : $setupFileName" -ForegroundColor Green
    Write-Host "Unencrypted    : $([math]::Round($unencSize/1MB,2)) MB" -ForegroundColor Green

    # Extract inner encrypted file
    Write-Host "Extracting inner encrypted file..." -ForegroundColor Yellow
    try {
        $innerFilePath = Get-IntuneWinInnerFile -SourceFile $IntuneWinFilePath -FileName "IntunePackage.intunewin"
    }
    catch {
        Write-Error "Failed to extract inner file: $($_.Exception.Message)"
        return
    }
    $encSize = (Get-Item $innerFilePath).Length
    Write-Host "Encrypted      : $([math]::Round($encSize/1MB,2)) MB" -ForegroundColor Green

    # Check for existing app
    Write-Host "Checking if app already exists in Intune..." -ForegroundColor Yellow

    try {
        $existingResp = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=displayName eq '$appName'" `
            -ErrorAction Stop
        $existingApps = $existingResp.value
    }
    catch {
        Write-Error "Failed to query existing apps: $($_.Exception.Message)"
        return
    }

    if ($existingApps -and $existingApps.Count -gt 0) {
        Write-Host ""
        Write-Host "An app named '$appName' already exists in Intune." -ForegroundColor Yellow
        while ($true) {
            Write-Host "Do you want to overwrite it? (Y/N): " -ForegroundColor Yellow -NoNewline
            $overwrite = Read-Host
            if ($overwrite -match '^[Yy]$') {
                foreach ($app in $existingApps) {
                    try {
                        Invoke-MgGraphRequest -Method DELETE `
                            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)" `
                            -ErrorAction Stop | Out-Null
                        Write-Host "Removed existing app: $($app.id)" -ForegroundColor Gray
                    }
                    catch {
                        Write-Error "Failed to remove existing app: $($_.Exception.Message)"
                        return
                    }
                }
                break
            }
            elseif ($overwrite -match '^[Nn]$') {
                Write-Host "Skipping deployment." -ForegroundColor Yellow
                Remove-Item $innerFilePath -Force -ErrorAction SilentlyContinue
                return
            }
            else { Write-Host "Please enter Y or N." -ForegroundColor Red }
        }
    }

    # Create app shell
    Write-Host ""
    Write-Host "Creating Win32 app in Intune..." -ForegroundColor Yellow

    $appBody = @{
        "@odata.type"        = "#microsoft.graph.win32LobApp"
        displayName          = $appName
        description          = $description
        publisher            = $publisher
        fileName             = $innerFileName
        setupFilePath        = $setupFileName
        installCommandLine   = $installCmd
        uninstallCommandLine = $uninstallCmd
        installExperience    = @{
            runAsAccount          = "system"
            deviceRestartBehavior = "suppress"
        }
        minimumSupportedOperatingSystem = @{ "v10_1607" = $true }
        msiInformation       = $null
        rules                = @(
            @{
                "@odata.type"        = "#microsoft.graph.win32LobAppFileSystemRule"
                ruleType             = "detection"
                check32BitOn64System = $false
                operationType        = "exists"
                operator             = "notConfigured"
                comparisonValue      = $null
                path                 = 'C:\Program Files\Duo Security\WindowsLogon\'
                fileOrFolderName     = "DuoCredFilter.dll"
            }
        )
        returnCodes          = @(
            @{ returnCode = 0;    type = "success" },
            @{ returnCode = 1707; type = "success" },
            @{ returnCode = 3010; type = "softReboot" },
            @{ returnCode = 1641; type = "hardReboot" },
            @{ returnCode = 1618; type = "retry" }
        )
        isFeatured            = $false
        runAs32bit            = $false
        notes                 = ""
        owner                 = ""
        developer             = ""
        informationUrl        = $null
        privacyInformationUrl = $null
    } | ConvertTo-Json -Depth 10

    try {
        $createdApp = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/mobileApps" `
            -Body $appBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "App created: $($createdApp.id)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create app: $($_.Exception.Message)"
        Remove-Item $innerFilePath -Force -ErrorAction SilentlyContinue
        return
    }

    $appId = $createdApp.id

    # Create content version
    Write-Host "Creating content version..." -ForegroundColor Yellow
    try {
        $contentVersion = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/mobileApps/$appId/$LOBType/contentVersions" `
            -Body "{}" -ContentType "application/json" -ErrorAction Stop
        Write-Host "Content version: $($contentVersion.id)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create content version: $($_.Exception.Message)"
        return
    }

    $contentVersionId = $contentVersion.id

    # Create file entry
    Write-Host "Creating file entry..." -ForegroundColor Yellow

    $fileBody = @{
        "@odata.type" = "#microsoft.graph.mobileAppContentFile"
        name          = $innerFileName
        size          = $unencSize
        sizeEncrypted = $encSize
        manifest      = $null
        isDependency  = $false
    } | ConvertTo-Json -Depth 5

    Write-Host "  name          : $innerFileName" -ForegroundColor DarkGray
    Write-Host "  size          : $([math]::Round($unencSize/1MB,2)) MB" -ForegroundColor DarkGray
    Write-Host "  sizeEncrypted : $([math]::Round($encSize/1MB,2)) MB" -ForegroundColor DarkGray

    try {
        $fileEntry = Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files" `
            -Body $fileBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "File entry created: $($fileEntry.id)" -ForegroundColor Green
    }
    catch {
        $detail = $null; try { $detail = $_.ErrorDetails.Message } catch {}
        Write-Error "Failed to create file entry: $($_.Exception.Message)$(if ($detail) {"`n  $detail"})"
        return
    }

    $fileId  = $fileEntry.id
    $fileUri = "$baseUri/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId"

    # Wait for Azure Storage URI
    Write-Host "Waiting for Azure Storage upload URI..." -ForegroundColor Yellow
    try {
        $fileReady = Wait-FileProcessing -FileUri $fileUri -Stage "AzureStorageUriRequest"
    }
    catch {
        Write-Error $_.Exception.Message
        return
    }
    Write-Host "`r  Azure Storage URI ready.   " -ForegroundColor Green

    # Upload inner encrypted file
    Write-Host "Uploading package to Azure Storage..." -ForegroundColor Yellow
    try {
        Invoke-AzureStorageUpload -SasUri $fileReady.azureStorageUri -FilePath $innerFilePath
    }
    catch {
        Write-Error "Upload failed: $($_.Exception.Message)"
        return
    }
    finally {
        Remove-Item $innerFilePath -Force -ErrorAction SilentlyContinue
        $win32Dir = [System.IO.Path]::GetDirectoryName($innerFilePath)
        if ((Get-ChildItem $win32Dir -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $win32Dir -Force -ErrorAction SilentlyContinue
        }
    }

    # Commit file
    Write-Host "Committing file..." -ForegroundColor Yellow

    $commitBody = @{
        fileEncryptionInfo = @{
            encryptionKey        = $encInfo.EncryptionKey
            initializationVector = $encInfo.InitializationVector
            mac                  = $encInfo.Mac
            macKey               = $encInfo.MacKey
            profileIdentifier    = "ProfileVersion1"
            fileDigest           = $encInfo.FileDigest
            fileDigestAlgorithm  = $encInfo.FileDigestAlgorithm
        }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "$fileUri/commit" `
            -Body $commitBody -ContentType "application/json" -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to send commit: $($_.Exception.Message)"
        return
    }

    try {
        Wait-FileProcessing -FileUri $fileUri -Stage "CommitFile" | Out-Null
    }
    catch {
        Write-Error $_.Exception.Message
        return
    }
    Write-Host "`r  File committed successfully.   " -ForegroundColor Green

    # Finalise app
    Write-Host "Finalizing app..." -ForegroundColor Yellow

    try {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "$baseUri/mobileApps/$appId" `
            -Body (@{ "@odata.type" = "#microsoft.graph.win32LobApp"; committedContentVersion = $contentVersionId } | ConvertTo-Json -Depth 3) `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to finalize app: $($_.Exception.Message)"
        return
    }

    # Assign to All Devices
    Write-Host "Assigning app to All Devices..." -ForegroundColor Yellow

    $assignBody = @{
        mobileAppAssignments = @(
            @{
                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                target        = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
                intent        = "required"
                settings      = @{
                    "@odata.type"                = "#microsoft.graph.win32LobAppAssignmentSettings"
                    notifications                = "showAll"
                    restartSettings              = $null
                    installTimeSettings          = $null
                    deliveryOptimizationPriority = "notConfigured"
                }
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "$baseUri/mobileApps/$appId/assign" `
            -Body $assignBody -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Assigned to All Devices (Required)." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to assign app: $($_.Exception.Message)"
        return
    }

    Write-Host ""
    Write-Host "=== Deployment Complete ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "App Name    : $appName" -ForegroundColor Green
    Write-Host "App ID      : $appId" -ForegroundColor Green
    Write-Host "Assignment  : All Devices (Required)" -ForegroundColor Green
    Write-Host ""
}

#endregion

Export-ModuleMember -Function Invoke-DuoDeploy
