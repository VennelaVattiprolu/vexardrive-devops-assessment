# ACR admin credentials disabled - was: the original GitHub Actions
# workflow used a long-lived admin username/password stored as a GitHub
# secret. Replaced with: the Container App's managed identity is granted
# AcrPull directly (below), and Deliverable 4's CI/CD workflow is
# redesigned to use OIDC federated credentials instead of a stored
# registry password - see .github/workflows/deploy.yml.
resource "azurerm_container_registry" "main" {
  name                = replace("${local.name_prefix}acr", "-", "") # ACR names: alphanumeric only
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled        = false
  tags                = local.tags
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
