environment = "prod"
location    = "centralindia"
project     = "vexar"

# General Purpose over Burstable once real fleet traffic is sustained
# rather than spiky - Burstable SKUs throttle CPU after burst credits are
# exhausted, which is a bad failure mode for a production ping ingestion
# endpoint under continuous load.
postgres_sku        = "GP_Standard_D2s_v3"
postgres_storage_mb = 65536

container_app_min_replicas = 2 # never scale to zero in prod - avoids cold-start latency on first request
container_app_max_replicas = 10

alert_email = "devops-alerts@vexardrive.example"

tags = {
  project = "vexar-fleet-ping"
  owner   = "devops-assessment"
}
