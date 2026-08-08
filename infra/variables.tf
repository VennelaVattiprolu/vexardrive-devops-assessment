# Variables are the mechanism for environment separation (dev/staging/prod
# all use this same configuration, with different values supplied via
# environments/*.tfvars - see environments/dev.tfvars and README.md).

variable "environment" {
  description = "Deployment environment name (dev, staging, prod). Used in resource naming and to select environment-appropriate SKUs."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "project" {
  description = "Short project name, used as a prefix in resource names."
  type        = string
  default     = "vexar"
}

variable "postgres_admin_username" {
  description = "PostgreSQL administrator username."
  type        = string
  default     = "vexaradmin"
}

variable "postgres_sku" {
  description = "Azure Database for PostgreSQL Flexible Server SKU. Burstable for dev/staging (cheap, bursty low-traffic workload); consider General Purpose for prod once sustained load is measured (see docs/REPORT.md, Deliverable 5)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "PostgreSQL storage in MB."
  type        = number
  default     = 32768 # 32GB - Flexible Server's minimum
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "container_app_min_replicas" {
  description = "Minimum Container App replicas. 0 allowed for dev (scale-to-zero saves cost); prod should stay >= 1 to avoid cold-start latency on the first request after idle."
  type        = number
  default     = 1
}

variable "container_app_max_replicas" {
  description = "Maximum Container App replicas for autoscaling."
  type        = number
  default     = 3
}

variable "container_image" {
  description = "Full container image reference (registry/image:tag) to deploy. Left as a variable rather than hardcoded so CI/CD (Deliverable 4) can pass the freshly built tag on each deploy."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest" # placeholder until the real image is pushed to ACR for the first time - see infra/README.md
}

variable "alert_email" {
  description = "Email address to receive monitoring alerts (Deliverable 7)."
  type        = string
  default     = "devops-alerts@vexardrive.example"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    project = "vexar-fleet-ping"
  }
}
