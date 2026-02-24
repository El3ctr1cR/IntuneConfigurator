$printerExport = "single.printerExport"
$path = "C:\ProgramData\VWC\PrinterDeployment\"

If (!(test-path -PathType container $path)) {
  New-Item -ItemType Directory -Path $path
}

Copy-Item $printerExport -Destination $path

$finalPath = $path + $printerExport
C:\Windows\System32\spool\tools\PrintBrm.exe -R -F "$finalPath"