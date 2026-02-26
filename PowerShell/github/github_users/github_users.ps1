<#
.SYNOPSIS
    Retrieves all users who have contributed to a specified GitHub repository and saves the information to a CSV file. Requires a GitHub personal access token to be configured.

.DESCRIPTION
    This script takes the repository owner and name as parameters, fetches all contributors and collaborators using the GitHub CLI, and exports their details to CSV files in the Output directory.

.PARAMETER owner
    The owner of the GitHub repository (user or organization). This is a mandatory parameter.

.PARAMETER repo
    The name of the GitHub repository. This is a mandatory parameter.

.EXAMPLE
    .\github_users.ps1 -owner "octocat" -repo "Hello-World"

    This command will retrieve all users who have contributed to the "Hello-World" repository owned by "octocat" and save the information to GitHubUsers.csv and GitHubCollaborators.csv in the Output directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$owner, # the repository owner (user or organization)
    [Parameter(Mandatory=$true)]
    [string]$repo # the repository name
)

if (-not $owner) {
    Write-Error "The owner parameter is required"
    exit 1
}
if(-not $repo){
    Write-Error "The repo parameter is required"
    exit 1
}

$GitHubToken = "GITHUB_PERSONAL_ACCESS_TOKEN_HERE" # or use $env:GITHUB_TOKEN

if (-not $GitHubToken) {
    Write-Error "GitHubToken not found, either hard coded or via GITHUB_TOKEN environment variable. Please set it to a valid GitHub Personal Access Token."
    exit 1
}

# Define Headers once
$Headers = @{
    "Authorization" = "token $GitHubToken"
    "Accept"        = "application/vnd.github.v3+json"
}

$RootFolder = Split-Path -Parent $PSScriptRoot
$OutputFolder = Join-Path -Path $RootFolder -ChildPath "Output"

# check if output exists
if (-not (Test-Path -Path $OutputFolder)) {
    # This throws a System.IO.DirectoryNotFoundException
    throw [System.IO.DirectoryNotFoundException]::new("CRITICAL: The Output directory does not exist at: $OutputFolder")
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$FilePath = Join-Path -Path $OutputFolder -ChildPath "GitHubUsers_$timestamp.csv" # Path to save the CSV file
$FilePath2 = Join-Path -Path $OutputFolder -ChildPath "GitHubCollaborators_$timestamp.csv"  # Path to save the CSV file

# Check if the files exists
if (Test-Path -Path $FilePath) {
    # Delete the existing file
    Remove-Item -Path $FilePath -Force 
}
if (Test-Path -Path $FilePath2) {
    # Delete the existing file
    Remove-Item -Path $FilePath2 -Force 
}

# The manifest of the things this script will output
# for uploading later
$OutputManifest = @{
    Files = @("GitHubUsers_$timestamp.csv", "GitHubCollaborators_$timestamp.csv")
    Links = @()
}
# Return any output parameters this script has to pass on 
# as defined by the contracts.config.json
$OutputParameters = @{}

$success = $true

try {
    # Get all contributors to the repository
    $Uri = "https://api.github.com/repos/$owner/$repo/contributors"
    $contributors = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get

    # Extract relevant information and create objects
    $users = foreach ($contributor in $contributors) {
        [PSCustomObject]@{
            Username = $contributor.login
            ID = $contributor.id
            ProfileURL = $contributor.html_url
            Contributions = $contributor.contributions
        }
    }

    # Export to CSV
    if ($users.Count -gt 0) {
        $users | Export-Csv -Path $FilePath -NoTypeInformation
        Write-Host "GitHub users exported to $FilePath"
    } else {
        Write-Warning "No contributors found for $owner/$repo"
    }

} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    $success = $false
    #If you want to see the full error details, uncomment the next line
    #$_.Exception | Format-List -Force
}

#Get all collaborators. This gets users who have direct access to the repository, regardless of contributions.
try{
    $Uri = "https://api.github.com/repos/$owner/$repo/collaborators"
    $collaborators = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get

    $collaboratorUsers = foreach ($collaborator in $collaborators) {
        [PSCustomObject]@{
            Username = $collaborator.login
            ID = $collaborator.id
            ProfileURL = $collaborator.html_url
            Permission = $collaborator.permissions
        }
    }

    if($collaboratorUsers.Count -gt 0){
        $collaboratorUsers | Export-Csv -Path $FilePath2 -NoTypeInformation
        Write-Host "GitHub collaborators exported to $FilePath2"
    } else {
        Write-Warning "No collaborators found for $owner/$repo"
    }
} catch {
    Write-Error "An error occurred fetching collaborators: $($_.Exception.Message)"
    $success = $false
}

if($success) {
    # Create the output wrapper object, wrapping the parameters and the Manifest
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest = $OutputManifest
    }

    # write the output as json
    Write-Output $ScriptOutput | ConvertTo-Json
}