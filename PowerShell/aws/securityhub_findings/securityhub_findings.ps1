<#
.SYNOPSIS
    Retrieves AWS Security Hub findings for a specific AWS account and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS Security Hub findings using AWS Tools for PowerShell, filtered by AWS account ID
    and optional compliance status. Findings are written to the Output directory as JSON.

.PARAMETER AwsAccountId
    The 12-digit AWS account ID used to filter findings.

.PARAMETER ComplianceStatus
    Optional compliance status filter (PASSED, WARNING, FAILED, NOT_AVAILABLE, or ALL).
    Defaults to FAILED. Use ALL to return all compliance states.

.EXAMPLE
    .\securityhub_findings.ps1 -AwsAccountId "123456789012" -ComplianceStatus "FAILED"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{12}$')]
    [string]$AwsAccountId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("PASSED", "WARNING", "FAILED", "NOT_AVAILABLE", "ALL")]
    [string]$ComplianceStatus = "FAILED"
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
        "AWS.Tools.SecurityHub",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule SecurityHub,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.SecurityHub
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_securityhub_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_securityhub_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_securityhub_temp" -Region $AwsRegion | Out-Null
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

    $filters = @{
        AwsAccountId = [Amazon.SecurityHub.Model.StringFilter]@{
            Comparison = "EQUALS"
            Value = $AwsAccountId
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace($ComplianceStatus) -and
        $ComplianceStatus -ne "ALL"
    ) {
        $filters.ComplianceStatus = [Amazon.SecurityHub.Model.StringFilter]@{
            Comparison = "EQUALS"
            Value = $ComplianceStatus
        }
    }

    $allFindings = @()
    $nextToken = $null

    do {
        $request = @{
            Filter = $filters
            MaxResult = 100
        }

        if (-not [string]::IsNullOrWhiteSpace($nextToken)) {
            $request.NextToken = $nextToken
        }

        # Force full response object to safely access Findings + NextToken.
        $response = Get-SHUBFinding @request -NoAutoIteration -Select '*' -ErrorAction Stop

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
    $outputFileName = "SecurityHubFindings_$($AwsAccountId)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $allFindings | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        FindingsCount = "$($allFindings.Count)"
        FindingsFile = $outputFileName
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving Security Hub findings. $($_.Exception.Message)"
    exit 1
}
