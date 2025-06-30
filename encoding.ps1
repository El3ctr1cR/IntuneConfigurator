# Set the root folder path where your modules are located
$rootPath = "C:\Users\Ruben\Documents\.respository\IntuneConfigurator"  # <-- Change this

# Helper function to detect if a file has a UTF-8 BOM
function Has-BOM {
    param ([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    } catch {
        Write-Warning "Failed to read $Path : $_"
        return $false
    }
}

# Get all .ps1 and .psm1 files recursively
$files = Get-ChildItem -Path $rootPath -Recurse -Include *.ps1, *.psm1 -File -ErrorAction SilentlyContinue

foreach ($file in $files) {
    if (-not (Has-BOM -Path $file.FullName)) {
        Write-Host "Converting: $($file.FullName)" -ForegroundColor Yellow

        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.UTF8Encoding]::new($true))
        } catch {
            Write-Warning "Failed to convert $($file.FullName): $_"
        }
    } else {
        Write-Host "Skipping (already UTF-8 BOM): $($file.FullName)" -ForegroundColor DarkGray
    }
}
