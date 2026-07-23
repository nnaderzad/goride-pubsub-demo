# Setup Without Terraform — Pure gcloud/bq

Don't want Terraform? This page builds the **exact same infrastructure** as
`terraform apply`, one `gcloud`/`bq` command per resource. It replaces **Step 3
of [`SETUP.md`](SETUP.md)** — do Steps 1–2 there first (project + APIs), then
run this top to bottom, then return to SETUP.md Step 4 (pre-bake) and Step 5
(verify).

It's also the proof that there's no magic in the `.tf` files: every resource in
this demo is one API call, whichever tool makes it — console click, `gcloud`,
client library, or Terraform. Use whatever your team uses.

```bash
# Run from the repo root (the schema files are referenced by path).
export PROJECT="$(gcloud config get-value project)"
```

---

## 1. The schema — the format contract

```bash
gcloud pubsub schemas create trip-event \
  --type=avro \
  --definition-file=terraform/schemas/trip_event.avsc
```

## 2. The rides topic, validated by that schema

```bash
gcloud pubsub topics create rides \
  --schema=trip-event \
  --message-encoding=json
```

## 3. The dead-letter topic + its subscription

```bash
gcloud pubsub topics create rides-dead-letter

gcloud pubsub subscriptions create rides-dead-letter-sub \
  --topic=rides-dead-letter \
  --message-retention-duration=7d
```

## 4. match-sub (dispatch) — with the dead-letter policy

```bash
gcloud pubsub subscriptions create match-sub \
  --topic=rides \
  --ack-deadline=20 \
  --dead-letter-topic=rides-dead-letter \
  --max-delivery-attempts=5 \
  --min-retry-delay=10s \
  --max-retry-delay=600s
```

> `gcloud` will print a **warning that the Pub/Sub service agent needs
> permissions** for dead-lettering to actually work. That's real — we grant them
> in step 7. (The console does this grant for you when you click; `gcloud` and
> Terraform both make you do it explicitly.)

## 5. billing-sub (finance) — the fan-out point

```bash
gcloud pubsub subscriptions create billing-sub \
  --topic=rides \
  --ack-deadline=20
```

## 6. The BigQuery landing zone (dataset + table)

```bash
bq --location=us-central1 mk --dataset "$PROJECT:rides_analytics"

bq mk --table \
  "$PROJECT:rides_analytics.trip_events" \
  terraform/schemas/trip_events_bq_schema.json
```

## 7. IAM — the grants Pub/Sub itself needs

Pub/Sub (not you) writes to BigQuery and publishes to the dead-letter topic, so
the grants go to the **Pub/Sub service agent** — granting your own user instead
is the classic "why is nothing landing" mistake:

```bash
PROJNUM=$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")
PUBSUB_SA="serviceAccount:service-${PROJNUM}@gcp-sa-pubsub.iam.gserviceaccount.com"

# Write into BigQuery (for analytics-sub):
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_SA" --role=roles/bigquery.dataEditor --condition=None
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_SA" --role=roles/bigquery.metadataViewer --condition=None

# Operate the dead-letter flow (for match-sub):
gcloud pubsub topics add-iam-policy-binding rides-dead-letter \
  --member="$PUBSUB_SA" --role=roles/pubsub.publisher
gcloud pubsub subscriptions add-iam-policy-binding match-sub \
  --member="$PUBSUB_SA" --role=roles/pubsub.subscriber
```

## 8. analytics-sub — the BigQuery subscription (last, after IAM)

```bash
gcloud pubsub subscriptions create analytics-sub \
  --topic=rides \
  --bigquery-table="$PROJECT.rides_analytics.trip_events" \
  --use-topic-schema \
  --drop-unknown-fields
```

> If this fails with a permissions error, the step-7 grants haven't propagated
> yet — wait ~60 seconds and re-run just this command. (Same eventual-consistency
> hiccup as the Terraform path.)

---

**Done.** You now have byte-for-byte the same setup as `terraform apply`:
1 schema, 2 topics, 4 subscriptions, 1 dataset, 1 table, 4 IAM grants.
Continue with [`SETUP.md`](SETUP.md) **Step 4** (pre-bake the earlier rides)
and **Step 5** (verify).

---

## Teardown (the manual equivalent of `terraform destroy`)

Order matters less than completeness — this is exactly why Terraform's
one-command destroy is nice, and it's a fair thing to point out when teaching:

```bash
gcloud pubsub subscriptions delete analytics-sub match-sub billing-sub rides-dead-letter-sub
gcloud pubsub topics delete rides rides-dead-letter
gcloud pubsub schemas delete trip-event
bq rm -r -f --dataset "$PROJECT:rides_analytics"

# Optional: remove the project-level grants too
PROJNUM=$(gcloud projects describe "$PROJECT" --format="value(projectNumber)")
PUBSUB_SA="serviceAccount:service-${PROJNUM}@gcp-sa-pubsub.iam.gserviceaccount.com"
gcloud projects remove-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_SA" --role=roles/bigquery.dataEditor --condition=None
gcloud projects remove-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_SA" --role=roles/bigquery.metadataViewer --condition=None
```

---

## Same resource, four ways (teaching aid)

Creating `billing-sub`, in every on-ramp GCP offers — they all produce the
identical resource:

| How | What it looks like |
|-----|--------------------|
| **Console** | Topic page → Create subscription → name it, pick Pull → Create |
| **gcloud** | `gcloud pubsub subscriptions create billing-sub --topic=rides` |
| **Python** | `subscriber.create_subscription(name=sub_path, topic=topic_path)` |
| **Terraform** | `resource "google_pubsub_subscription" "billing" { name = "billing-sub" topic = ... }` |

The tool is a preference. The concepts — topics, subscriptions, fan-out, ack,
schemas, dead-letter — are the subject.
