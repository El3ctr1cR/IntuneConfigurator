$printerName = "<REPLACE_WITH_PRINTER_NAME>"

try {
    $printer = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
    if ($printer) {
        Write-Output "Printer '$printerName' found."
        exit 0
    } else {
        Write-Output "Printer '$printerName' not found."
        exit 1
    }
}
catch {
    Write-Output "Error checking for printer '$printerName': $_"
    exit 1
}