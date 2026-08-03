# Centralized Observability Platform — Azure Log Analytics

Terraform module suite for deploying a production-grade, centralized observability stack on Azure. The platform provisions a shared **Log Analytics Dedicated Cluster** with Customer-Managed Key (CMK) encryption, a **hub-peered spoke VNet** with private endpoints, registration against a **centrally-managed AMPLS** for fully private agent traffic, and an **Azure Monitor Workspace** (managed Prometheus) integrated with an externally-provided Grafana instance. Consumer teams receive isolated, RBAC-controlled Log Analytics workspaces billed separately through dedicated resource groups.

---

## Table of Contents

1. [High-Level Design](#high-level-design)
2. [Repository Structure](#repository-structure)
3. [Prerequisites](#prerequisites)
4. [Deployment Guide](#deployment-guide)
5. [Onboarding a Consumer](#onboarding-a-consumer)
6. [Access Control Model](#access-control-model)
7. [Network Architecture](#network-architecture)
8. [AMPLS Integration](#ampls-integration)
9. [Prometheus and Grafana Integration](#prometheus-and-grafana-integration)
10. [Encryption and Key Management](#encryption-and-key-management)
11. [Billing Isolation](#billing-isolation)
12. [Day-2 Operations](#day-2-operations)
13. [Variable Reference](#variable-reference)

---

## High-Level Design

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  Azure Subscription                                                              │
│                                                                                  │
│  ┌───────────────────────────────┐      ┌─────────────────────────────────────┐ │
│  │  Hub VNet  [Network Team]     │◄────►│  rg-observability-network-prod      │ │
│  │  ─────────────────────────── │ peer │  vnet-observability-prod (spoke)    │ │
│  │  · AMPLS private endpoint     │      │  ─────────────────────────────────  │ │
│  │  · VPN / ExpressRoute (opt.)  │      │  snet-private-endpoints             │ │
│  │  · Azure Firewall (opt.)      │      │  · Key Vault PE                     │ │
│  │  · Private DNS zones          │      │  · NSG — deny internet inbound      │ │
│  └───────────────────────────────┘      │  · Optional UDR → hub firewall      │ │
│                                         └─────────────────────────────────────┘ │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │  rg-observability-platform-prod                        [Platform Team]     │ │
│  │                                                                            │ │
│  │  ┌─────────────────────┐  ┌──────────────────┐  ┌───────────────────────┐│ │
│  │  │  Key Vault (Premium)│  │  User-Assigned   │  │  Azure Monitor        ││ │
│  │  │  ─────────────────  │  │  Managed Identity│  │  Workspace            ││ │
│  │  │  RSA-HSM 4096 key   │  │  (cluster)       │  │  ──────────────────── ││ │
│  │  │  Auto-rotate 90d    │◄─┤  KV Crypto Svc   │  │  Managed Prometheus   ││ │
│  │  │  Purge protection   │  │  Encryption User  │  │  PromQL query EP      ││ │
│  │  │  Private EP in spoke│  └──────────────────┘  │  Prometheus DCR       ││ │
│  │  └──────────┬──────────┘                         └───────────┬───────────┘│ │
│  │             │ CMK wraps DEK                                   │            │ │
│  │             ▼                                                 │            │ │
│  │  ┌──────────────────────┐                                     │            │ │
│  │  │  LA Dedicated Cluster│                                     │            │ │
│  │  │  ─────────────────── │                                     │            │ │
│  │  │  100+ GB/day tier    │                                     │            │ │
│  │  │  CMK encrypted       │                                     │            │ │
│  │  │  CanNotDelete lock   │                                     │            │ │
│  │  └──────────┬───────────┘                                     │            │ │
│  │             │ linked                                          │            │ │
│  │             ▼                                                 │            │ │
│  │  ┌──────────────────────┐  ←──────────────────────────────────┘            │ │
│  │  │  law-platform-prod   │  Audit logs, infra telemetry, Activity Log       │ │
│  │  │  CanNotDelete lock   │                                                  │ │
│  │  └──────────────────────┘                                                  │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌───────────────────────────────────┐  [Network / Security Team — central]     │
│  │  Azure Monitor Private Link Scope │                                          │
│  │  ─────────────────────────────── │                                          │
│  │  Scoped: law-platform-prod        │  All agent traffic (logs, heartbeats,    │
│  │  Scoped: law-{consumer}-prod ×N   │  metrics) flows through the hub PE.      │
│  │  Scoped: Azure Monitor Workspace  │  No public endpoints for agents.         │
│  └───────────────────────────────────┘                                          │
│                                                                                  │
│  ┌─────────────────────────┐  ┌─────────────────────────┐   [per consumer]     │
│  │  rg-obs-team-alpha-prod │  │  rg-obs-team-beta-prod  │                      │
│  │  law-team-alpha-prod    │  │  law-team-beta-prod      │                      │
│  │  ───────────────────── │  │  ───────────────────────  │                      │
│  │  Linked → cluster       │  │  Linked → cluster        │                      │
│  │  RBAC: Contributor      │  │  RBAC: Contributor       │                      │
│  │  RBAC: Reader           │  │  RBAC: Reader            │                      │
│  │  Scoped in AMPLS        │  │  Scoped in AMPLS         │                      │
│  │  CanNotDelete lock      │  │  CanNotDelete lock       │                      │
│  └─────────────────────────┘  └─────────────────────────┘                      │
│                                                                                  │
│  ┌───────────────────────────────────────────────┐  [external — Grafana Team]  │
│  │  Azure Managed Grafana                        │                              │
│  │  ─────────────────────────────────────────── │                              │
│  │  Data source: Prometheus  → AMW PromQL EP     │                              │
│  │  Data source: Azure Monitor → Log Analytics   │                              │
│  │  Grafana MI: Monitoring Reader on AMW         │                              │
│  │  Grafana MI: Log Analytics Reader on all WSs  │                              │
│  └───────────────────────────────────────────────┘                              │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Encryption at rest** | CMK via Key Vault Premium (RSA-HSM 4096). All data on the cluster — including every linked workspace — is encrypted with this key before writing to storage. |
| **Key hygiene** | Automatic key rotation 90 days before expiry. The cluster uses the versionless key URI, so rotation is transparent with zero downtime. |
| **Fully private networking** | Spoke VNet peers to the hub. All private endpoints land in `snet-private-endpoints`. Agent traffic flows through the central AMPLS private endpoint — no Azure Monitor public endpoints are used. |
| **Data isolation** | Each consumer has its own workspace. Log Analytics enforces query-scope boundaries — a user with access to workspace A cannot query workspace B, regardless of cluster sharing. |
| **Billing isolation** | One resource group per consumer. Azure Cost Management filters by RG for per-team chargeback. |
| **Least-privilege RBAC** | RBAC scoped to individual workspaces, not resource groups. Grafana authenticates via managed identity — no stored credentials. |
| **Metrics and logs in one platform** | Logs in Log Analytics (KQL). Metrics in Azure Monitor Workspace (PromQL). Both exposed to Grafana via separate data sources, both covered by AMPLS. |
| **Deletion protection** | `CanNotDelete` management locks on every resource group, including consumer RGs. |
| **Infrastructure as Code** | All resources, RBAC assignments, peerings, AMPLS registrations, and Grafana data sources are managed in Terraform. |

---

## Repository Structure

```
.
├── providers.tf              # Terraform, AzureRM, AzureAD, Grafana providers + backend
├── variables.tf              # All root-level variables with validation
├── locals.tf                 # Common tag map
├── main.tf                   # Root — calls all five modules in dependency order
├── outputs.tf                # All outputs including Prometheus EP and Grafana summary
├── grafana_datasources.tf    # Optional Grafana data source + folder resources
├── terraform.tfvars.example  # Annotated variable values template
├── backend.conf.example      # Remote state backend configuration template
│
└── modules/
    ├── networking/               # Spoke VNet, subnets, NSG, hub peering, UDR
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── log-analytics-cluster/    # Dedicated cluster, Key Vault/CMK, platform workspace
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── consumer-workspace/       # Per-consumer: RG, workspace, cluster link, RBAC
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── ampls/                    # Registers workspaces against central AMPLS
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── prometheus/               # Azure Monitor Workspace, Prometheus DCR, Grafana RBAC
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Module responsibilities and ownership

| Module | Owned by | Creates | Consumes externally |
|--------|----------|---------|---------------------|
| `networking` | Platform team | Spoke VNet, subnets, NSG, spoke→hub peering | Hub VNet ID |
| `log-analytics-cluster` | Platform team | Key Vault, CMK, dedicated cluster, platform workspace | Subnet ID from `networking` |
| `consumer-workspace` | Platform team | Consumer RG + workspace + RBAC | Cluster ID from `log-analytics-cluster` |
| `ampls` | Platform team | AMPLS scoped services | Central AMPLS name + RG |
| `prometheus` | Platform team | Azure Monitor Workspace, Prometheus DCR, Grafana RBAC | Platform + consumer workspace IDs |
| `grafana_datasources.tf` | Platform team (optional) | Grafana data sources + folder | Grafana URL + service account token |

---

## Prerequisites

### Tooling

| Tool | Minimum version | Notes |
|------|----------------|-------|
| Terraform | 1.5.0 | |
| AzureRM provider | 3.100 | |
| Grafana provider | 3.0 | Only needed when `grafana_endpoint` is set |
| Azure CLI | 2.50 | Used for authentication |

### Azure permissions required by the deploying identity

| Scope | Role | Purpose |
|-------|------|---------|
| Target subscription | `Contributor` | Create resource groups and all resources |
| Target subscription | `User Access Administrator` | Create role assignments |
| Hub VNet resource group | `Network Contributor` | Create hub→spoke peering (only when `manage_hub_peering = true`) |
| AMPLS resource group | `Contributor` | Create scoped service entries in the central AMPLS |
| Key Vault (post-creation) | `Key Vault Administrator` | Created automatically by Terraform, scoped to the vault |

> **Recommended:** Combine `Contributor` + `User Access Administrator` into a custom role scoped to the subscription. Add `Network Contributor` on the hub VNet RG as a separate assignment to maintain least-privilege on hub resources.

### Central infrastructure required before first apply

These resources must exist and be managed externally before running this module:

| Resource | Managed by | Used for |
|----------|-----------|---------|
| Hub VNet | Network team | VNet peering target |
| `privatelink.vaultcore.azure.net` private DNS zone | Network / DNS team | Key Vault private endpoint resolution |
| Azure Monitor Private Link Scope (AMPLS) | Network / Security team | Agent traffic private routing |
| AMPLS private endpoint in hub VNet | Network / Security team | DNS resolution and network path for agents |
| Private DNS zones for Azure Monitor (×5) | Network / DNS team | Agent hostname resolution through AMPLS |
| Azure Managed Grafana instance | Grafana team | Metrics and log visualisation |

**Required private DNS zones for AMPLS** (must be linked to hub VNet and resolvable from spoke via peering):

```
privatelink.ods.opinsights.azure.com
privatelink.oms.opinsights.azure.com
privatelink.agentsvc.azure-automation.net
privatelink.blob.core.windows.net
privatelink.monitor.azure.com
```

### Remote state storage

Provision an Azure Storage Account for Terraform state **before** running this module (one-time, out-of-band):

```bash
az group create -n rg-terraform-state-prod -l westeurope

az storage account create \
  --name sttfstatecontosoxx \
  --resource-group rg-terraform-state-prod \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

az storage container create \
  --name tfstate-observability \
  --account-name sttfstatecontosoxx \
  --auth-mode login

# Enable versioning and soft-delete for state file protection
az storage account blob-service-properties update \
  --account-name sttfstatecontosoxx \
  --resource-group rg-terraform-state-prod \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30
```

---

## Deployment Guide

### 1. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Fill in all required values — see Variable Reference
```

> **Security:** Never commit `terraform.tfvars`. Inject via CI/CD secrets or a secrets manager. Pass `grafana_service_account_token` via the `TF_VAR_grafana_service_account_token` environment variable — never in a file.

### 2. Configure the backend

```bash
cp backend.conf.example backend.conf
# Fill in storage account name, container name, state key
```

### 3. Authenticate

```bash
# Interactive
az login
az account set --subscription "<subscription_id>"

# CI/CD service principal
export ARM_CLIENT_ID="<sp-client-id>"
export ARM_CLIENT_SECRET="<sp-client-secret>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

### 4. Initialise

```bash
terraform init -backend-config="backend.conf"
```

This pulls three providers: `hashicorp/azurerm`, `hashicorp/azuread`, and `grafana/grafana`.

### 5. Plan and review

```bash
terraform plan -var-file="terraform.tfvars" -out=tfplan
```

The first apply creates:

| # | Resources | Notes |
|---|-----------|-------|
| 1 | Network RG + spoke VNet + subnet + NSG + peering(s) | Immediate |
| 2 | Platform RG + managed identity + Key Vault + CMK key + KV private endpoint | Immediate |
| 3 | Log Analytics Dedicated Cluster | **10–15 min to provision** |
| 4 | CMK attachment to cluster | After cluster reaches `Succeeded` |
| 5 | Platform workspace + cluster link + diagnostic setting | After CMK attached |
| 6 | N × consumer RG + workspace + cluster link + RBAC + diagnostic setting | After platform workspace |
| 7 | Azure Monitor Workspace + Prometheus DCR + Grafana RBAC assignments | After consumer workspaces |
| 8 | AMPLS scoped services (platform + consumers + AMW) | After all workspaces and AMW |
| 9 | Grafana data sources + folder (if `grafana_endpoint` set) | After AMW |

Total first-apply time: **25–35 minutes** (dominated by cluster provisioning).

### 6. Apply

```bash
terraform apply tfplan
```

### 7. Verify

```bash
# Cluster state
az monitor log-analytics cluster show \
  --name lac-observability-prod \
  --resource-group rg-observability-platform-prod \
  --query "provisioningState" -o tsv

# Linked workspaces on the platform workspace
az monitor log-analytics workspace linked-service list \
  --workspace-name law-platform-prod \
  --resource-group rg-observability-platform-prod \
  --query "[].properties.resourceId" -o tsv

# AMPLS scoped services
az monitor private-link-scope scoped-resource list \
  --scope-name "<ampls-name>" \
  --resource-group "<ampls-rg>" \
  --query "[].properties.linkedResourceId" -o tsv

# Azure Monitor Workspace (Prometheus)
az monitor account show \
  --name amw-observability-prod \
  --resource-group rg-observability-platform-prod \
  --query "metrics.prometheusQueryEndpoint" -o tsv

# Spoke→hub peering state
az network vnet peering show \
  --name "peer-obs-prod-to-hub" \
  --vnet-name vnet-observability-prod \
  --resource-group rg-observability-network-prod \
  --query "peeringState" -o tsv
```

### 8. Share Grafana datasource info (if Grafana integration is manual)

When `grafana_endpoint` is not set, retrieve the values the Grafana team needs:

```bash
terraform output -json grafana_datasource_summary
```

```json
{
  "prometheus_url":                 "https://<workspace>.westeurope.prometheus.monitor.azure.com",
  "azure_monitor_workspace_id":     "/subscriptions/.../amw-observability-prod",
  "platform_workspace_customer_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "subscription_id":                "00000000-...",
  "tenant_id":                      "00000000-..."
}
```

---

## Onboarding a Consumer

All consumer provisioning is a single `terraform.tfvars` edit — no code changes required.

### Step 1 — Collect AAD security group object IDs

```bash
# Retrieve group object ID by display name
az ad group show --group "sg-team-delta-sre" --query id -o tsv
az ad group show --group "sg-team-delta-devs" --query id -o tsv
```

> Always use **AAD security groups**, not individual user accounts. Group membership is managed by the team lead or identity governance, not by Terraform.

### Step 2 — Add the consumer block to `terraform.tfvars`

```hcl
consumers = {
  # ... existing consumers ...

  "team-delta" = {
    retention_in_days      = 90
    workspace_contributors = ["<object-id-of-sg-team-delta-sre>"]
    workspace_readers      = ["<object-id-of-sg-team-delta-devs>"]
    extra_tags = {
      cost_center = "delta-004"
      team        = "Delta"
    }
  }
}
```

**Consumer key naming rules:** 2–20 characters, lowercase alphanumeric and hyphens only.

| Resource | Generated name |
|----------|---------------|
| Resource group | `rg-observability-team-delta-prod` |
| Log Analytics workspace | `law-team-delta-prod` |

### Step 3 — Plan and apply

```bash
terraform plan -var-file="terraform.tfvars" -out=tfplan
terraform apply tfplan
```

Terraform creates per consumer:

1. `rg-observability-team-delta-prod` — resource group with `CanNotDelete` lock
2. `law-team-delta-prod` — Log Analytics workspace (PerGB2018 SKU, linked to dedicated cluster)
3. AMPLS scoped service — registers the workspace in the central AMPLS automatically
4. Role assignment: **Log Analytics Contributor** → SRE group
5. Role assignment: **Log Analytics Reader** → developer group
6. **Log Analytics Reader** for Grafana managed identity — workspace is immediately queryable in Grafana
7. Diagnostic setting forwarding workspace audit logs to itself

### Step 4 — Hand off to the consumer team

```bash
terraform output -json consumer_workspaces | jq '.["team-delta"]'
```

```json
{
  "resource_group_name":   "rg-observability-team-delta-prod",
  "workspace_id":          "/subscriptions/.../workspaces/law-team-delta-prod",
  "workspace_name":        "law-team-delta-prod",
  "workspace_customer_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Hand off:
- `workspace_customer_id` → needed when configuring Azure Monitor Agent, DCRs, and Diagnostic Settings
- `prometheus_dcr_id` output → needed when associating the Prometheus DCR with AKS clusters
- Grafana team is notified that a new workspace is available (role assignments already in place)

### Step 5 — AKS Prometheus scraping (consumer side)

Consumer teams associate the platform Prometheus DCR with their AKS clusters to enable managed Prometheus metric scraping. This is done in the consumer team's own Terraform:

```hcl
data "terraform_remote_state" "observability" {
  backend = "azurerm"
  config = {
    storage_account_name = "sttfstatecontosoxx"
    container_name       = "tfstate-observability"
    key                  = "observability/prod/terraform.tfstate"
  }
}

resource "azurerm_monitor_data_collection_rule_association" "aks_prometheus" {
  name                    = "dcra-aks-team-delta-prometheus"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = data.terraform_remote_state.observability.outputs.prometheus_dcr_id
}
```

### Offboarding a consumer

Remove the consumer's entry from `terraform.tfvars` and apply. Terraform removes:

1. Log Analytics Reader role assignment for Grafana MI
2. Log Analytics Contributor / Reader assignments for consumer groups
3. AMPLS scoped service for the workspace
4. Workspace cluster link
5. Log Analytics workspace and all its data
6. Management lock
7. Resource group

> **Warning:** Workspace deletion is irreversible. Log data is permanently lost. Confirm the team has exported or archived any data before offboarding.

---

## Access Control Model

### RBAC layers

```
Subscription
├── rg-observability-network-prod        [Platform team — Contributor]
│   └── VNet, subnets, NSG, peerings
│
├── rg-observability-platform-prod       [Platform team — Contributor]
│   ├── Key Vault                        [Deployer SP — Key Vault Administrator]
│   │                                    [Cluster MI — KV Crypto Svc Encryption User]
│   ├── Dedicated Cluster
│   ├── Azure Monitor Workspace          [Grafana MI — Monitoring Reader]
│   └── law-platform-prod                [Grafana MI — Log Analytics Reader]
│
└── rg-observability-{consumer}-prod     [Platform team — Contributor]
    └── law-{consumer}-prod
        ├── Log Analytics Contributor    ← DevOps / SRE groups
        ├── Log Analytics Reader         ← Developer / stakeholder groups
        └── Log Analytics Reader         ← Grafana managed identity
```

### Role capabilities matrix

| Identity | Query logs | Configure workspace | Create DCRs | Read KV keys | Query Prometheus |
|----------|:-:|:-:|:-:|:-:|:-:|
| Log Analytics Contributor | Yes | Yes | Yes | No | No |
| Log Analytics Reader | Yes | No | No | No | No |
| Platform team (Contributor on platform RG) | Yes (all) | Yes | Yes | No | Yes |
| Grafana managed identity | Yes (all workspaces) | No | No | No | Yes (AMW) |
| Cluster managed identity | No | No | No | Unwrap only | No |
| Deployer SP | Yes | Yes | Yes | Yes (KV Admin) | Yes |

### Isolation guarantees

- **Query isolation:** Log Analytics enforces workspace boundaries on the query layer. A user with `Log Analytics Reader` on `law-team-alpha-prod` cannot query `law-team-beta-prod`, even though both share the same dedicated cluster.
- **Encryption isolation:** All cluster data shares one CMK. Revoking the key affects all workspaces simultaneously — there is no per-workspace key. Use separate clusters if you need per-tenant key isolation.
- **Network isolation:** AMPLS private mode (`Open` vs `PrivateOnly`) is configured centrally. Once set to `PrivateOnly`, agents without private endpoint connectivity cannot ingest data. Confirm the AMPLS access mode with the central team before onboarding.
- **Grafana isolation:** Grafana uses MSI authentication. The MI has `Log Analytics Reader` on each workspace — consumers see their own workspace's data in Grafana; there is no cross-workspace query bleed unless a dashboard author explicitly uses cross-workspace KQL.

### Granting temporary elevated access

For break-glass or incident response, use PIM for time-bound assignments:

```bash
az role assignment create \
  --role "Log Analytics Reader" \
  --assignee "<user-object-id>" \
  --scope "<workspace-resource-id>" \
  --description "Incident response — ticket #INC-12345 — expires 2026-06-15"
```

Remove immediately after the incident. Do not add ad-hoc assignments to `terraform.tfvars`.

---

## Network Architecture

### Topology overview

```
On-premises / other VNets
        │
        │ VPN / ExpressRoute
        ▼
┌──────────────────────────────┐
│  Hub VNet  [Network Team]    │
│                              │
│  ┌──────────────────────┐   │
│  │  AMPLS Private EP    │   │
│  │  Azure Firewall      │   │
│  │  VPN / ER Gateway    │   │
│  └──────────────────────┘   │
│          ▲  │               │
│          │  │ VNet Peering  │
└──────────┼──┼───────────────┘
           │  │
           │  ▼
┌──────────────────────────────┐
│  Spoke: vnet-obs-prod        │
│  [Platform Team]             │
│                              │
│  snet-private-endpoints      │
│  ┌──────────────────────┐   │
│  │  Key Vault PE (NIC)  │   │
│  │  NSG attached        │   │
│  │  UDR → hub FW (opt.) │   │
│  └──────────────────────┘   │
└──────────────────────────────┘
```

### Hub peering

| Variable | Default | Description |
|----------|---------|-------------|
| `hub_vnet_id` | required | Resource ID of the hub VNet |
| `manage_hub_peering` | `false` | When `true`, Terraform creates hub→spoke peering (needs hub RG Contributor) |
| `use_hub_gateway` | `false` | Set `true` when hub hosts a VPN/ER gateway for transit routing |
| `hub_firewall_private_ip` | `null` | When set, a `0.0.0.0/0` UDR routes spoke traffic through the hub NVA |

When `manage_hub_peering = false`, provide the `spoke_vnet_id` output to the network team:

```bash
terraform output spoke_vnet_id
```

They must create the hub-side peering with:
- `allow_forwarded_traffic = true`
- `allow_gateway_transit = true` (if hub has a gateway)
- `use_remote_gateways = false`

### Key Vault private endpoint

The Key Vault private endpoint is placed in `snet-private-endpoints` of the spoke VNet. The subnet ID is wired automatically from the `networking` module output — no raw subnet ID string is required in `terraform.tfvars`.

```
Key Vault (private EP only)
    │
    │ Private NIC in snet-private-endpoints
    │
    ▼
DNS: kv-name.privatelink.vaultcore.azure.net → PE NIC IP
     (resolved via hub Private DNS zone, propagated through peering)
```

For the Terraform pipeline runner to manage the Key Vault during apply, it must have network connectivity to the spoke VNet (e.g., a self-hosted agent deployed in the VNet, or a VNet-integrated runner).

**Bootstrap without private connectivity:**

```hcl
key_vault_public_network_access_enabled = true
key_vault_allowed_ips                   = ["<ci-runner-egress-ip>/32"]
```

Lock it down after the private endpoint is established by resetting to:

```hcl
key_vault_public_network_access_enabled = false
key_vault_allowed_ips                   = []
```

---

## AMPLS Integration

### What AMPLS does

Azure Monitor Private Link Scope (AMPLS) acts as a single private endpoint for all Azure Monitor traffic. Once a workspace is registered as a scoped service and the AMPLS access mode is set to `PrivateOnly`, agents on private networks route all Log Analytics ingestion, heartbeats, and custom log uploads through the hub's AMPLS private endpoint — completely bypassing public internet.

### What this module does

This module **does not create the AMPLS** — it is provided centrally by the network/security team. This module registers resources as scoped services:

| Scoped service | Resource |
|---|---|
| `ampls-svc-law-platform-prod` | Platform Log Analytics workspace |
| `ampls-svc-{consumer}` | Each consumer Log Analytics workspace |
| `ampls-svc-prometheus` | Azure Monitor Workspace (managed Prometheus) |

The registration runs after all workspaces and the AMW exist (enforced via `depends_on`).

### Required permissions

The deploying SP needs `Contributor` on `var.ampls_resource_group_name` to create scoped service resources under the central AMPLS. Confirm this with the team that owns the AMPLS before the first apply.

### AMPLS access modes

AMPLS has two access modes that the central team controls:

| Mode | Behaviour |
|------|-----------|
| `Open` | Private endpoint preferred; public endpoints still accessible as fallback. Safe during migration. |
| `PrivateOnly` | Public endpoints completely blocked. Agents without PE connectivity cannot ingest. Full production hardening. |

Coordinate with the central team on which mode is active. If `PrivateOnly` is already enforced, all agents must be on the private network before workspaces are linked or they will lose connectivity.

---

## Prometheus and Grafana Integration

### Architecture

```
AKS Cluster / VM
    │
    │ Azure Monitor Agent
    │ (DCRA → Prometheus DCR)
    ▼
Azure Monitor Workspace (AMW)
    │  PromQL query endpoint
    │  (private via AMPLS)
    ▼
Grafana [external team]
    │
    ├── Data source: Prometheus  → AMW PromQL EP
    └── Data source: Azure Monitor → Log Analytics workspaces (KQL)
```

### Azure Monitor Workspace

The `prometheus` module creates an `azurerm_monitor_workspace` — the Azure-native Prometheus store. It is distinct from Log Analytics:

| | Log Analytics Workspace | Azure Monitor Workspace |
|--|------------------------|------------------------|
| Data type | Logs (structured events) | Metrics (time-series) |
| Query language | KQL | PromQL |
| Retention | 30–730 days | 18 months (fixed) |
| AMPLS support | Yes | Yes |
| Grafana data source type | `grafana-azure-monitor-datasource` | `prometheus` |

### Prometheus Data Collection Rule (DCR)

A reusable DCR is provisioned that captures all Prometheus metrics labels and forwards them to the AMW. Consumer teams associate it with their AKS clusters:

```hcl
# In the consumer team's own Terraform
resource "azurerm_monitor_data_collection_rule_association" "aks" {
  name                    = "dcra-aks-${var.team_name}-prometheus"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = "<prometheus_dcr_id>"   # from terraform output
}
```

Get the DCR resource ID:

```bash
terraform output prometheus_dcr_id
```

### Grafana integration

The external Grafana instance authenticates to Azure using its **managed identity** — no stored credentials. The `prometheus` module grants:

- `Monitoring Reader` on the Azure Monitor Workspace → enables PromQL queries
- `Log Analytics Reader` on the platform workspace → enables KQL log queries
- `Log Analytics Reader` on each consumer workspace → per-team log queries in Grafana

#### Automated data source provisioning

When `grafana_endpoint` and `grafana_service_account_token` are both set, `grafana_datasources.tf` configures two data sources and a folder directly in the Grafana instance via the `grafana/grafana` Terraform provider:

| Data source | Grafana type | Auth | Query target |
|-------------|-------------|------|--------------|
| `Azure Managed Prometheus — prod` | `prometheus` | MSI | AMW PromQL endpoint |
| `Azure Monitor — prod` | `grafana-azure-monitor-datasource` | MSI | All Log Analytics workspaces |

Set variables (the token should never be in a file):

```bash
export TF_VAR_grafana_service_account_token="<service-account-token>"
```

```hcl
# terraform.tfvars
grafana_endpoint = "https://grafana.contoso.com"
```

#### Manual data source provisioning

When Grafana credentials are not available, retrieve the information and hand it to the Grafana team:

```bash
terraform output -json grafana_datasource_summary
```

The Grafana team uses:

1. **Prometheus data source** — type `Prometheus`, URL from `prometheus_url` output, auth `Azure Managed Identity`
2. **Azure Monitor data source** — type `Azure Monitor`, subscription ID and tenant ID from output, auth `Managed Identity`

The Grafana instance's managed identity must already have the RBAC assignments applied by this module before they can query data.

---

## Encryption and Key Management

### How CMK works in this setup

```
Write path:
  Agent / DCR → Log Analytics Workspace → Dedicated Cluster → Azure Storage
                                                    │
                                           CMK wraps DEK before write
                                                    │
                                          Key Vault HSM (RSA-HSM 4096)
                                          unwraps the Data Encryption Key
```

The cluster holds a Data Encryption Key (DEK) wrapped by the Key Encryption Key (KEK) in Key Vault. Azure never stores the unwrapped KEK. Revoking the Key Vault key prevents the cluster from unwrapping the DEK, making all data inaccessible — this is the BYOK guarantee.

### Key rotation

The key is configured for automatic rotation:

- Expires after `key_expiry_days` days (default: 365)
- A new version is created **90 days before** expiry
- The cluster uses the **versionless** key URI — rotation is transparent, no Terraform changes needed
- An expiry notification fires **30 days before** expiry as a safety net

Manual rotation (e.g., after suspected compromise):

```bash
az keyvault key rotate \
  --vault-name kv-law-cmk-contoso-prod \
  --name log-analytics-cmk
```

### Revoking the CMK

Use only as a last resort (data breach response). All cluster data becomes inaccessible:

```bash
# Recoverable: disable the key
az keyvault key set-attributes \
  --vault-name kv-law-cmk-contoso-prod \
  --name log-analytics-cmk \
  --enabled false

# Also recoverable: remove the cluster identity's role assignment
az role assignment delete \
  --role "Key Vault Crypto Service Encryption User" \
  --assignee "<cluster-managed-identity-principal-id>" \
  --scope "<key-vault-resource-id>"
```

To restore: re-enable the key or recreate the role assignment. Allow 30–60 minutes for the cluster to resume.

---

## Billing Isolation

### Dedicated cluster pricing

The cluster bills on a commitment tier (GB/day), shared across all linked workspaces:

| Tier | GB/day | Approx. monthly |
|------|--------|----------------|
| 100 | 100 | ~$2,700 |
| 200 | 200 | ~$5,400 |
| 500 | 500 | ~$13,400 |
| 1000 | 1,000 | ~$26,800 |

*(Prices vary by region. Use the Azure Pricing Calculator for accurate figures.)*

Ingestion above the committed tier is billed at the standard PerGB2018 overage rate.

### Azure Monitor Workspace pricing

The AMW (managed Prometheus) bills separately per metric sample ingested and queried. It is not covered by the Log Analytics commitment tier. Review Azure Monitor pricing for current rates.

### Per-consumer cost allocation

Each consumer has its own resource group (`rg-observability-{consumer}-{env}`). Use Azure Cost Management:

- **Tag filter:** Every resource has `consumer = <name>` and `cost_center = <value>` tags
- **RG scope:** Filter Cost Management to `rg-observability-team-alpha-prod` for that team's workspace costs
- **Budget alerts:** Add `azurerm_consumption_budget_resource_group` per consumer RG

### Scaling the cluster

Review cluster utilisation monthly. Adjust in `terraform.tfvars`:

```hcl
cluster_capacity_reservation_gb = 200  # Up from 100
```

```bash
terraform plan -var-file="terraform.tfvars" -out=tfplan
terraform apply tfplan
```

Scaling is non-disruptive — workspaces continue ingesting during the tier change.

---

## Day-2 Operations

### Changing workspace retention for a consumer

```hcl
"team-beta" = {
  retention_in_days = 365  # increased from 180 — compliance requirement
  ...
}
```

Apply and Terraform updates only the workspace retention property.

### Adding a new RBAC group to an existing consumer

Add the AAD group object ID to `workspace_contributors` or `workspace_readers` and apply. Existing assignments are not touched.

### Adding a new consumer workspace to Grafana

Terraform handles this automatically. When a new consumer is added:

1. The workspace is linked to the cluster
2. An AMPLS scoped service is registered
3. The `prometheus` module's `for_each` picks up the new workspace ID and creates `Log Analytics Reader` for the Grafana MI
4. If automated Grafana provisioning is enabled, the `grafana-azure-monitor-datasource` data source already covers all workspaces via the subscription-level query — no data source update is needed

### Rotating the Terraform service principal secret

1. Create a new secret in Azure AD for the SP
2. Update the secret in the CI/CD secrets store
3. Revoke the old secret
4. No Terraform changes required

### Rotating the Grafana service account token

1. Create a new service account token in Grafana
2. Update `TF_VAR_grafana_service_account_token` in the CI/CD secrets store
3. Run `terraform apply` — the provider re-authenticates and reconciles data source configuration

### Hub peering — handing off to the network team

When `manage_hub_peering = false` (default), provide the spoke VNet resource ID to the network team after first apply:

```bash
terraform output spoke_vnet_id
```

They create the peering:
- `allow_forwarded_traffic = true`
- `allow_gateway_transit = true` (if hub has a VPN/ER gateway)
- `use_remote_gateways = false`

### Disaster recovery

- Terraform state versioning and soft-delete protect against accidental state loss
- Key Vault has 90-day soft-delete and purge protection — deleted vaults and keys are recoverable within that window
- If state is lost, use `terraform import` to reimport existing resources
- `CanNotDelete` locks on all resource groups prevent accidental deletion via the Portal or CLI

---

## Variable Reference

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `network_resource_group_name` | `string` | `rg-observability-network-prod` | RG for spoke networking resources |
| `vnet_name` | `string` | `vnet-observability-prod` | Spoke VNet name |
| `vnet_address_space` | `string` | `10.100.0.0/23` | Spoke VNet CIDR |
| `private_endpoints_subnet_cidr` | `string` | `10.100.0.0/26` | Subnet CIDR for private endpoints (min /28) |
| `hub_vnet_id` | `string` | — | Hub VNet resource ID (required) |
| `hub_vnet_name` | `string` | `null` | Hub VNet name — required when `manage_hub_peering = true` |
| `hub_vnet_resource_group_name` | `string` | `null` | Hub VNet RG — required when `manage_hub_peering = true` |
| `manage_hub_peering` | `bool` | `false` | Create hub→spoke peering (needs hub RG Contributor) |
| `use_hub_gateway` | `bool` | `false` | Use hub VPN/ER gateway for transit |
| `hub_firewall_private_ip` | `string` | `null` | Hub NVA IP — enables UDR for forced tunnelling |

### Platform cluster

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `subscription_id` | `string` | — | Azure subscription ID |
| `tenant_id` | `string` | — | Azure AD tenant ID |
| `location` | `string` | `westeurope` | Azure region |
| `environment` | `string` | `prod` | Label applied to names and tags (`prod`, `staging`, `dev`) |
| `extra_tags` | `map(string)` | `{}` | Additional tags merged onto all resources |
| `platform_resource_group_name` | `string` | `rg-observability-platform-prod` | Platform RG name |
| `cluster_name` | `string` | `lac-observability-prod` | Dedicated cluster name |
| `cluster_capacity_reservation_gb` | `number` | `100` | Commitment tier GB/day (100/200/300/400/500/1000/2000/5000) |
| `platform_workspace_name` | `string` | `law-platform-prod` | Central platform workspace name |
| `default_retention_in_days` | `number` | `90` | Default workspace retention (30–730 days) |

### Key Vault / CMK

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `key_vault_name` | `string` | — | Globally unique KV name (3–24 chars, required) |
| `key_vault_key_name` | `string` | `log-analytics-cmk` | CMK key name inside Key Vault |
| `key_expiry_days` | `number` | `365` | CMK expiry in days (rotation fires 90d before) |
| `key_vault_public_network_access_enabled` | `bool` | `false` | `false` = private endpoint only |
| `key_vault_allowed_ips` | `list(string)` | `[]` | IPs allowed when public access is on |
| `private_dns_zone_resource_group_name` | `string` | `null` | RG of `privatelink.vaultcore.azure.net` DNS zone |

### AMPLS

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ampls_name` | `string` | — | Name of the centrally-managed AMPLS (required) |
| `ampls_resource_group_name` | `string` | — | RG of the AMPLS — deployer SP needs Contributor here (required) |

### Prometheus and Grafana

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `monitor_workspace_name` | `string` | `amw-observability-prod` | Azure Monitor Workspace name |
| `grafana_managed_identity_principal_id` | `string` | — | Object ID of Grafana's MI — granted Monitoring Reader + Log Analytics Reader (required) |
| `grafana_endpoint` | `string` | `null` | Grafana URL — when set, data sources are provisioned automatically |
| `grafana_service_account_token` | `string` | `null` | Grafana service account token (sensitive — use `TF_VAR_` env var) |

### Consumers

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `consumers` | `map(object)` | `{}` | Consumer workspace definitions — see schema below |

```hcl
consumers = {
  "<consumer-key>" = {
    retention_in_days      = number         # optional — inherits default_retention_in_days
    workspace_contributors = list(string)   # optional — AAD object IDs, Log Analytics Contributor
    workspace_readers      = list(string)   # optional — AAD object IDs, Log Analytics Reader
    extra_tags             = map(string)    # optional — merged with common_tags
  }
}
```

### Outputs

| Output | Description |
|--------|-------------|
| `platform_cluster_id` | Resource ID of the dedicated cluster |
| `platform_cluster_name` | Name of the dedicated cluster |
| `platform_workspace_id` | Resource ID of the platform workspace |
| `platform_workspace_customer_id` | Customer ID for agent / DCR configuration |
| `key_vault_id` | Resource ID of the Key Vault |
| `consumer_workspaces` | Map of consumer → `{ resource_group_name, workspace_id, workspace_name, workspace_customer_id }` |
| `spoke_vnet_id` | Spoke VNet resource ID — provide to network team for hub-side peering |
| `private_endpoints_subnet_id` | Subnet ID hosting private endpoint NICs |
| `ampls_scoped_service_ids` | Map of all AMPLS scoped-service resource IDs |
| `prometheus_query_endpoint` | PromQL query URL — configure as Grafana Prometheus data source |
| `prometheus_dcr_id` | Prometheus DCR resource ID — consumer teams create DCRAs against this |
| `prometheus_default_dce_id` | Default Data Collection Endpoint resource ID for the AMW |
| `grafana_datasource_summary` | JSON bundle of values the Grafana team needs for manual data source setup |
