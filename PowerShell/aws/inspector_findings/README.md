# inspector_findings.ps1

### What it does
- Queries AWS Inspector v2 findings directly with `Get-INS2FindingList`.
- Filters by required `AwsAccountId` and optional `FindingStatus`.
- Handles paging (`NextToken`) to collect all findings.
- Writes findings to an evidence file in `.\Output`.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsAccountId` (required): 12-digit AWS account ID.
- `FindingStatus` (optional): `ACTIVE`, `SUPPRESSED`, `CLOSED`, or `ALL`.
  If omitted, the script defaults to `ACTIVE`. Use `ALL` to return findings of any status.

### Outputs (contract)
- Output parameter `FindingsCount`: Number of findings returned.
- Output parameter `FindingsFile`: The generated findings filename.
- Manifest file evidence: `InspectorFindings_<AccountId>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `inspector2:ListFindings`
  - `sts:GetCallerIdentity`
- AWS Inspector v2 enabled in the configured region.
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.Inspector2 -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `inspector_findings.ps1`. The script supports exactly one of these methods:
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
.\inspector_findings.ps1 -AwsAccountId "123456789012" -FindingStatus "ACTIVE"
```

```powershell
.\inspector_findings.ps1 -AwsAccountId "123456789012" -FindingStatus "ALL"
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
