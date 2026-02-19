function Remove-ReadOnlyProperties {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$JsonObject
    )
    
    $propertiesToRemove = @(
        '@odata.context',
        '@odata.id',
        '@odata.editLink',
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'version',
        'assignments',
        'assignedDevices',
        'roleScopeTagIds',
        'supportsScopeTags',
        'deviceEnrollmentConfigurationType'
    )
    
    $cleanObject = @{}
    
    $JsonObject.PSObject.Properties | ForEach-Object {
        $propertyName = $_.Name
        $propertyValue = $_.Value
        
        if ($propertyName -in $propertiesToRemove) {
            return
        }
        
        if ($propertyName.StartsWith('@') -and $propertyName -ne '@odata.type') {
            return
        }
        
        if ($propertyValue -is [PSCustomObject]) {
            $cleanObject[$propertyName] = Remove-ReadOnlyProperties -JsonObject $propertyValue
        }
        elseif ($propertyValue -is [Array]) {
            $cleanArray = @()
            foreach ($item in $propertyValue) {
                if ($item -is [PSCustomObject]) {
                    $cleanArray += Remove-ReadOnlyProperties -JsonObject $item
                }
                else {
                    $cleanArray += $item
                }
            }
            $cleanObject[$propertyName] = $cleanArray
        }
        else {
            $cleanObject[$propertyName] = $propertyValue
        }
    }
    
    return [PSCustomObject]$cleanObject
}

Export-ModuleMember -Function Remove-ReadOnlyProperties