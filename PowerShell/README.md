# Aberrant Remote Agent Powershell Scripts
Powershell scripts for the [Aberrant](https://www.aberrant.io/) RemoteAgent

## Contents

| Folder| Description |
| -------- | ------- |
| aws  | Scripts for interacting with AWS services |
| github  | Scripts for interacting with github.com |
| jira  | Scripts for interacting with Atlassian Jira |
| web | General scripts for making http and web requests |
|  |  |

## Contribution Guidelines

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
