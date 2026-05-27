# rds_inventory.ps1

### What it does
- Lists all RDS DB instances in the configured region with `Get-RDSDBInstance`.
- Lists all RDS DB clusters (Aurora and Multi-AZ clusters) with `Get-RDSDBCluster`.
- Handles paging (`Marker`) independently for each resource type.
- Captures security-relevant fields for each instance: engine and version, encryption at rest, KMS key, public accessibility, Multi-AZ, deletion protection, backup retention, VPC security groups, subnet group, parameter groups, IAM database authentication, Performance Insights, auto minor version upgrade, and tags.
- Captures equivalent fields for clusters plus cluster-specific attributes: reader endpoint, cluster members, and activity stream status.
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Writes a single combined JSON document with two top-level arrays (`DBInstances`, `DBClusters`) plus metadata (`AccountId`, `Region`, `ExportedAt`).
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsRegion` (optional): AWS region to query (e.g. `us-west-2`). Defaults to `us-east-1`.

### Outputs (contract)
- Output parameter `DBInstanceCount`: Number of RDS DB instances returned.
- Output parameter `DBClusterCount`: Number of RDS DB clusters returned.
- Output parameter `InventoryFile`: The generated inventory filename.
- Output parameter `AccountId`: The AWS account ID inventory was retrieved from.
- Output parameter `Region`: The AWS region inventory was retrieved from.
- Manifest file evidence: `RdsInventory_<AccountId>_<Region>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `rds:DescribeDBInstances`
  - `rds:DescribeDBClusters`
  - `sts:GetCallerIdentity`
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.RDS -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `rds_inventory.ps1`. The script supports exactly one of these methods:
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
.\rds_inventory.ps1
```

```powershell
.\rds_inventory.ps1 -AwsRegion us-west-2
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
    "name": "Get AWS RDS Inventory",
    "description": "Retrieves all RDS DB instances and clusters for the authenticated AWS account and region and writes a combined inventory snapshot to JSON",
    "fileName": "rds_inventory.ps1",
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
        }
    ],
    "outputParameters": [
        {
            "direction": "OUT",
            "name": "DBInstanceCount",
            "label": "DB Instance Count",
            "description": "The number of RDS DB instances returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "DBClusterCount",
            "label": "DB Cluster Count",
            "description": "The number of RDS DB clusters returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "InventoryFile",
            "label": "Inventory File",
            "description": "The output file name containing the combined RDS inventory data",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which the inventory was retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Region",
            "label": "Region",
            "description": "The AWS region from which the inventory was retrieved",
            "parameterType": "string",
            "parameterLength": 32,
            "scope": "GLOBAL"
        }
    ]
}
```
