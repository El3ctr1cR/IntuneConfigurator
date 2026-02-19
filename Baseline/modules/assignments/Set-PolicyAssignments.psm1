function Set-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning policy '$PolicyName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            assignments = @(
                @{
                    id = ""
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned policy '$PolicyName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign policy '$PolicyName': $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign policy '$PolicyName': $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Set-PolicyAssignments