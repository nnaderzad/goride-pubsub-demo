# Provider + version pinning.
# Source: hashicorp/google v7.x (Pub/Sub schemas, BigQuery subscriptions, and
# dead-letter policies are all GA in the v7 provider). Verified against the
# provider docs for the 7.x line.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project != "" ? var.project : null # null → provider reads GOOGLE_CLOUD_PROJECT
  region  = var.location
  # No credentials block — Cloud Shell supplies Application Default Credentials automatically.
}
