environment = "dev"
location    = "centralindia"
project     = "vexar"

postgres_sku         = "B_Standard_B1ms"
postgres_storage_mb  = 32768

container_app_min_replicas = 0 # scale-to-zero: dev doesn't need to be always-on, saves cost
container_app_max_replicas = 2

alert_email = "devops-alerts@vexardrive.example"

tags = {
  project = "vexar-fleet-ping"
  owner   = "devops-assessment"
}
