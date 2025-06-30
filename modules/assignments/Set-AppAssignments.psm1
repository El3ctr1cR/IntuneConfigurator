function Set-AppAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentType
    )
    
    try {
        Write-Host "Assigning application '$AppName' to $AssignmentType..." -ForegroundColor Yellow
        
        $odataType = if ($AssignmentType -eq "devices") { 
            "#microsoft.graph.allDevicesAssignmentTarget"
        } else { 
            "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        
        $assignmentBody = @{
            mobileAppAssignments = @(
                @{
                    "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                    intent = "Required"
                    target = @{
                        "@odata.type" = $odataType
                    }
                }
            )
        }
        
        $jsonBody = $assignmentBody | ConvertTo-Json -Depth 10
        
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$AppId')/assign"
        
        try {
            $response = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "✓ Successfully assigned application '$AppName' to $AssignmentType" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to assign application '$AppName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                Write-Error "Error details: $errorContent"
            }
            return $false
        }
    }
    catch {
        Write-Error "Failed to assign application '$AppName': $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Set-AppAssignments