# Resource group - a single RG per environment. This is the blast-radius
# boundary: `terraform destroy` on a dev environment can never touch prod
# resources, since they live in entirely separate resource groups (and,
# in a team setup, separate subscriptions/state files - see
# infra/README.md, Environment Separation).

locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
  })
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}
