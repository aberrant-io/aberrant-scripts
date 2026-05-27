# AWS Scripts
Powershell scripts for interacting with AWS services with the [Aberrant](https://www.aberrant.io/) RemoteAgent

## Contents

| Script| Description |
| -------- | ------- |
| securityhub_findings.ps1  | Retrieves AWS Security Hub findings filtered by account ID and optional compliance status, and writes findings to `Output/SecurityHubFindings_<AccountId>_<Timestamp>.json`. |
| inspector_findings.ps1  | Retrieves AWS Inspector v2 findings directly, filtered by account ID and optional finding status, and writes findings to `Output/InspectorFindings_<AccountId>_<Timestamp>.json`. |
| iam_users.ps1  | Retrieves all IAM users for the authenticated AWS account with full attribute set (access keys, MFA devices, groups, policies, tags, console access), and writes results to `Output/IamUsers_<AccountId>_<Timestamp>.json`. |
| security_groups.ps1  | Retrieves all EC2 security groups for the authenticated AWS account and configured region with full inbound/outbound rule detail and tags, and writes results to `Output/SecurityGroups_<AccountId>_<Region>_<Timestamp>.json`. |
| network_topology.ps1  | Retrieves all VPCs, subnets, and network ACLs for the authenticated AWS account and configured region and writes a combined topology snapshot to `Output/NetworkTopology_<AccountId>_<Region>_<Timestamp>.json`. |
| waf_rules.ps1  | Retrieves all WAFv2 web ACLs (with full rule detail), custom rule groups, IP sets, and regex pattern sets for the authenticated AWS account and writes a combined snapshot to `Output/WafRules_<AccountId>_<Scope>_<Region>_<Timestamp>.json`. |
| rds_inventory.ps1  | Retrieves all RDS DB instances and clusters for the authenticated AWS account and region with security-relevant fields (encryption, public accessibility, VPC placement, IAM auth, backup retention), and writes results to `Output/RdsInventory_<AccountId>_<Region>_<Timestamp>.json`. |
| guardduty_findings.ps1  | Retrieves GuardDuty findings updated within a configurable lookback window (default 30 days) for the authenticated AWS account and region, and writes results to `Output/GuardDutyFindings_<AccountId>_<Region>_<LookbackDays>d_<Timestamp>.json`. |
