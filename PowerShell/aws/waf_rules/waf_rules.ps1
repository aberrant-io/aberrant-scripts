<#
.SYNOPSIS
    Retrieves all WAFv2 web ACLs, rule groups, IP sets, and regex pattern sets for the authenticated
    AWS account and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS WAFv2 using AWS Tools for PowerShell and exports a combined snapshot
    containing all web ACLs (with full rule details), custom rule groups, IP sets (with addresses),
    and regex pattern sets (with patterns). Output is written to the Output directory as JSON.

    Use -Scope REGIONAL for resources associated with ALBs, API Gateway, and AppSync.
    Use -Scope CLOUDFRONT for resources associated with CloudFront distributions. CloudFront WAF
    resources are global; use AwsRegion us-east-1 when querying CLOUDFRONT scope.

.PARAMETER AwsRegion
    The AWS region to query (e.g. us-east-1). Defaults to us-east-1.

.PARAMETER Scope
    The WAFv2 scope: REGIONAL or CLOUDFRONT. Defaults to REGIONAL.

.EXAMPLE
    .\waf_rules.ps1
.EXAMPLE
    .\waf_rules.ps1 -AwsRegion us-west-2
.EXAMPLE
    .\waf_rules.ps1 -Scope CLOUDFRONT -AwsRegion us-east-1
#>
[CmdletBinding()]
param(
    [string]$AwsRegion = "us-east-1",
    [ValidateSet("REGIONAL", "CLOUDFRONT")]
    [string]$Scope = "REGIONAL"
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

function Get-WAF2Pages {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Fetcher,
        [Parameter(Mandatory = $true)]
        [string]$ResultProperty
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $nextMarker = $null

    do {
        $response = & $Fetcher $nextMarker
        if ($null -ne $response -and $null -ne $response.$ResultProperty) {
            $all.AddRange(@($response.$ResultProperty))
        }
        $nextMarker = if ($null -ne $response) { $response.NextMarker } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($nextMarker))

    return ,$all
}

try {
    $requiredModules = @(
        "AWS.Tools.Common",
        "AWS.Tools.WAFv2",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule WAFv2,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.WAFv2
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_waf_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_waf_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_waf_temp" -Region $AwsRegion | Out-Null
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

    # Web ACLs — list summaries then fetch full details (including rules) for each.
    $webAclSummaries = Get-WAF2Pages -ResultProperty "WebACLs" -Fetcher {
        param($marker)
        $req = @{ Scope = $Scope; Limit = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.NextMarker = $marker }
        Get-WAF2WebACLsList @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allWebACLs = [System.Collections.Generic.List[object]]::new()
    foreach ($summary in $webAclSummaries) {
        $detail = Get-WAF2WebACL -Name $summary.Name -Id $summary.Id -Scope $Scope -ErrorAction Stop
        $allWebACLs.Add([PSCustomObject]@{
            Name              = $detail.WebACL.Name
            Id                = $detail.WebACL.Id
            ARN               = $detail.WebACL.ARN
            Description       = $detail.WebACL.Description
            DefaultAction     = $detail.WebACL.DefaultAction
            Rules             = $detail.WebACL.Rules
            VisibilityConfig  = $detail.WebACL.VisibilityConfig
            Capacity          = $detail.WebACL.Capacity
            ManagedByFirewallManager = $detail.WebACL.ManagedByFirewallManager
            LockToken         = $detail.LockToken
        })
    }

    # Custom rule groups — list summaries then fetch full details (including rules) for each.
    $ruleGroupSummaries = Get-WAF2Pages -ResultProperty "RuleGroups" -Fetcher {
        param($marker)
        $req = @{ Scope = $Scope; Limit = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.NextMarker = $marker }
        Get-WAF2RuleGroupList @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allRuleGroups = [System.Collections.Generic.List[object]]::new()
    foreach ($summary in $ruleGroupSummaries) {
        $detail = Get-WAF2RuleGroup -Name $summary.Name -Id $summary.Id -Scope $Scope -ARN $summary.ARN -ErrorAction Stop
        $allRuleGroups.Add([PSCustomObject]@{
            Name             = $detail.RuleGroup.Name
            Id               = $detail.RuleGroup.Id
            ARN              = $detail.RuleGroup.ARN
            Description      = $detail.RuleGroup.Description
            Capacity         = $detail.RuleGroup.Capacity
            Rules            = $detail.RuleGroup.Rules
            VisibilityConfig = $detail.RuleGroup.VisibilityConfig
            LockToken        = $detail.LockToken
        })
    }

    # IP sets — list summaries then fetch full details (including address list) for each.
    $ipSetSummaries = Get-WAF2Pages -ResultProperty "IPSets" -Fetcher {
        param($marker)
        $req = @{ Scope = $Scope; Limit = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.NextMarker = $marker }
        Get-WAF2IPSetList @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allIPSets = [System.Collections.Generic.List[object]]::new()
    foreach ($summary in $ipSetSummaries) {
        $detail = Get-WAF2IPSet -Name $summary.Name -Id $summary.Id -Scope $Scope -ErrorAction Stop
        $allIPSets.Add([PSCustomObject]@{
            Name            = $detail.IPSet.Name
            Id              = $detail.IPSet.Id
            ARN             = $detail.IPSet.ARN
            Description     = $detail.IPSet.Description
            IPAddressVersion = $detail.IPSet.IPAddressVersion
            Addresses       = $detail.IPSet.Addresses
            LockToken       = $detail.LockToken
        })
    }

    # Regex pattern sets — list summaries then fetch full details (including patterns) for each.
    $regexSetSummaries = Get-WAF2Pages -ResultProperty "RegexPatternSets" -Fetcher {
        param($marker)
        $req = @{ Scope = $Scope; Limit = 100 }
        if (-not [string]::IsNullOrWhiteSpace($marker)) { $req.NextMarker = $marker }
        Get-WAF2RegexPatternSetList @req -NoAutoIteration -Select '*' -ErrorAction Stop
    }

    $allRegexPatternSets = [System.Collections.Generic.List[object]]::new()
    foreach ($summary in $regexSetSummaries) {
        $detail = Get-WAF2RegexPatternSet -Name $summary.Name -Id $summary.Id -Scope $Scope -ErrorAction Stop
        $allRegexPatternSets.Add([PSCustomObject]@{
            Name                 = $detail.RegexPatternSet.Name
            Id                   = $detail.RegexPatternSet.Id
            ARN                  = $detail.RegexPatternSet.ARN
            Description          = $detail.RegexPatternSet.Description
            RegularExpressionList = $detail.RegexPatternSet.RegularExpressionList
            LockToken            = $detail.LockToken
        })
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
    $outputFileName = "WafRules_$($AwsAccountId)_$($Scope)_$($AwsRegion)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $snapshot = @{
        AccountId       = $AwsAccountId
        Region          = $AwsRegion
        Scope           = $Scope
        ExportedAt      = (Get-Date).ToString("o")
        WebACLs         = @($allWebACLs)
        RuleGroups      = @($allRuleGroups)
        IPSets          = @($allIPSets)
        RegexPatternSets = @($allRegexPatternSets)
    }

    $snapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        WebACLCount         = "$($allWebACLs.Count)"
        RuleGroupCount      = "$($allRuleGroups.Count)"
        IPSetCount          = "$($allIPSets.Count)"
        RegexPatternSetCount = "$($allRegexPatternSets.Count)"
        WafFile             = $outputFileName
        AccountId           = $AwsAccountId
        Region              = $AwsRegion
        Scope               = $Scope
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest   = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving WAF rules. $($_.Exception.Message)"
    exit 1
}
