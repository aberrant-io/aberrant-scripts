---
title: Inspector Findings Script
date: 2026-05-26
status: approved
---

# Inspector Findings Script

## Goal

Replace the copied `securityhub_findings.ps1` in `PowerShell/aws/inspector_findings/` with a script that queries AWS Inspector v2 directly, returning richer native Inspector data without requiring Security Hub to be enabled.

## Files Changed

| File | Change |
|------|--------|
| `PowerShell/aws/inspector_findings/securityhub_findings.ps1` | Rename to `inspector_findings.ps1`, rewrite for Inspector v2 |
| `PowerShell/aws/inspector_findings/contract.json` | Update name, description, fileName, and status parameter |

## Script: inspector_findings.ps1

### Modules

Remove `AWS.Tools.SecurityHub`. Add `AWS.Tools.Inspector2`. Keep `AWS.Tools.Common` and `AWS.Tools.SecurityToken`.

### Parameters

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `AwsAccountId` | string | yes | — | 12-digit AWS account ID |
| `FindingStatus` | string | no | `ACTIVE` | `ACTIVE`, `SUPPRESSED`, `CLOSED`, or `ALL` |

`FindingStatus` replaces `ComplianceStatus`. Inspector's native status values map more directly to finding lifecycle than Security Hub's compliance values.

### Authentication

Unchanged from `securityhub_findings.ps1`. Credential store key renamed from `aberrant_securityhub_temp` to `aberrant_inspector_temp`.

### Query

Build an `Amazon.Inspector2.Model.FilterCriteria` object with:
- `AwsAccountId` list containing one `StringFilter` with `Comparison = "EQUALS"` and the provided account ID
- `FindingStatus` list (omitted when `ALL`) containing one `StringFilter` with `Comparison = "EQUALS"` and the provided status

Call `Get-INS2FindingList` with `-FilterCriteria`, `-MaxResult 100`, and `-NextToken` for pagination. Paginate until `NextToken` is null/empty, accumulating all findings into `$allFindings`.

### Output

- Output file: `InspectorFindings_<AwsAccountId>_<yyyyMMdd_HHmmss>.json`
- Written to `.\Output\` directory (created if absent, write-tested before use)
- JSON serialized with `ConvertTo-Json -Depth 20`
- Script stdout: JSON object with `Parameters` (`FindingsCount`, `FindingsFile`) and `Manifest` (`Files`, `Links`)

## contract.json

- `name`: `"Get AWS Inspector Findings"`
- `description`: `"Retrieves AWS Inspector v2 findings for a specific AWS account and writes results to JSON"`
- `fileName`: `"inspector_findings.ps1"`
- Input parameter `ComplianceStatus` renamed to `FindingStatus`, description and `defaultValue` updated to `ACTIVE`, valid values noted as `ACTIVE`, `SUPPRESSED`, `CLOSED`, or `ALL`
- Output parameters (`FindingsCount`, `FindingsFile`) unchanged
