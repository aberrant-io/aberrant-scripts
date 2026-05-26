# Inspector Findings Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the copied `securityhub_findings.ps1` in `PowerShell/aws/inspector_findings/` with a script that queries AWS Inspector v2 directly using `Get-INS2FindingList`.

**Architecture:** A single PowerShell script that authenticates to AWS, builds an `Amazon.Inspector2.Model.FilterCriteria` filter, pages through `Get-INS2FindingList` results, writes findings to a JSON file, and emits a structured JSON manifest to stdout. The `contract.json` is updated to match the new parameter names and descriptions.

**Tech Stack:** PowerShell, `AWS.Tools.Inspector2`, `AWS.Tools.Common`, `AWS.Tools.SecurityToken`

---

## Files

| Action | Path |
|--------|------|
| Create | `PowerShell/aws/inspector_findings/inspector_findings.ps1` |
| Modify | `PowerShell/aws/inspector_findings/contract.json` |
| Delete | `PowerShell/aws/inspector_findings/securityhub_findings.ps1` |

---

### Task 1: Create inspector_findings.ps1

**Files:**
- Create: `PowerShell/aws/inspector_findings/inspector_findings.ps1`

- [ ] **Step 1: Create the file with the full script content**

Create `PowerShell/aws/inspector_findings/inspector_findings.ps1` with this exact content:

```powershell
<#
.SYNOPSIS
    Retrieves AWS Inspector v2 findings for a specific AWS account and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS Inspector v2 findings using AWS Tools for PowerShell, filtered by AWS account ID
    and optional finding status. Findings are written to the Output directory as JSON.

.PARAMETER AwsAccountId
    The 12-digit AWS account ID used to filter findings.

.PARAMETER FindingStatus
    Optional finding status filter (ACTIVE, SUPPRESSED, CLOSED, or ALL).
    Defaults to ACTIVE. Use ALL to return findings of any status.

.EXAMPLE
    .\inspector_findings.ps1 -AwsAccountId "123456789012" -FindingStatus "ACTIVE"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{12}$')]
    [string]$AwsAccountId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ACTIVE", "SUPPRESSED", "CLOSED", "ALL")]
    [string]$FindingStatus = "ACTIVE"
)

# --- USER CONFIGURATION ---
# Configure one of these options:
# 1) Set AwsProfileName to use an AWS shared credentials profile.
# 2) Set AwsAccessKey/AwsSecretKey (and optional AwsSessionToken) for explicit credentials.
# 3) Leave all blank to use the environment/instance role default AWS credential chain.
$AwsRegion = "us-east-1"
$AwsProfileName = ""
$AwsAccessKey = ""
$AwsSecretKey = ""
$AwsSessionToken = ""
# --- END OF USER CONFIGURATION ---

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-ModuleInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Module -ListAvailable -Name $Name)
}

try {
    $requiredModules = @(
        "AWS.Tools.Common",
        "AWS.Tools.Inspector2",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule Inspector2,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.Inspector2
    Import-Module AWS.Tools.SecurityToken

    $hasProfile = -not [string]::IsNullOrWhiteSpace($AwsProfileName)
    $hasAccessKey = -not [string]::IsNullOrWhiteSpace($AwsAccessKey)
    $hasSecretKey = -not [string]::IsNullOrWhiteSpace($AwsSecretKey)
    $hasSessionToken = -not [string]::IsNullOrWhiteSpace($AwsSessionToken)

    if ($hasProfile -and ($hasAccessKey -or $hasSecretKey -or $hasSessionToken)) {
        throw "Use either AwsProfileName or AwsAccessKey/AwsSecretKey configuration, not both."
    }

    if ($hasAccessKey -xor $hasSecretKey) {
        throw "Both AwsAccessKey and AwsSecretKey are required when using key-based authentication."
    }

    if ($hasSessionToken -and -not ($hasAccessKey -and $hasSecretKey)) {
        throw "AwsSessionToken requires AwsAccessKey and AwsSecretKey."
    }

    if ($hasProfile) {
        Initialize-AWSDefaultConfiguration -ProfileName $AwsProfileName -Region $AwsRegion | Out-Null
    }
    elseif ($hasAccessKey -and $hasSecretKey) {
        if ($hasSessionToken) {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_inspector_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_inspector_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_inspector_temp" -Region $AwsRegion | Out-Null
    }
    else {
        Set-DefaultAWSRegion -Region $AwsRegion
    }

    try {
        Get-STSCallerIdentity | Out-Null
    }
    catch {
        throw "AWS authentication failed. Configure AwsProfileName or AwsAccessKey/AwsSecretKey, or set environment/instance-role credentials. Details: $($_.Exception.Message)"
    }

    $filterCriteria = New-Object Amazon.Inspector2.Model.FilterCriteria

    $accountIdFilter = New-Object Amazon.Inspector2.Model.StringFilter
    $accountIdFilter.Comparison = "EQUALS"
    $accountIdFilter.Value = $AwsAccountId
    $filterCriteria.AwsAccountId = [System.Collections.Generic.List[Amazon.Inspector2.Model.StringFilter]]@($accountIdFilter)

    if ($FindingStatus -ne "ALL") {
        $statusFilter = New-Object Amazon.Inspector2.Model.StringFilter
        $statusFilter.Comparison = "EQUALS"
        $statusFilter.Value = $FindingStatus
        $filterCriteria.FindingStatus = [System.Collections.Generic.List[Amazon.Inspector2.Model.StringFilter]]@($statusFilter)
    }

    $allFindings = @()
    $nextToken = $null

    do {
        $request = @{
            FilterCriteria = $filterCriteria
            MaxResult      = 100
        }

        if (-not [string]::IsNullOrWhiteSpace($nextToken)) {
            $request.NextToken = $nextToken
        }

        # Force full response object to safely access Findings + NextToken.
        $response = Get-INS2FindingList @request -NoAutoIteration -Select '*' -ErrorAction Stop

        if ($null -ne $response -and $null -ne $response.Findings) {
            $allFindings += $response.Findings
        }

        $nextToken = if ($null -ne $response) { $response.NextToken } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($nextToken))

    try {
        if (-not (Test-Path -Path ".\Output")) {
            New-Item -Path ".\Output" -ItemType Directory | Out-Null
        }
        $probePath = ".\Output\.write_test.tmp"
        "ok" | Set-Content -Path $probePath -Encoding UTF8
        Remove-Item -Path $probePath -Force
    }
    catch {
        throw "Output directory is not writable. Ensure '.\\Output' exists and is writable. Details: $($_.Exception.Message)"
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $outputFileName = "InspectorFindings_$($AwsAccountId)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $allFindings | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        FindingsCount = "$($allFindings.Count)"
        FindingsFile  = $outputFileName
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest   = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving Inspector findings. $($_.Exception.Message)"
    exit 1
}
```

- [ ] **Step 2: Verify the file was created**

Run:
```powershell
Test-Path "PowerShell\aws\inspector_findings\inspector_findings.ps1"
```
Expected: `True`

- [ ] **Step 3: Commit**

```bash
git add PowerShell/aws/inspector_findings/inspector_findings.ps1
git commit -m "Add inspector_findings.ps1 using AWS Inspector v2 directly"
```

---

### Task 2: Update contract.json

**Files:**
- Modify: `PowerShell/aws/inspector_findings/contract.json`

- [ ] **Step 1: Replace contract.json content**

Replace the entire contents of `PowerShell/aws/inspector_findings/contract.json` with:

```json
{
    "name": "Get AWS Inspector Findings",
    "description": "Retrieves AWS Inspector v2 findings for a specific AWS account and writes results to JSON",
    "fileName": "inspector_findings.ps1",
    "inputParameters": [
        {
            "direction": "IN",
            "name": "AwsAccountId",
            "label": "AWS Account ID",
            "description": "The AWS account ID to filter Inspector findings (12 digits)",
            "parameterType": "string",
            "parameterLength": 12,
            "required": true
        },
        {
            "direction": "IN",
            "name": "FindingStatus",
            "label": "Finding Status",
            "description": "Finding status filter for findings (ACTIVE, SUPPRESSED, CLOSED, or ALL for no status filter)",
            "parameterType": "string",
            "parameterLength": 32,
            "required": false,
            "defaultValue": "ACTIVE"
        }
    ],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "FindingsCount",
            "label": "Findings Count",
            "description": "The number of findings returned by the query",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "FindingsFile",
            "label": "Findings File",
            "description": "The output file name containing Inspector findings",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        }
    ]
}
```

- [ ] **Step 2: Commit**

```bash
git add PowerShell/aws/inspector_findings/contract.json
git commit -m "Update contract.json for inspector_findings"
```

---

### Task 3: Remove old securityhub_findings.ps1

**Files:**
- Delete: `PowerShell/aws/inspector_findings/securityhub_findings.ps1`

- [ ] **Step 1: Delete the old file**

```bash
git rm PowerShell/aws/inspector_findings/securityhub_findings.ps1
```

- [ ] **Step 2: Commit**

```bash
git commit -m "Remove copied securityhub_findings.ps1 from inspector_findings"
```
