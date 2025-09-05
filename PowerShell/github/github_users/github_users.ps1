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

# Requires the GitHub CLI (gh) to be installed and authenticated.
# Install: https://cli.github.com/

# Configuration
$FilePath = ".\Output\GitHubUsers.csv" # Path to save the CSV file
$FilePath2 = ".\Output\GitHubCollaborators.csv" # Path to save the CSV file

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
    Files = @("GitHubUsers.csv", "GitHubCollaborators.csv")
    Links = @()
}
# Return any output parameters this script has to pass on 
# as defined by the contracts.config.json
$OutputParameters = @{}

$success = $true

try {
    # Get all contributors to the repository
    $contributors = gh api "/repos/$owner/$repo/contributors" | ConvertFrom-Json

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
    $collaborators = gh api "/repos/$owner/$repo/collaborators" | ConvertFrom-Json

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