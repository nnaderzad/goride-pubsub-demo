output "topic_name" {
  description = "The rides topic trip events are published to."
  value       = google_pubsub_topic.rides.name
}

output "subscriptions" {
  description = "The subscriptions fanning out from the rides topic."
  value = {
    match     = google_pubsub_subscription.match.name
    billing   = google_pubsub_subscription.billing.name
    analytics = google_pubsub_subscription.analytics.name
  }
}

output "bigquery_table" {
  description = "Fully-qualified BigQuery table the analytics subscription writes to."
  value       = "${local.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.trip_events.table_id}"
}

# ---------------------------------------------------------------------------
# Console deep-links — open these on stage; they are the demo surface.
# ---------------------------------------------------------------------------
output "topic_console_url" {
  description = "Open the rides topic (use the Messages tab to publish live)."
  value       = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.rides.name}?project=${local.project_id}"
}

output "match_sub_console_url" {
  description = "Open match-sub (use Pull to see driver-matching's copy)."
  value       = "https://console.cloud.google.com/cloudpubsub/subscription/detail/${google_pubsub_subscription.match.name}?project=${local.project_id}"
}

output "billing_sub_console_url" {
  description = "Open billing-sub (use Pull to see payments' own copy of the same event)."
  value       = "https://console.cloud.google.com/cloudpubsub/subscription/detail/${google_pubsub_subscription.billing.name}?project=${local.project_id}"
}

output "bigquery_console_url" {
  description = "Open the BigQuery dataset where analytics events land."
  value       = "https://console.cloud.google.com/bigquery?project=${local.project_id}&d=${google_bigquery_dataset.analytics.dataset_id}&p=${local.project_id}&page=dataset"
}

# ---------------------------------------------------------------------------
# Copy-paste helpers for the live beats.
# ---------------------------------------------------------------------------
output "publish_command" {
  description = "Publish Maya's trip event from the CLI (the gcloud fallback for Scene 3)."
  value       = "gcloud pubsub topics publish ${google_pubsub_topic.rides.name} --project=${local.project_id} --message='{\"event_id\":\"evt_maya\",\"user_id\":\"u_456\",\"driver_id\":\"d_789\",\"event_type\":\"trip_completed\",\"fare\":24.50,\"city\":\"San Francisco\",\"timestamp\":\"2026-07-22T22:15:00Z\"}'"
}

output "run_this_query" {
  description = "Paste into the BigQuery console to show events that landed."
  value       = "SELECT event_type, city, fare, timestamp FROM `${local.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.trip_events.table_id}` ORDER BY timestamp DESC LIMIT 20"
}
