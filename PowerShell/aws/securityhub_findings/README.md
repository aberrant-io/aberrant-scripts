# securityhub_findings.ps1

### What it does
- Queries AWS Security Hub findings with `Get-SHUBFinding`.
- Filters by required `AwsAccountId` and optional `ComplianceStatus`.
- Handles paging (`NextToken`) to collect all findings.
- Writes findings to an evidence file in `.\Output`.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsAccountId` (required): 12-digit AWS account ID.
- `ComplianceStatus` (optional): `PASSED`, `WARNING`, `FAILED`, `NOT_AVAILABLE`, or `ALL`.
  If omitted, the script defaults to `FAILED`. Use `ALL` to return all compliance states.

### Outputs (contract)
- Output parameter `FindingsCount`: Number of findings returned.
- Output parameter `FindingsFile`: The generated findings filename.
- Manifest file evidence: `SecurityHubFindings_<AccountId>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `securityhub:GetFindings`
  - `sts:GetCallerIdentity`
- AWS Security Hub enabled in the configured region.
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.SecurityHub -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `securityhub_findings.ps1`. The script supports exactly one of these methods:
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
.\securityhub_findings.ps1 -AwsAccountId "123456789012" -ComplianceStatus "FAILED"
```

```powershell
.\securityhub_findings.ps1 -AwsAccountId "123456789012" -ComplianceStatus "ALL"
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
    "name": "Get AWS Security Hub Findings",
    "description": "Retrieves AWS Security Hub vulnerability findings for a specific AWS account and writes results to JSON",
    "fileName": "securityhub_findings.ps1",
    "inputParameters": [
        {
            "direction": "IN",
            "name": "AwsAccountId",
            "label": "AWS Account ID",
            "description": "The AWS account ID to filter Security Hub findings (12 digits)",
            "parameterType": "string",
            "parameterLength": 12,
            "required": true
        },
        {
            "direction": "IN",
            "name": "ComplianceStatus",
            "label": "Compliance Status",
            "description": "Compliance status filter for findings (PASSED, WARNING, FAILED, NOT_AVAILABLE, or ALL for no compliance filter)",
            "parameterType": "string",
            "parameterLength": 32,
            "required": false,
            "defaultValue": "FAILED"
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
            "description": "The output file name containing Security Hub findings",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        }
    ]
}
```
