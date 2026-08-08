# Infrastructure as Code — VexarDrive Fleet Ping Service

Terraform for the Azure infrastructure described in `docs/REPORT.md`,
Deliverable 3.

## Structure

| File | Purpose |
|---|---|
| `providers.tf` | Terraform/provider version pinning, remote state notes |
| `variables.tf` | All configurable inputs |
| `main.tf` | Resource group |
| `network.tf` | VNet, subnets, private DNS for Postgres |
| `database.tf` | Azure Database for PostgreSQL Flexible Server (private) |
| `identity.tf` | User-assigned managed identity |
| `keyvault.tf` | Key Vault + RBAC role assignments + secrets |
| `registry.tf` | Azure Container Registry |
| `containerapp.tf` | Container Apps environment + the app itself |
| `monitoring.tf` | Log Analytics workspace + alert action group |
| `outputs.tf` | Values needed by CI/CD and for manual verification |
| `environments/*.tfvars` | Per-environment values (see below) |

## Environment separation

Rather than one Terraform config with hardcoded values, every
environment-specific input (SKU sizes, replica counts, region) is a
variable, supplied via `environments/dev.tfvars` / `prod.tfvars`. Each
environment should also use its **own Terraform state file** (via
`-backend-config` or a separate `terraform workspace`) and ideally its
**own Azure subscription or at minimum resource group**, so a mistake in
dev can never affect prod. This repo demonstrates the pattern with two
tfvars files; a `staging.tfvars` would follow the same shape.

## Running this

Requires the Azure CLI, logged in (`az login`), and Terraform >= 1.9.

```bash
cd infra
terraform init

# Review the plan before applying anything
terraform plan -var-file=environments/dev.tfvars

# Apply
terraform apply -var-file=environments/dev.tfvars
```

First apply will use the placeholder `container_image` default (see
`variables.tf`) since the ACR doesn't exist yet to have pushed a real
image to. After the first apply:

```bash
# Build and push the real image (see Deliverable 4 for the automated version)
az acr login --name $(terraform output -raw acr_login_server | cut -d. -f1)
docker build -t $(terraform output -raw acr_login_server)/vexar-fleet-ping:v1 ..
docker push $(terraform output -raw acr_login_server)/vexar-fleet-ping:v1

# Re-apply pointing at the real image
terraform apply -var-file=environments/dev.tfvars \
  -var="container_image=$(terraform output -raw acr_login_server)/vexar-fleet-ping:v1"
```

## Tearing down

```bash
terraform destroy -var-file=environments/dev.tfvars
```

Note: Key Vault soft-delete means the vault name is reserved for a
retention period after destroy. `purge_soft_delete_on_destroy = true` in
`providers.tf` handles this automatically for repeated demo/test
destroy-and-recreate cycles.

## Cost note

Every SKU choice in `environments/dev.tfvars` is deliberately the
cheapest viable option (Burstable Postgres, `min_replicas = 0`, Basic
ACR) to minimize spend against a free-tier subscription. Even so,
Postgres Flexible Server and the Container Apps environment are **not**
part of Azure's always-free tier — running this for an extended period
will incur cost. Recommended: `terraform apply`, verify, then
`terraform destroy` promptly rather than leaving it running.
