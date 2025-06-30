function Set-AutopilotAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileId,
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning Autopilot profile '$ProfileName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            target = @{
                "@odata.type" = $odataType
            }
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned Autopilot profile '$ProfileName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign Autopilot profile '$ProfileName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign Autopilot profile '$ProfileName': $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Set-AutopilotAssignments