<#
.SYNOPSIS
    Retrieves all IAM users for the authenticated AWS account and saves them to a JSON file.

.DESCRIPTION
    This script queries AWS IAM using AWS Tools for PowerShell and exports all users with their
    full attribute set: access keys, MFA devices, group memberships, attached policies,
    inline policies, tags, and login profile status. Output is written to the Output directory as JSON.

.EXAMPLE
    .\iam_users.ps1
#>
[CmdletBinding()]
param()

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
        "AWS.Tools.IdentityManagement",
        "AWS.Tools.SecurityToken"
    )
    $missingModules = @()

    foreach ($moduleName in $requiredModules) {
        if (-not (Test-ModuleInstalled -Name $moduleName)) {
            $missingModules += $moduleName
        }
    }

    if ($missingModules.Count -gt 0) {
        throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module AWS.Tools.Installer -Scope CurrentUser; Install-AWSToolsModule IdentityManagement,SecurityToken -Scope CurrentUser"
    }

    Import-Module AWS.Tools.Common
    Import-Module AWS.Tools.IdentityManagement
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
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -SessionToken $AwsSessionToken -StoreAs "aberrant_iam_temp" | Out-Null
        }
        else {
            Set-AWSCredential -AccessKey $AwsAccessKey -SecretKey $AwsSecretKey -StoreAs "aberrant_iam_temp" | Out-Null
        }
        Initialize-AWSDefaultConfiguration -ProfileName "aberrant_iam_temp" -Region $AwsRegion | Out-Null
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

    # Paginate through all IAM users.
    $allUsers = [System.Collections.Generic.List[object]]::new()
    $marker = $null

    do {
        $request = @{ MaxItem = 100 }

        if (-not [string]::IsNullOrWhiteSpace($marker)) {
            $request.Marker = $marker
        }

        $response = Get-IAMUserList @request -NoAutoIteration -Select '*' -ErrorAction Stop

        if ($null -ne $response -and $null -ne $response.Users) {
            $allUsers.AddRange($response.Users)
        }

        $marker = if ($null -ne $response -and $response.IsTruncated) { $response.Marker } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($marker))

    # Enrich each user with full attribute set.
    $enrichedUsers = [System.Collections.Generic.List[object]]::new()

    foreach ($user in $allUsers) {
        $userName = $user.UserName

        $accessKeys = @(Get-IAMAccessKey -UserName $userName -ErrorAction SilentlyContinue)
        $mfaDevices = @(Get-IAMMFADevice -UserName $userName -ErrorAction SilentlyContinue)
        $groups = @(Get-IAMGroupForUser -UserName $userName -ErrorAction SilentlyContinue)
        $attachedPolicies = @(Get-IAMAttachedUserPolicies -UserName $userName -ErrorAction SilentlyContinue)
        $inlinePolicies = @(Get-IAMUserPolicyList -UserName $userName -ErrorAction SilentlyContinue)
        $tags = @(Get-IAMUserTagList -UserName $userName -ErrorAction SilentlyContinue)

        $loginProfileExists = $false
        try {
            Get-IAMLoginProfile -UserName $userName -ErrorAction Stop | Out-Null
            $loginProfileExists = $true
        }
        catch {
            # NoSuchEntityException means no console login profile — expected for service accounts.
        }

        $enrichedUsers.Add([PSCustomObject]@{
            UserId              = $user.UserId
            UserName            = $userName
            Arn                 = $user.Arn
            Path                = $user.Path
            CreateDate          = $user.CreateDate
            PasswordLastUsed    = $user.PasswordLastUsed
            ConsoleAccess       = $loginProfileExists
            AccessKeys          = $accessKeys | Select-Object AccessKeyId, Status, CreateDate
            MfaDevices          = $mfaDevices | Select-Object SerialNumber, EnableDate
            Groups              = $groups | Select-Object GroupId, GroupName, Arn
            AttachedPolicies    = $attachedPolicies | Select-Object PolicyArn, PolicyName
            InlinePolicies      = $inlinePolicies
            Tags                = $tags | Select-Object Key, Value
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
    $outputFileName = "IamUsers_$($AwsAccountId)_$timestamp.json"
    $outputFilePath = ".\Output\$outputFileName"

    $enrichedUsers.ToArray() | ConvertTo-Json -Depth 20 | Set-Content -Path $outputFilePath -Encoding UTF8

    $OutputManifest = @{
        Files = @($outputFileName)
        Links = @()
    }
    $OutputParameters = @{
        UserCount  = "$($enrichedUsers.Count)"
        UsersFile  = $outputFileName
        AccountId  = $AwsAccountId
    }
    $ScriptOutput = @{
        Parameters = $OutputParameters
        Manifest   = $OutputManifest
    }

    Write-Output ($ScriptOutput | ConvertTo-Json)
}
catch {
    Write-Error "An error occurred while retrieving IAM users. $($_.Exception.Message)"
    exit 1
}
