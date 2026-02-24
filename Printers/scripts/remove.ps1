$printerExport="single.printerExport"
$path="C:\ProgramData\VWC\PrinterDeployment\"

Remove-Printer "<REPLACE_WITH_PRINTER_NAME>"

$finalPath=$path+$printerExport
Remove-Item -Recurse -Force $finalPath