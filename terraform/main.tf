# =============================================================================
# Cloud Pub/Sub Tech Spotlight - Demo Infrastructure
# -----------------------------------------------------------------------------
# The rides story from the deck, as real infrastructure:
#
#   Trip service ──> rides topic ──┬─> match-sub     (pull)   Driver matching
#                   (Avro schema)  ├─> billing-sub   (pull)   Payments
#                                  └─> analytics-sub (BigQuery) ─> rides_analytics.trip_events
#                                      (SMT masks rider_email in-flight)
#
#   Failed messages on match-sub ──> rides-dead-letter ──> rides-dead-letter-sub
#
# One `terraform apply` stands the whole thing up; one `terraform destroy` tears
# it down. Runs in Google Cloud Shell (Terraform pre-installed, ADC automatic).
# =============================================================================

# Resolves the active project - used for the pubsub service-agent email, the
# BigQuery subscription target, and the console URLs in outputs.tf.
data "google_project" "project" {
  project_id = var.project != "" ? var.project : null
}

locals {
  project_id = data.google_project.project.project_id

  # The Pub/Sub service agent. Pub/Sub itself (not your user) writes to BigQuery
  # and publishes to the dead-letter topic, so THIS is the identity that needs
  # the IAM grants below. Granting your own user account instead is the single
  # most common cause of "why is nothing landing in BigQuery" in a live demo.
  pubsub_sa = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# Schema - the format contract for every message on the topic (deck: "Schema").
# AVRO with JSON encoding: you publish plain JSON, Pub/Sub validates it against
# this schema and rejects anything that doesn't conform.
# -----------------------------------------------------------------------------
resource "google_pubsub_schema" "trip_event" {
  name       = "trip-event"
  type       = "AVRO"
  definition = file("${path.module}/schemas/trip_event.avsc")
}

# -----------------------------------------------------------------------------
# Topic - the named feed trip events are published to (deck: "Topic").
# -----------------------------------------------------------------------------
resource "google_pubsub_topic" "rides" {
  name = var.topic_name

  schema_settings {
    schema   = google_pubsub_schema.trip_event.id
    encoding = "JSON" # publish JSON; Pub/Sub validates against the Avro schema
  }

  # Ensure the schema exists before the topic references it.
  depends_on = [google_pubsub_schema.trip_event]
}

# -----------------------------------------------------------------------------
# Dead-letter topic + its own subscription (deck: "Dead-letter topics").
# Messages that fail delivery on match-sub too many times land here instead of
# retrying forever. The subscription keeps them visible/pullable in the console.
# -----------------------------------------------------------------------------
resource "google_pubsub_topic" "dead_letter" {
  name = "${var.topic_name}-dead-letter"
}

resource "google_pubsub_subscription" "dead_letter" {
  name                       = "${var.topic_name}-dead-letter-sub"
  topic                      = google_pubsub_topic.dead_letter.id
  message_retention_duration = "604800s" # 7 days - inspect failures at your leisure
}

# -----------------------------------------------------------------------------
# match-sub - pull subscription for driver matching.
# Carries a dead-letter policy so a poison message can't block the pipeline.
# -----------------------------------------------------------------------------
resource "google_pubsub_subscription" "match" {
  name                 = "match-sub"
  topic                = google_pubsub_topic.rides.id
  ack_deadline_seconds = 20

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5 # after 5 failed deliveries, route to dead-letter
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# -----------------------------------------------------------------------------
# billing-sub - a SEPARATE pull subscription for payments.
# This is the fan-out point of the demo: match-sub and billing-sub each receive
# their OWN copy of every published message (deck: "Every subscription gets a copy").
# -----------------------------------------------------------------------------
resource "google_pubsub_subscription" "billing" {
  name                 = "billing-sub"
  topic                = google_pubsub_topic.rides.id
  ack_deadline_seconds = 20
}

# -----------------------------------------------------------------------------
# BigQuery landing zone - the visible payoff (deck: "One trip → one smart
# notification", the BigQuery hop). Nothing is copied twice: the analytics
# subscription streams events straight into this table.
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset" "analytics" {
  dataset_id                 = "rides_analytics"
  location                   = var.location
  delete_contents_on_destroy = true # let `terraform destroy` drop the table cleanly
}

resource "google_bigquery_table" "trip_events" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "trip_events"
  deletion_protection = false # REQUIRED for a clean destroy in provider 7.x
  schema              = file("${path.module}/schemas/trip_events_bq_schema.json")
}

# -----------------------------------------------------------------------------
# IAM - let the Pub/Sub service agent write to BigQuery.
# Per Google's docs, a BigQuery subscription requires the Pub/Sub service agent
# to hold bigquery.dataEditor (+ metadataViewer to read the table schema).
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "pubsub_bq_editor" {
  project = local.project_id
  role    = "roles/bigquery.dataEditor"
  member  = local.pubsub_sa
}

resource "google_project_iam_member" "pubsub_bq_metadata" {
  project = local.project_id
  role    = "roles/bigquery.metadataViewer"
  member  = local.pubsub_sa
}

# -----------------------------------------------------------------------------
# analytics-sub - the BigQuery subscription. Pub/Sub delivers matching messages
# directly into the table (deck: "Export" delivery type). use_topic_schema maps
# the Avro fields to the table columns.
#
# The message_transforms block is the deck's Single Message Transform (SMT):
# a JavaScript function that runs inside Pub/Sub on each message at delivery
# time. Because it sits on THIS subscription (not the topic), billing-sub still
# receives the full event - only the copy headed to BigQuery gets rider_email
# masked. Before SMTs, this took a Dataflow job between Pub/Sub and BigQuery.
# -----------------------------------------------------------------------------
resource "google_pubsub_subscription" "analytics" {
  name  = "analytics-sub"
  topic = google_pubsub_topic.rides.id

  message_transforms {
    javascript_udf {
      function_name = "maskEmail"
      code          = file("${path.module}/transforms/mask_email.js")
    }
  }

  bigquery_config {
    table               = "${local.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.trip_events.table_id}"
    use_topic_schema    = true  # map Avro schema fields → BigQuery columns
    write_metadata      = false # set true to also capture message_id / publish_time / attributes
    drop_unknown_fields = true  # tolerate schema evolution instead of erroring
  }

  # The subscription creation call fails if the service agent can't yet write to
  # the table, so wait for the IAM grants to land first.
  depends_on = [
    google_project_iam_member.pubsub_bq_editor,
    google_project_iam_member.pubsub_bq_metadata,
    google_bigquery_table.trip_events,
  ]
}

# -----------------------------------------------------------------------------
# IAM - let the Pub/Sub service agent operate the dead-letter flow.
# It must be able to PUBLISH to the dead-letter topic and SUBSCRIBE (ack) on the
# source subscription. Missing these = dead-lettering silently doesn't work.
# -----------------------------------------------------------------------------
resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  topic  = google_pubsub_topic.dead_letter.id
  role   = "roles/pubsub.publisher"
  member = local.pubsub_sa
}

resource "google_pubsub_subscription_iam_member" "match_subscriber" {
  subscription = google_pubsub_subscription.match.id
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_sa
}
