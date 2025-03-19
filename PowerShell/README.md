# aberrant-scripts
Powershell scripts for the Aberrant RemoteAgent

## Contents

| Script| Description |
| -------- | ------- |
| github_users.ps1  | Connects to a github repository and writes a CSV of all users that have contributed to the repository (`GitHubUsers.csv`) and all users who have access repository (`GitHubCollaborators.csv`). Requires [github cli](https://cli.github.com/) to be installed and configured. |
| url_grabber.ps1 | Accepts a url as a parameter and outputs the raw response from the url to a file (`downloaded_content.txt`) |
|  |  |

## Adding Scripts

### Parameters
Scripts with parameters _must_ decorate any required parameters with `[Parameter(Mandatory=$true)]`.

e.g.
```
param(
    [Parameter(Mandatory=$true)]
    [string]$owner, # the repository owner (user or organization)
    [Parameter(Mandatory=$true)]
    [string]$repo # the repository name
)
```

### Standard Out
The only output written to stdout should be the Output Manifest in JSON format.

The output manifest is read by the RemoteAgent in order to determine script success, and any actions that may be required for output of this script. 

```
// output manifest example
{
   //a dictionary of the output parameters for the script
   Parameters : {
     (key) : (value)
   },
   //a list of evidence this script generated
   Manifest {
    Files: ["file1", "file2", etc.],
    Links: ["http://example.com", "http://sample.com", etc.]
   }
}
```

### Standard Error
If the script encountered an error, any error messages can be written to the stderr output.
