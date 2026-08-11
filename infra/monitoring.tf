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

# --- Alerts -----------------------------------------------------------
# Six alerts, chosen deliberately narrow rather than exhaustive: each one
# maps to a condition that would actually change what an on-call engineer
# does next. See docs/REPORT.md, Deliverable 7, for the "what/trigger/
# why" reasoning behind each - this file is the mechanism, the report is
# the reasoning.

# 1. Error rate - the single most direct signal that something is
# actively broken for real users right now.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_error_rate" {
  name                = "${local.name_prefix}-high-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  severity            = 1 # 0=critical .. 4=verbose; 1 = urgent, needs prompt attention
  scopes              = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency = "PT5M"
  window_duration       = "PT5M"

  criteria {
    query = <<-KQL
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${azurerm_container_app.main.name}"
      | extend parsed = parse_json(Log_s)
      | where isnotempty(parsed.res.statusCode)
      | summarize total = count(), errors = countif(toint(parsed.res.statusCode) >= 500) by bin(TimeGenerated, 5m)
      | extend error_rate = todouble(errors) / todouble(total) * 100
      | where total > 5  // ignore noise at very low traffic volume
      | project TimeGenerated, error_rate
    KQL
    time_aggregation_method = "Average"
    threshold               = 5 # >5% of requests returning 5xx
    operator                = "GreaterThan"
    metric_measure_column    = "error_rate"
    resource_id_column       = ""
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}

# 2. Sustained readiness-probe failures - distinct from a single blip;
# catches the "app is up but can't reach the DB" failure mode.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "readiness_failing" {
  name                = "${local.name_prefix}-readiness-failing"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  severity            = 1
  scopes              = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency = "PT5M"
  window_duration       = "PT10M"

  criteria {
    query = <<-KQL
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${azurerm_container_app.main.name}"
      | extend parsed = parse_json(Log_s)
      | where tostring(parsed.req.url) == "/readyz"
      | summarize fail_count = countif(toint(parsed.res.statusCode) == 503) by bin(TimeGenerated, 5m)
      | project TimeGenerated, fail_count
    KQL
    time_aggregation_method = "Total"
    threshold               = 3 # 3+ failed readiness checks in the window - not just one transient blip
    operator                = "GreaterThanOrEqual"
    metric_measure_column    = "fail_count"
    resource_id_column       = ""
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}

# 3. Container App replica restarts - catches crash loops before they
# necessarily show up as user-facing errors (e.g. if traffic is low).
resource "azurerm_monitor_metric_alert" "replica_restarts" {
  name                = "${local.name_prefix}-replica-restarts"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.main.id]
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.tags
}

# 4. Database CPU sustained high - the earliest warning sign before
# connection saturation/query timeouts start affecting users directly.
resource "azurerm_monitor_metric_alert" "postgres_cpu" {
  name                = "${local.name_prefix}-postgres-cpu-high"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.tags
}

# 5. Database connections approaching the configured ceiling - directly
# tied to the connection-count arithmetic documented in Deliverable 5
# (replicas x DB_POOL_MAX vs max_connections). This is the alert that
# would have caught that gap before it became an outage.
resource "azurerm_monitor_metric_alert" "postgres_connections" {
  name                = "${local.name_prefix}-postgres-connections-high"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85 # against max_connections = 100 (database.tf) - alerts before exhaustion, not at it
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = local.tags
}

# 6. Spike in failed login attempts - a security signal, not just a
# reliability one. Distinguishes "someone is trying to brute-force OTPs"
# from normal traffic, using the rate-limit-triggered 429s from
# src/middleware/rateLimit.js as the detection surface.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "auth_abuse" {
  name                = "${local.name_prefix}-auth-abuse-signal"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  severity            = 2
  scopes              = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency = "PT15M"
  window_duration       = "PT15M"

  criteria {
    query = <<-KQL
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${azurerm_container_app.main.name}"
      | extend parsed = parse_json(Log_s)
      | where tostring(parsed.req.url) in ("/api/auth/login", "/api/auth/request-otp")
      | where toint(parsed.res.statusCode) == 429
      | summarize throttled_count = count() by bin(TimeGenerated, 15m)
      | project TimeGenerated, throttled_count
    KQL
    time_aggregation_method = "Total"
    threshold               = 20 # a normal traffic pattern shouldn't hit the rate limiter this often
    operator                = "GreaterThan"
    metric_measure_column    = "throttled_count"
    resource_id_column       = ""
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = local.tags
}
