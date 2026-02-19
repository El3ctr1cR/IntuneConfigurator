function Set-ESPAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileId,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning ESP profile '$ProfileName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            enrollmentConfigurationAssignments = @(
                @{
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations('$ProfileId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned ESP profile '$ProfileName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign ESP profile '$ProfileName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign ESP profile '$ProfileName': $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Set-ESPAssignments