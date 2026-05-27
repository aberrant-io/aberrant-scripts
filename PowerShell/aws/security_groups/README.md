# security_groups.ps1

### What it does
- Lists all EC2 security groups in the configured region with `Get-EC2SecurityGroup`.
- Handles paging (`NextToken`) to collect all groups.
- Each security group includes full detail: inbound rules (`IpPermissions`), outbound rules (`IpPermissionsEgress`), VPC association, owner, and tags.
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Writes all security group data to an evidence file in `.\Output`.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- None. The script takes no input parameters. Region and auth are configured in the `USER CONFIGURATION` section of the script.

### Outputs (contract)
- Output parameter `SecurityGroupCount`: Number of security groups returned.
- Output parameter `SecurityGroupsFile`: The generated security groups filename.
- Output parameter `AccountId`: The AWS account ID security groups were retrieved from.
- Output parameter `Region`: The AWS region security groups were retrieved from.
- Manifest file evidence: `SecurityGroups_<AccountId>_<Region>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `ec2:DescribeSecurityGroups`
  - `sts:GetCallerIdentity`
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.EC2 -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `security_groups.ps1`. The script supports exactly one of these methods:
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
.\security_groups.ps1
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
    "name": "Get AWS Security Groups",
    "description": "Retrieves all EC2 security groups for the authenticated AWS account and region with full inbound/outbound rule detail and writes results to JSON",
    "fileName": "security_groups.ps1",
    "inputParameters": [],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "SecurityGroupCount",
            "label": "Security Group Count",
            "description": "The number of security groups returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "SecurityGroupsFile",
            "label": "Security Groups File",
            "description": "The output file name containing security group data",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which security groups were retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Region",
            "label": "Region",
            "description": "The AWS region from which security groups were retrieved",
            "parameterType": "string",
            "parameterLength": 32,
            "scope": "GLOBAL"
        }
    ]
}
```
