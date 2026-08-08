# Central destination for Container Apps' stdout/stderr (our pino JSON
# logs land here automatically) and platform metrics. See docs/REPORT.md,
# Deliverable 7, for the specific queries/alerts built on top of this.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "main" {
  name                = "${local.name_prefix}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = substr("${var.project}alert", 0, 12) # Azure caps short_name at 12 chars

  email_receiver {
    name          = "devops-team"
    email_address = var.alert_email
  }

  tags = local.tags
}
