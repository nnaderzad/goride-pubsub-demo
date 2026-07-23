#!/usr/bin/env bash
# commands.sh - every command for the demo, in order.
# This is a REFERENCE to copy from, not a script to run blindly.
# The infrastructure itself is created by Terraform (see terraform/); these are
# the gcloud/bq commands for pre-baking, the CLI fallback for each live scene,
# and verification. Scene numbers match DEMO_WALKTHROUGH.md.

set -euo pipefail

# Set these to match your environment. In Cloud Shell, PROJECT is usually the
# active project already (echo "$GOOGLE_CLOUD_PROJECT").
export PROJECT="your-gcp-project-id"
export TOPIC="rides"
export DATASET="rides_analytics"
export TABLE="trip_events"

# ---------------------------------------------------------------------------
# ONE-TIME SETUP (do BEFORE the talk - not on the live clock)
# ---------------------------------------------------------------------------

# 1. Enable the two APIs the demo touches.
gcloud services enable pubsub.googleapis.com bigquery.googleapis.com --project="$PROJECT"

# 2. Stand up all the infrastructure with Terraform (topic, schema, the three
#    subscriptions, dead-letter, BigQuery dataset/table, and all IAM).
cd terraform
terraform init
terraform apply        # review the plan, type "yes"
cd ..
#    Note the outputs - the console URLs and the publish command are printed here.

# 3. PRE-BAKE THE PAYOFF: publish "earlier rides tonight" so the data team's
#    BigQuery table already has traffic before Maya's live ride. Each --message
#    must conform to the Avro schema (see data/sample_events.json).
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT" \
  --message='{"event_id":"evt_1001","user_id":"u_910","driver_id":"d_233","event_type":"trip_completed","fare":8.75,"city":"Oakland","timestamp":"2026-07-22T21:48:30Z"}'
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT" \
  --message='{"event_id":"evt_1002","user_id":"u_128","driver_id":"d_512","event_type":"trip_completed","fare":41.20,"city":"San Jose","timestamp":"2026-07-22T21:55:05Z"}'

# 4. Confirm rows landed (BigQuery subscriptions stream continuously; give it a
#    few seconds). If this returns rows, your payoff is safe.
bq query --project_id="$PROJECT" --use_legacy_sql=false \
  "SELECT event_type, city, fare, timestamp
   FROM \`$PROJECT.$DATASET.$TABLE\` ORDER BY timestamp DESC LIMIT 20"

# ---------------------------------------------------------------------------
# LIVE DEMO - CLI fallback for each scene
# (the walkthrough drives these in the Console UI; keep these handy)
# ---------------------------------------------------------------------------

# SCENE 3 - Maya's trip completes: publish HER event, live. You are the app.
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT" \
  --message='{"event_id":"evt_maya","user_id":"u_456","driver_id":"d_789","event_type":"trip_completed","fare":24.50,"city":"San Francisco","timestamp":"2026-07-22T22:15:00Z"}'

# SCENE 4 - Dispatch and Finance both react: pull ONE copy from EACH
# subscription. The SAME event comes back on both - fan-out, each department
# gets its own copy.
gcloud pubsub subscriptions pull match-sub   --project="$PROJECT" --auto-ack --limit=1
gcloud pubsub subscriptions pull billing-sub --project="$PROJECT" --auto-ack --limit=1

# SCENE 5 - The data team already sees it: Maya's ride is a row in BigQuery.
bq query --project_id="$PROJECT" --use_legacy_sql=false \
  "SELECT event_type, city, fare, timestamp
   FROM \`$PROJECT.$DATASET.$TABLE\` ORDER BY timestamp DESC LIMIT 20"

# SCENE 6 (optional live) - the buggy partner app: fare as text.
# This SHOULD fail with an INVALID_ARGUMENT / schema mismatch error. That's the point.
gcloud pubsub topics publish "$TOPIC" --project="$PROJECT" \
  --message='{"event_id":"evt_bad","user_id":"u_999","driver_id":"d_000","event_type":"trip_completed","fare":"not-a-number","city":"Nowhere","timestamp":"2026-07-22T22:20:00Z"}' \
  || echo ">> Rejected by the schema, exactly as designed."

# ---------------------------------------------------------------------------
# CLEANUP - tear everything down (Terraform tracks exactly what it made).
# ---------------------------------------------------------------------------
# cd terraform && terraform destroy   # type "yes"
