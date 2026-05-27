# iam_users.ps1

### What it does
- Lists all IAM users in the authenticated account with `Get-IAMUserList`.
- Handles paging (`Marker`/`IsTruncated`) to collect all users.
- Enriches each user with a full attribute set via additional IAM API calls:
  - Access keys (`Get-IAMAccessKey`)
  - MFA devices (`Get-IAMMFADevice`)
  - Group memberships (`Get-IAMGroupForUser`)
  - Attached managed policies (`Get-IAMAttachedUserPolicies`)
  - Inline policy names (`Get-IAMUserPolicyList`)
  - Tags (`Get-IAMUserTagList`)
  - Console login profile existence (`Get-IAMLoginProfile`)
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Writes all user data to an evidence file in `.\Output`.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- None. The script takes no input parameters. Auth is configured in the `USER CONFIGURATION` section of the script.

### Outputs (contract)
- Output parameter `UserCount`: Number of IAM users returned.
- Output parameter `UsersFile`: The generated users filename.
- Output parameter `AccountId`: The AWS account ID users were retrieved from.
- Manifest file evidence: `IamUsers_<AccountId>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `iam:ListUsers`
  - `iam:ListAccessKeys`
  - `iam:ListMFADevices`
  - `iam:ListGroupsForUser`
  - `iam:ListAttachedUserPolicies`
  - `iam:ListUserPolicies`
  - `iam:ListUserTags`
  - `iam:GetLoginProfile`
  - `sts:GetCallerIdentity`
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.IdentityManagement -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `iam_users.ps1`. The script supports exactly one of these methods:
- AWS profile:
  - Set `$AwsProfileName` and verify `$AwsRegion`.
- Static keys:
  - Set `$AwsAccessKey` and `$AwsSecretKey`.
  - Set `$AwsSessionToken` only if using temporary credentials.
- Default AWS credential chain:
  - Leave profile/keys blank and rely on environment/instance role credentials.

Validation guardrails in the script:
- Fails if profile and key-based auth are both configured.
- Fails if only one of access key/secret key is provided.
- Fails if session token is set without access key/secret key.

### Example run
```powershell
.\iam_users.ps1
```

### Error handling behavior
- Success:
  - Writes only the output manifest JSON to stdout.
- Failure:
  - Writes clear actionable error details to stderr.
  - Exits with non-zero status (`exit 1`).

## Contract

```json
{
    "name": "Get AWS IAM Users",
    "description": "Retrieves all IAM users for the authenticated AWS account with full attribute set and writes results to JSON",
    "fileName": "iam_users.ps1",
    "inputParameters": [],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "UserCount",
            "label": "User Count",
            "description": "The number of IAM users returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "UsersFile",
            "label": "Users File",
            "description": "The output file name containing IAM user data",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which users were retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        }
    ]
}
```
