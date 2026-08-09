output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "container_app_fqdn" {
  description = "Public URL of the deployed app."
  value       = azurerm_container_app.main.latest_revision_fqdn
}

output "container_app_identity_client_id" {
  description = "Client ID of the managed identity - useful for federated credential setup in CI/CD (Deliverable 4)."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "acr_login_server" {
  description = "ACR login server - CI/CD pushes images here."
  value       = azurerm_container_registry.main.login_server
}

output "postgres_fqdn" {
  description = "Private FQDN of the PostgreSQL server (only resolvable/reachable from inside the VNet)."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "cicd_client_id" {
  description = "Client ID of the CI/CD identity - set as an AZURE_CLIENT_ID variable (not secret - not sensitive under OIDC) on the matching GitHub Environment."
  value       = azurerm_user_assigned_identity.cicd.client_id
}

output "azure_tenant_id" {
  description = "Set as AZURE_TENANT_ID on the GitHub Environment."
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "Set as AZURE_SUBSCRIPTION_ID on the GitHub Environment."
  value       = data.azurerm_client_config.current.subscription_id
}

output "container_app_name" {
  value = azurerm_container_app.main.name
}
