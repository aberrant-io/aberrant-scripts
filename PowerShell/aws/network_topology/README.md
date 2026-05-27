# network_topology.ps1

### What it does
- Retrieves all VPCs, subnets, and network ACLs in the configured region in a single pass.
- Handles paging (`NextToken`) independently for each resource type.
- Writes a single combined JSON document with three top-level arrays (`Vpcs`, `Subnets`, `NetworkAcls`) plus metadata (`AccountId`, `Region`, `ExportedAt`).
- Each VPC includes CIDR blocks, DHCP options set, tenancy, state, and tags.
- Each subnet includes CIDR, availability zone, available IP count, default/public-IP-on-launch flags, and tags.
- Each network ACL includes all numbered inbound and outbound rules with protocol, port ranges, CIDR, and allow/deny action, plus subnet associations.
- Derives the account ID from `Get-STSCallerIdentity` — no account ID parameter required.
- Returns only the RemoteAgent output manifest JSON to stdout.

### Inputs (contract)
- `AwsRegion` (optional): AWS region to query (e.g. `us-west-2`). Defaults to `us-east-1`.

### Outputs (contract)
- Output parameter `VpcCount`: Number of VPCs returned.
- Output parameter `SubnetCount`: Number of subnets returned.
- Output parameter `NetworkAclCount`: Number of network ACLs returned.
- Output parameter `TopologyFile`: The generated topology filename.
- Output parameter `AccountId`: The AWS account ID topology was retrieved from.
- Output parameter `Region`: The AWS region topology was retrieved from.
- Manifest file evidence: `NetworkTopology_<AccountId>_<Region>_<Timestamp>.json`.

### Prerequisites
- PowerShell 7+ (`pwsh`/`pwsh.exe`) required.
- AWS account/role with permissions for:
  - `ec2:DescribeVpcs`
  - `ec2:DescribeSubnets`
  - `ec2:DescribeNetworkAcls`
  - `sts:GetCallerIdentity`
- AWS Tools for PowerShell modules installed:

```powershell
Install-Module AWS.Tools.Common -Scope AllUsers
Install-Module AWS.Tools.SecurityToken -Scope AllUsers
Install-Module AWS.Tools.EC2 -Scope AllUsers
```

### Credential configuration
Edit the `USER CONFIGURATION` section in `network_topology.ps1`. The script supports exactly one of these methods:
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
.\network_topology.ps1
```

```powershell
.\network_topology.ps1 -AwsRegion us-west-2
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
    "name": "Get AWS Network Topology",
    "description": "Retrieves all VPCs, subnets, and network ACLs for the authenticated AWS account and configured region and writes a combined topology snapshot to JSON",
    "fileName": "network_topology.ps1",
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
            "name": "VpcCount",
            "label": "VPC Count",
            "description": "The number of VPCs returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "SubnetCount",
            "label": "Subnet Count",
            "description": "The number of subnets returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "NetworkAclCount",
            "label": "Network ACL Count",
            "description": "The number of network ACLs returned",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "TopologyFile",
            "label": "Topology File",
            "description": "The output file name containing the combined network topology data",
            "parameterType": "string",
            "parameterLength": 128,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "AccountId",
            "label": "Account ID",
            "description": "The AWS account ID from which topology was retrieved",
            "parameterType": "string",
            "parameterLength": 12,
            "scope": "GLOBAL"
        },
        {
            "direction": "OUT",
            "name": "Region",
            "label": "Region",
            "description": "The AWS region from which topology was retrieved",
            "parameterType": "string",
            "parameterLength": 32,
            "scope": "GLOBAL"
        }
    ]
}
```
