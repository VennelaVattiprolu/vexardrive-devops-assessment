# A single user-assigned managed identity, attached to the Container App,
# used for BOTH Key Vault secret access and ACR image pulls. This is the
# mechanism that means no credential (DB password, JWT secret, registry
# password) ever needs to exist in the image, an env var file, or a
# GitHub secret for runtime access - Azure AD handles the authentication.
resource "azurerm_user_assigned_identity" "app" {
  name                = "${local.name_prefix}-app-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}
