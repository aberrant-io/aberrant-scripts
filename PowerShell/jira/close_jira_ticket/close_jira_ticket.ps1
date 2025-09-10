<#
.SYNOPSIS
    Closes a Jira ticket using the Jira REST API.

.DESCRIPTION
    This script takes a ticket number as a parameter and transitions the ticket to a closed state in Jira.

.PARAMETER TicketNumber
    The ticket number/key of the Jira ticket to close (e.g., "PROJ-123"). This is a mandatory parameter.

.EXAMPLE
    .\close-jira-ticket.ps1 -TicketNumber "PROJ-123"

    This command will close the specified Jira ticket by transitioning it to a closed state.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the ticket number/key for the Jira ticket to close.")]
    [string]$TicketNumber
)

# --- USER CONFIGURATION ---
# IMPORTANT: Update these variables with your Jira instance details.

# Your full Jira URL (e.g., https://aberrant.atlassian.net)
$jiraUrl = "https://your-jira-url.atlassian.net"

$email = "user@example.com"
$apiToken = "xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# The name of the transition to close the ticket (e.g., "Done", "Closed", "Resolved")
# You may need to check your Jira workflow to find the correct transition name
$closeTransitionName = "Done"

# --- END OF USER CONFIGURATION ---

try {
    # Create the Base64 authentication header
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $email, $apiToken)))
    $headers = @{
        "Authorization" = "Basic $base64AuthInfo"
        "Content-Type"  = "application/json"
    }

    # First, get the available transitions for this ticket
    $transitionsUrl = "$jiraUrl/rest/api/2/issue/$TicketNumber/transitions"
    $transitionsResponse = Invoke-RestMethod -Uri $transitionsUrl -Method Get -Headers $headers

    # Find the transition ID for the close transition
    $closeTransition = $transitionsResponse.transitions | Where-Object { $_.name -eq $closeTransitionName }
    
    if (-not $closeTransition) {
        Write-Error "Transition '$closeTransitionName' not found for ticket $TicketNumber. Available transitions: $($transitionsResponse.transitions.name -join ', ')"
        exit 1
    }

    # Construct the JSON payload for the Jira API transition
    $body = @{
        transition = @{
            id = $closeTransition.id
        }
    } | ConvertTo-Json

    # Define the API endpoint for transitioning an issue
    $apiUrl = "$jiraUrl/rest/api/2/issue/$TicketNumber/transitions"
    
    # Call the Jira REST API to transition the ticket
    Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body

    $ticketUrl = "$($jiraUrl)/browse/$TicketNumber"

    # The manifest of the things this script will output
    # for uploading later
    $OutputManifest = @{
        Files = @()
        Links = @($ticketUrl)
    }
    # Return any output parameters this script has to pass on 
    # as defined by the contracts.config.json
    $OutputParameters = @{
        ClosedTicketNumber = $TicketNumber
        ClosedTicketUrl = $ticketUrl
    }

    # Create the output wrapper object, wrapping the parameters and the Manifest
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest = $OutputManifest
    }

    # write the output as json
    Write-Output $ScriptOutput | ConvertTo-Json
    
}
catch {
    Write-Error "An error occurred while closing the Jira ticket. $($_.Exception.Message)"

    # Attempt to get more detailed error info from the response
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $streamReader = New-Object System.IO.StreamReader($errorResponse)
        $errorBody = $streamReader.ReadToEnd()
        Write-Error "Jira API Response: $errorBody"
    }
}
