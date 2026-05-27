<#
.SYNOPSIS
    Retrieves all RDS DB instances and clusters for the authenticated AWS account and region and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS RDS using AWS Tools for PowerShell and exports a combined inventory
    snapshot containing all DB instances (with engine, encryption, public accessibility, VPC placement,
    parameter groups, IAM auth, backup retention, and tags) and all DB clusters (Aurora and Multi-AZ
    clusters, with equivalent security-relevant fields). Output is written to the Output directory as JSON.

.PARAMETER AwsRegion
    The AWS region to query (e.g. us-east-1). Defaults to us-east-1.

.EXAMPLE
    .\rds_inventory.ps1
.EXAMPLE
    .\rds_inventory.ps1 -AwsRegion us-west-2
#>
[CmdletBinding()]
param(
    [string]$AwsRegion = "us-east-1"
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
        "AWS.Tools.RDS",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule RDS,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.RDS
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_rds_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_rds_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_rds_temp" -Region $AwsRegion | Out-Null
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

    # Paginate through all DB instances.
    $allInstances = [System.Collections.Generic.List[object]]::new()
    $marker = $null

    do {
        $req = @{ MaxRecord = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.Marker = $marker }
        $response = Get-RDSDBInstance @req -NoAutoIteration -Select '*' -ErrorAction Stop
        if ($null -ne $response -and $null -ne $response.DBInstances) {
            $allInstances.AddRange($response.DBInstances)
        }
        $marker = if ($null -ne $response) { $response.Marker } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($marker))

    # Paginate through all DB clusters (Aurora and Multi-AZ clusters).
    $allClusters = [System.Collections.Generic.List[object]]::new()
    $marker = $null

    do {
        $req = @{ MaxRecord = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.Marker = $marker }
        $response = Get-RDSDBCluster @req -NoAutoIteration -Select '*' -ErrorAction Stop
        if ($null -ne $response -and $null -ne $response.DBClusters) {
            $allClusters.AddRange($response.DBClusters)
        }
        $marker = if ($null -ne $response) { $response.Marker } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($marker))

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
    $outputFileName = "RdsInventory_$($AwsAccountId)_$($AwsRegion)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $inventory = @{
        AccountId   = $AwsAccountId
        Region      = $AwsRegion
        ExportedAt  = (Get-Date).ToString("o")
        DBInstances = @($allInstances)
        DBClusters  = @($allClusters)
    }

    $inventory | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        DBInstanceCount = "$($allInstances.Count)"
        DBClusterCount  = "$($allClusters.Count)"
        InventoryFile   = $outputFileName
        AccountId       = $AwsAccountId
        Region          = $AwsRegion
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest   = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving RDS inventory. $($_.Exception.Message)"
    exit 1
}
