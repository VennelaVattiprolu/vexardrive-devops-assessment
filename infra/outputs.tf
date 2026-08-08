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
