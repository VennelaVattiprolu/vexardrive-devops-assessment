resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-cae"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # VNet integration - this is what lets the app reach PostgreSQL over
  # the private network in database.tf instead of needing any public DB
  # access.
  infrastructure_subnet_id = azurerm_subnet.container_apps.id

  tags = local.tags
}

resource "azurerm_container_app" "main" {
  name                         = "${local.name_prefix}-app"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                 = "Single" # see infra/README.md for why not "Multiple" at this stage

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  # Secrets are pulled from Key Vault using the app's own managed identity
  # - Terraform references the Key Vault URI here, but the actual secret
  # VALUE is never read back through Terraform into the Container App
  # resource definition. This means the secret never appears in
  # `terraform plan` output or the Container App's own ARM properties.
  secret {
    name                = "db-password"
    key_vault_secret_id = azurerm_key_vault_secret.db_password.versionless_id
    identity            = azurerm_user_assigned_identity.app.id
  }

  secret {
    name                = "jwt-secret"
    key_vault_secret_id = azurerm_key_vault_secret.jwt_secret.versionless_id
    identity            = azurerm_user_assigned_identity.app.id
  }

  template {
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas

    container {
      name   = "vexar-fleet-ping"
      image  = var.container_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "PORT"
        value = "3000"
      }
      env {
        name  = "DB_HOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_USER"
        value = var.postgres_admin_username
      }
      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }
      env {
        name  = "DB_NAME"
        value = azurerm_postgresql_flexible_server_database.app.name
      }
      env {
        name  = "DB_SSL"
        value = "true"
      }
      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }
      env {
        name  = "JWT_EXPIRES_IN"
        value = "24h"
      }

      # Container Apps' own probes, layered on top of the app-level
      # HEALTHCHECK from the Dockerfile - these are what the platform
      # actually uses to gate traffic routing and restarts.
      liveness_probe {
        transport = "HTTP"
        path      = "/healthz"
        port      = 3000
      }
      readiness_probe {
        transport = "HTTP"
        path      = "/readyz"
        port      = 3000
      }
    }

    # Scale on concurrent HTTP requests - a reasonable default for an API
    # service. See docs/REPORT.md, Deliverable 5, for how this interacts
    # with the DB connection pool as fleet size grows (more replicas =
    # more total pooled connections against Postgres's fixed ceiling).
    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = 50
    }
  }

  ingress {
    external_enabled = true # fleet vehicles and driver clients reach this over the internet
    target_port      = 3000
    transport         = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = local.tags
}
