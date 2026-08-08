# Terraform + provider version pinning. Pinned rather than left open so a
# `terraform init` six months from now doesn't silently pull a provider
# major version with breaking changes.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state (recommended, not activated by default here):
  # local state is fine for this assessment/demo, but a real team should
  # never use local state - no locking (two people running `apply`
  # simultaneously can corrupt state) and no shared source of truth.
  #
  # To use remote state, provision a storage account + container once
  # (outside Terraform, to avoid the chicken-and-egg problem of state
  # needing infra that doesn't exist yet), then uncomment and fill in:
  #
  # backend "azurerm" {
  #   resource_group_name  = "vexar-tfstate-rg"
  #   storage_account_name = "vexartfstateXXXX"   # must be globally unique
  #   container_name       = "tfstate"
  #   key                  = "vexar-fleet-ping.tfstate"
  # }
}

provider "azurerm" {
  features {
    key_vault {
      # Ensures `terraform destroy` actually removes the Key Vault instead
      # of leaving it in a "soft-deleted, waiting to be purged" state that
      # then blocks recreating a Key Vault with the same name - a common
      # source of confusing errors when tearing down/rebuilding demo
      # environments repeatedly.
      purge_soft_delete_on_destroy = true
    }
  }
}
