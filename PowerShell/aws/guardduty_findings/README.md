# guardduty_findings.ps1

### What it does
- Lists all GuardDuty detector IDs in the configured region with `Get-GDDetectorList`.
- For each detector, paginates finding IDs filtered to findings updated within the lookback window (`Get-GDFindingList` with an `updatedAt` criterion).
- Batch-fetches full finding details in groups of 50 (`Get-GDFinding`), capturing severity, type, resource affected, service action, and evidence.
- Writes a combined JSON document with findings plus metadata (`AccountId`, `Region`, `LookbackDays`, `WindowStart`, `DetectorIds`, `ExportedAt`).
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsRegion` (optional): AWS region to query (e.g. `us-west-2`). Defaults to `us-east-1`.
- `LookbackDays` (optional): Number of days back from now to include findings updated within that window. Defaults to `30`. Valid range: 1–365.

### Outputs (contract)
- Output parameter `FindingCount`: Number of findings returned.
- Output parameter `DetectorCount`: Number of GuardDuty detectors found in the region.
- Output parameter `LookbackDays`: The lookback window used.
- Output parameter `FindingsFile`: The generated findings filename.
- Output parameter `AccountId`: The AWS account ID findings were retrieved from.
- Output parameter `Region`: The AWS region findings were retrieved from.
- Manifest file evidence: `GuardDutyFindings_<AccountId>_<Region>_<LookbackDays>d_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `guardduty:ListDetectors`
  - `guardduty:ListFindings`
  - `guardduty:GetFindings`
  - `sts:GetCallerIdentity`
- GuardDuty enabled in the configured region.
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.GuardDuty -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `guardduty_findings.ps1`. The script supports exactly one of these methods:
- AWS profile:
  - Set `$AwsProfileName`.
- Static keys:
  - Set `$AwsAccessKey` and `$AwsSecretKey`.
  - Set `$AwsSessionToken` only if using temporary credentials.
- Default AWS credential chain:
  - Leave profile/keys blank and rely on environment/instance role credentials.

Validation guardrails in the script:
- Fails if profile and key-based auth are both configured.
- Fails if only one of access key/secret key is provided.
- Fails if session token is set without access key/secret key.
- Fails if no GuardDuty detectors are found in the region.

### Example run
```powershell
.\guardduty_findings.ps1
```

```powershell
.\guardduty_findings.ps1 -AwsRegion us-west-2 -LookbackDays 90
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
    "name": "Get AWS GuardDuty Findings",
    "description": "Retrieves GuardDuty findings updated within a configurable lookback window for the authenticated AWS account and region and writes results to JSON",
    "fileName": "guardduty_findings.ps1",
    "inputParameters": [
        {
            "direction": "IN",
            "name": "AwsRegion",
            "label": "AWS Region",
            "description": "The AWS region to query (e.g. us-east-1). Defaults to us-east-1.",
            "parameterType": "string",
            "parameterLength": 32,
            "required": false,
            "defaultValue": "us-east-1"
        },
        {
            "direction": "IN",
            "name": "LookbackDays",
            "label": "Lookback Days",
            "description": "Number of days back from now to include findings updated within that window. Valid range: 1-365.",
            "parameterType": "string",
            "parameterLength": 3,
            "required": false,
            "defaultValue": "30"
        }
    ],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "FindingCount",
            "label": "Finding Count",
            "description": "The number of findings returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "DetectorCount",
            "label": "Detector Count",
            "description": "The number of GuardDuty detectors found in the region",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "LookbackDays",
            "label": "Lookback Days",
            "description": "The lookback window used for the query",
            "parameterType": "string",
            "parameterLength": 3,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "FindingsFile",
            "label": "Findings File",
            "description": "The output file name containing GuardDuty findings",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which findings were retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Region",
            "label": "Region",
            "description": "The AWS region from which findings were retrieved",
            "parameterType": "string",
            "parameterLength": 32,
            "scope": "GLOBAL"
        }
    ]
}
```
