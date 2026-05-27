<#
.SYNOPSIS
    Retrieves GuardDuty findings for the authenticated AWS account and region over a configurable
    lookback window and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS GuardDuty using AWS Tools for PowerShell and exports all findings
    updated within the lookback window. For each detector in the region it paginates the finding
    IDs filtered by updatedAt, then batch-fetches full finding details (severity, type, resource
    affected, service action, evidence). Output is written to the Output directory as JSON.

.PARAMETER AwsRegion
    The AWS region to query (e.g. us-east-1). Defaults to us-east-1.

.PARAMETER LookbackDays
    Number of days back from now to include findings updated within that window. Defaults to 30.
    Valid range: 1-365.

.EXAMPLE
    .\guardduty_findings.ps1
.EXAMPLE
    .\guardduty_findings.ps1 -AwsRegion us-west-2 -LookbackDays 90
#>
[CmdletBinding()]
param(
    [string]$AwsRegion = "us-east-1",

    [ValidateRange(1, 365)]
    [int]$LookbackDays = 30
)

# --- USER CONFIGURATION ---
# Configure one of these options:
# 1) Set AwsProfileName to use an AWS shared credentials profile.
# 2) Set AwsAccessKey/AwsSecretKey (and optional AwsSessionToken) for explicit credentials.
# 3) Leave all blank to use the environment/instance role default AWS credential chain.
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
        "AWS.Tools.GuardDuty",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule GuardDuty,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.GuardDuty
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_gd_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_gd_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_gd_temp" -Region $AwsRegion | Out-Null
    }
    else {
        Set-DefaultAWSRegion -Region $AwsRegion
    }

    $callerIdentity = $null
    try {
        $callerIdentity = Get-STSCallerIdentity -ErrorAction Stop
    }
    catch {
        throw "AWS authentication failed. Configure AwsProfileName or AwsAccessKey/AwsSecretKey, or set environment/instance-role credentials. Details: $($_.Exception.Message)"
    }

    $AwsAccountId = $callerIdentity.Account

    # Calculate lookback window start as epoch milliseconds (GuardDuty criterion format).
    $windowStart = (Get-Date).AddDays(-$LookbackDays).ToUniversalTime()
    $epochOrigin = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $windowStartEpochMs = [long]($windowStart - $epochOrigin).TotalMilliseconds

    # List all detectors in the region (typically one per region).
    $detectorIds = @(Get-GDDetectorList -ErrorAction Stop)

    if ($detectorIds.Count -eq 0) {
        throw "No GuardDuty detectors found in region $AwsRegion. Ensure GuardDuty is enabled."
    }

    $allFindings = [System.Collections.Generic.List[object]]::new()

    foreach ($detectorId in $detectorIds) {
        # Build the updatedAt >= windowStart filter criterion.
        $condition = New-Object Amazon.GuardDuty.Model.Condition
        $condition.GreaterThanOrEqual = $windowStartEpochMs

        $findingCriteria = New-Object Amazon.GuardDuty.Model.FindingCriteria
        if ($null -eq $findingCriteria.Criterion) {
            $findingCriteria.Criterion = New-Object 'System.Collections.Generic.Dictionary[String, Amazon.GuardDuty.Model.Condition]'
        }
        $findingCriteria.Criterion["updatedAt"] = $condition

        # Paginate finding IDs.
        $findingIds = [System.Collections.Generic.List[string]]::new()
        $nextToken = $null

        do {
            $req = @{
                DetectorId       = $detectorId
                FindingCriterion = $findingCriteria
                MaxResult        = 50
            }
            if (-not [string]::IsNullOrWhiteSpace($nextToken)) { $req.NextToken = $nextToken }

            $response = Get-GDFindingList @req -NoAutoIteration -Select '*' -ErrorAction Stop

            if ($null -ne $response -and $null -ne $response.FindingIds) {
                $findingIds.AddRange($response.FindingIds)
            }
            $nextToken = if ($null -ne $response) { $response.NextToken } else { $null }
        } while (-not [string]::IsNullOrWhiteSpace($nextToken))

        # Batch-fetch full finding details (API limit: 50 IDs per call).
        for ($i = 0; $i -lt $findingIds.Count; $i += 50) {
            $batch = $findingIds[$i..([Math]::Min($i + 49, $findingIds.Count - 1))]
            $findings = Get-GDFinding -DetectorId $detectorId -FindingId $batch -ErrorAction Stop
            if ($null -ne $findings) {
                $allFindings.AddRange(@($findings))
            }
        }
    }

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
    $outputFileName = "GuardDutyFindings_$($AwsAccountId)_$($AwsRegion)_$($LookbackDays)d_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $snapshot = @{
        AccountId    = $AwsAccountId
        Region       = $AwsRegion
        LookbackDays = $LookbackDays
        WindowStart  = $windowStart.ToString("o")
        ExportedAt   = (Get-Date).ToString("o")
        DetectorIds  = $detectorIds
        Findings     = @($allFindings)
    }

    $snapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        FindingCount  = "$($allFindings.Count)"
        DetectorCount = "$($detectorIds.Count)"
        LookbackDays  = "$LookbackDays"
        FindingsFile  = $outputFileName
        AccountId     = $AwsAccountId
        Region        = $AwsRegion
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest   = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving GuardDuty findings. $($_.Exception.Message)"
    exit 1
}
