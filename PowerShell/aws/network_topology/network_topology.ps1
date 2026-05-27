<#
.SYNOPSIS
    Retrieves all VPCs, subnets, and network ACLs for the authenticated AWS account and region and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS EC2 using AWS Tools for PowerShell and exports a combined network topology
    snapshot containing all VPCs (with CIDR blocks, DHCP options, and tags), subnets (with CIDR, AZ,
    available IPs, and tags), and network ACLs (with all inbound/outbound rules and subnet associations).
    Output is written to the Output directory as JSON.

.PARAMETER AwsRegion
    The AWS region to query (e.g. us-east-1). Defaults to us-east-1.

.EXAMPLE
    .\network_topology.ps1
.EXAMPLE
    .\network_topology.ps1 -AwsRegion us-west-2
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

function Get-AllPages {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Fetcher,
        [Parameter(Mandatory = $true)]
        [string]$ResultProperty
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $nextToken = $null

    do {
        $response = & $Fetcher $nextToken
        if ($null -ne $response -and $null -ne $response.$ResultProperty) {
            $all.AddRange($response.$ResultProperty)
        }
        $nextToken = if ($null -ne $response) { $response.NextToken } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($nextToken))

    return ,$all
}

try {
    $requiredModules = @(
        "AWS.Tools.Common",
        "AWS.Tools.EC2",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule EC2,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.EC2
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_nettopo_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_nettopo_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_nettopo_temp" -Region $AwsRegion | Out-Null
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

    $allVpcs = Get-AllPages -ResultProperty "Vpcs" -Fetcher {
        param($token)
        $req = @{ MaxResult = 200 }
        if (-not [string]::IsNullOrWhiteSpace($token)) { $req.NextToken = $token }
        Get-EC2Vpc @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allSubnets = Get-AllPages -ResultProperty "Subnets" -Fetcher {
        param($token)
        $req = @{ MaxResult = 200 }
        if (-not [string]::IsNullOrWhiteSpace($token)) { $req.NextToken = $token }
        Get-EC2Subnet @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allNacls = Get-AllPages -ResultProperty "NetworkAcls" -Fetcher {
        param($token)
        $req = @{ MaxResult = 200 }
        if (-not [string]::IsNullOrWhiteSpace($token)) { $req.NextToken = $token }
        Get-EC2NetworkAcl @req -NoAutoIteration -Select '*' -ErrorAction Stop
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
    $outputFileName = "NetworkTopology_$($AwsAccountId)_$($AwsRegion)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $topology = @{
        AccountId   = $AwsAccountId
        Region      = $AwsRegion
        ExportedAt  = (Get-Date).ToString("o")
        Vpcs        = @($allVpcs)
        Subnets     = @($allSubnets)
        NetworkAcls = @($allNacls)
    }

    $topology | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        VpcCount        = "$($allVpcs.Count)"
        SubnetCount     = "$($allSubnets.Count)"
        NetworkAclCount = "$($allNacls.Count)"
        TopologyFile    = $outputFileName
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
    Write-Error "An error occurred while retrieving network topology. $($_.Exception.Message)"
    exit 1
}
