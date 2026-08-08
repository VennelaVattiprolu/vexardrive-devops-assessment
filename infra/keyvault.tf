data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = "${local.name_prefix}-kv"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC authorization (not the legacy access-policy model) so access is
  # granted via standard Azure role assignments below - one consistent
  # permission model across the whole architecture instead of two.
  enable_rbac_authorization = true

  # Purge protection prevents anyone (including someone with delete
  # permission) from permanently destroying secrets before their retention
  # period - a safety net against both accidental and malicious deletion.
  # Off for dev/staging so tearing down demo environments doesn't leave a
  # soft-deleted vault blocking a same-name recreation for 90 days.
  purge_protection_enabled = var.environment == "prod"
  soft_delete_retention_days = 90

  tags = local.tags
}

# Terraform itself needs permission to write the secrets below.
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The app's managed identity gets read-only access to secrets - nothing
# more. It cannot list/delete/manage the vault itself, only fetch the
# specific secret values it needs at runtime.
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.postgres_admin.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.terraform_kv_admin]
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false # JWT secret doesn't need special chars, just entropy
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = random_password.jwt_secret.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.terraform_kv_admin]
}
