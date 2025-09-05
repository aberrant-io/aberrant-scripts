<#
.SYNOPSIS
    Creates a Jira ticket using the Jira REST API.

.DESCRIPTION
    This script takes a ticket name (summary) and a description as parameters and creates a new issue in a specified Jira project.

.PARAMETER TicketName
    The summary or title of the Jira ticket. This is a mandatory parameter.

.PARAMETER TicketDescription
    The description for the Jira ticket. This is a mandatory parameter.

.EXAMPLE
    .\create-jira-ticket.ps1 -TicketName "Fix the login button" -TicketDescription "The login button on the main page is not working when clicked. It needs to be investigated."

    This command will create a new Jira ticket with the specified summary and description.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the name/summary for the Jira ticket.")]
    [string]$TicketName,

    [Parameter(Mandatory = $true, HelpMessage = "Enter the description for the Jira ticket.")]
    [string]$TicketDescription
)

# --- USER CONFIGURATION ---
# IMPORTANT: Update these variables with your Jira instance details.

# Your full Jira URL (e.g., https://aberrant.atlassian.net)
$jiraUrl = "https://your-jira-url.atlassian.net"

# The key for your Jira project (e.g., "PROJ", "TEST")
$projectKey = "PROJ"

$email = "user@example.com"
$apiToken = "xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# The name of the issue type you want to create (e.g., "Task", "Story", "Bug", "Epic")
$issueTypeName = "Task"

# --- END OF USER CONFIGURATION ---

try {
    # Create the Base64 authentication header
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $email, $apiToken)))
    $headers = @{
        "Authorization" = "Basic $base64AuthInfo"
        "Content-Type"  = "application/json"
    }

    # Construct the JSON payload for the Jira API
    # The structure must match what the Jira API expects for creating an issue.
    $body = @{
        fields = @{
            project     = @{
                key = $projectKey
            }
            summary     = $TicketName
            description = $TicketDescription
            issuetype   = @{
                name = $issueTypeName
            }
        }
    } | ConvertTo-Json

    # Define the API endpoint for creating an issue
    $apiUrl = "$jiraUrl/rest/api/2/issue"
    
    # Call the Jira REST API
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body

    if ($response) {
        $ticketUrl = "$($jiraUrl)/browse/$($response.key)"

        # The manifest of the things this script will output
        # for uploading later
        $OutputManifest = @{
            Files = @()
            Links = @($ticketUrl)
        }
        # Return any output parameters this script has to pass on 
        # as defined by the contracts.config.json
        $OutputParameters = @{
            TicketNumber = $response.key
            TicketUrl = "$($jiraUrl)/browse/$($response.key)"
        }

        # Create the output wrapper object, wrapping the parameters and the Manifest
        $ScriptOutput = @{
            Parameters = $OutputParameters
            Manifest = $OutputManifest
        }

        # write the output as json
        Write-Output $ScriptOutput | ConvertTo-Json
    }
}
catch {
    Write-Error "An error occurred while creating the Jira ticket. $($_.Exception.Message)"

    # Attempt to get more detailed error info from the response
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $streamReader = New-Object System.IO.StreamReader($errorResponse)
        $errorBody = $streamReader.ReadToEnd()
        Write-Error "Jira API Response: $errorBody"
    }
}
