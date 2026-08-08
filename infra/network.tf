# Network boundary design (see docs/REPORT.md, Deliverable 6 for the full
# write-up):
#   - PostgreSQL: private only, no public IP, reachable only from inside
#     this VNet via a delegated subnet. The single highest-value network
#     control in this whole architecture - the database should never be
#     reachable from the public internet under any circumstance.
#   - Container Apps environment: gets its own subnet so it can reach
#     Postgres over the private network, while still exposing the app's
#     HTTP ingress publicly (fleet vehicles/drivers need to reach the API
#     from the internet - this is not an internal-only service).
#   - Key Vault and ACR: public endpoints but access-controlled via Azure
#     AD (managed identity + RBAC), not network isolated. Private
#     endpoints for these are a reasonable next step (see "what I'd
#     address next" in docs/REPORT.md) but add meaningful complexity
#     (private DNS zones, NSGs, no more `az acr login` from a laptop
#     without VPN) that isn't justified at this stage/team size.

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

# Delegated subnet for PostgreSQL Flexible Server private access.
resource "azurerm_subnet" "postgres" {
  name                 = "postgres-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Subnet for the Container Apps environment. /23 is Container Apps'
# minimum recommended size when using VNet integration with workload
# profiles - undersizing this is a common source of "works in dev, can't
# scale in prod" surprises since each replica consumes an IP.
resource "azurerm_subnet" "container_apps" {
  name                 = "container-apps-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/23"]
}

# Private DNS zone required for PostgreSQL Flexible Server private access -
# without this, the server's private hostname doesn't resolve, even though
# the network path exists.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${local.name_prefix}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name_prefix}-postgres-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.tags
}
