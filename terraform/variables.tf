variable "project" {
  type        = string
  description = "GCP project ID. Leave blank in Cloud Shell to use the active project (GOOGLE_CLOUD_PROJECT)."
  default     = ""
}

variable "location" {
  type        = string
  description = "Region for the BigQuery dataset. Pub/Sub topics are global, but the BigQuery subscription writes to a regional dataset. us-central1 is free-tier friendly."
  default     = "us-central1"
}

variable "topic_name" {
  type        = string
  description = "Name of the rides topic that trip events are published to."
  default     = "rides"
}
