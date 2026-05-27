# waf_rules.ps1

### What it does
- Lists all WAFv2 web ACLs, custom rule groups, IP sets, and regex pattern sets for the configured scope and region.
- Handles paging (`NextMarker`) independently for each resource type.
- Enriches each summary with a full-detail API call to capture rules, addresses, and patterns:
  - Web ACLs: full rule list, default action, visibility config, capacity (`Get-WAF2WebACL`)
  - Rule groups: full rule list, capacity, visibility config (`Get-WAF2RuleGroup`)
  - IP sets: all CIDR addresses, IP version (`Get-WAF2IPSet`)
  - Regex pattern sets: all regex patterns (`Get-WAF2RegexPatternSet`)
- Writes a single combined JSON document with four top-level arrays plus metadata (`AccountId`, `Region`, `Scope`, `ExportedAt`).
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsRegion` (optional): AWS region to query (e.g. `us-west-2`). Defaults to `us-east-1`. Use `us-east-1` when querying `CLOUDFRONT` scope.
- `Scope` (optional): `REGIONAL` for resources on ALBs, API Gateway, and AppSync; `CLOUDFRONT` for CloudFront distributions. Defaults to `REGIONAL`.

### Outputs (contract)
- Output parameter `WebACLCount`: Number of web ACLs returned.
- Output parameter `RuleGroupCount`: Number of custom rule groups returned.
- Output parameter `IPSetCount`: Number of IP sets returned.
- Output parameter `RegexPatternSetCount`: Number of regex pattern sets returned.
- Output parameter `WafFile`: The generated WAF rules filename.
- Output parameter `AccountId`: The AWS account ID WAF rules were retrieved from.
- Output parameter `Region`: The AWS region WAF rules were retrieved from.
- Output parameter `Scope`: The WAFv2 scope that was queried.
- Manifest file evidence: `WafRules_<AccountId>_<Scope>_<Region>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `wafv2:ListWebACLs`
  - `wafv2:GetWebACL`
  - `wafv2:ListRuleGroups`
  - `wafv2:GetRuleGroup`
  - `wafv2:ListIPSets`
  - `wafv2:GetIPSet`
  - `wafv2:ListRegexPatternSets`
  - `wafv2:GetRegexPatternSet`
  - `sts:GetCallerIdentity`
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.WAFv2 -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `waf_rules.ps1`. The script supports exactly one of these methods:
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

### Example run
```powershell
.\waf_rules.ps1
```

```powershell
.\waf_rules.ps1 -AwsRegion us-west-2
```

```powershell
.\waf_rules.ps1 -Scope CLOUDFRONT -AwsRegion us-east-1
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
    "name": "Get AWS WAF Rules",
    "description": "Retrieves all WAFv2 web ACLs, rule groups, IP sets, and regex pattern sets for the authenticated AWS account and writes a combined snapshot to JSON",
    "fileName": "waf_rules.ps1",
    "inputParameters": [
        {
            "direction": "IN",
            "name": "AwsRegion",
            "label": "AWS Region",
            "description": "The AWS region to query (e.g. us-east-1). Use us-east-1 for CLOUDFRONT scope.",
            "parameterType": "string",
            "parameterLength": 32,
            "required": false,
            "defaultValue": "us-east-1"
        },
        {
            "direction": "IN",
            "name": "Scope",
            "label": "Scope",
            "description": "WAFv2 scope: REGIONAL (ALB, API Gateway, AppSync) or CLOUDFRONT (CloudFront distributions)",
            "parameterType": "string",
            "parameterLength": 16,
            "required": false,
            "defaultValue": "REGIONAL"
        }
    ],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "WebACLCount",
            "label": "Web ACL Count",
            "description": "The number of web ACLs returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "RuleGroupCount",
            "label": "Rule Group Count",
            "description": "The number of custom rule groups returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "IPSetCount",
            "label": "IP Set Count",
            "description": "The number of IP sets returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "RegexPatternSetCount",
            "label": "Regex Pattern Set Count",
            "description": "The number of regex pattern sets returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "WafFile",
            "label": "WAF File",
            "description": "The output file name containing the combined WAF rules snapshot",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which WAF rules were retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Region",
            "label": "Region",
            "description": "The AWS region from which WAF rules were retrieved",
            "parameterType": "string",
            "parameterLength": 32,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Scope",
            "label": "Scope",
            "description": "The WAFv2 scope that was queried (REGIONAL or CLOUDFRONT)",
            "parameterType": "string",
            "parameterLength": 16,
            "scope": "GLOBAL"
        }
    ]
}
```
