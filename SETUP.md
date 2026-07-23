# Pre-Talk Setup — Cloud Pub/Sub Demo

**Do this before the session — about 10 minutes.** None of it is on the live
clock. The guiding principle (borrowed from the best demos): **pre-bake
everything, run one thing live.**

## Assumptions

- You have a **Google Cloud project with billing enabled**. You will not create a
  project or set up billing.
- You will use **Google Cloud Shell** (browser-based) — Terraform, `gcloud`, and
  `bq` are pre-installed and pre-authenticated, so there is nothing to install.
- Cost is effectively **~$0**: a handful of tiny messages and a few rows in
  BigQuery, well inside the Always Free tier.

---

## Step 1 — Point Cloud Shell at your project

Open [shell.cloud.google.com](https://shell.cloud.google.com), signed in with the
account that owns the project, then:

```bash
gcloud config set project YOUR_PROJECT_ID
```

Expected: `Updated property [core/project].` Cloud Shell authenticates you
automatically — no `gcloud auth login` needed.

---

## Step 2 — Enable the two APIs

```bash
gcloud services enable pubsub.googleapis.com bigquery.googleapis.com
```

Wait for `Operation ... finished successfully.` (30–60s). Idempotent — safe to
re-run.

> **Why these two:** Pub/Sub is the service itself; BigQuery is where the
> analytics subscription lands events. No Cloud Storage or Compute APIs are
> needed for this demo.

---

## Step 3 — Get the code and stand up the infrastructure

> **Prefer not to use Terraform?** The same infrastructure, resource for
> resource, as plain `gcloud`/`bq` commands:
> [`SETUP_WITHOUT_TERRAFORM.md`](SETUP_WITHOUT_TERRAFORM.md). Do that instead of
> this step, then rejoin at Step 4.

```bash
git clone https://github.com/nnaderzad/goride-pubsub-demo.git
cd goride-pubsub-demo/terraform
terraform init
terraform apply        # review the plan, type "yes"
```

This creates **one topic (with an Avro schema), three subscriptions
(match-sub, billing-sub, analytics→BigQuery), a dead-letter topic + its
subscription, a BigQuery dataset + table, and all the IAM** the Pub/Sub service
agent needs. Takes ~30–60 seconds.

When it finishes, Terraform prints the console URLs and helper commands. **Keep
this output** — it's your demo cheat sheet.

> ### ⚠️ If `terraform apply` errors on the BigQuery subscription or dead-letter
> IAM propagation is eventually-consistent. A brand-new project's Pub/Sub service
> agent (`service-<PROJECT_NUMBER>@gcp-sa-pubsub.iam.gserviceaccount.com`) may not
> have picked up its grants the instant the subscription is created. **Just run
> `terraform apply` a second time** — the IAM will have landed and the
> subscription creates cleanly. This is the single most likely first-run hiccup.

---

## Step 4 — Pre-bake the payoff

Publish the "earlier rides tonight" now, so the data team's BigQuery table
already has traffic before Maya's live ride (and rows to show if the live
publish is slow). Maya's own event (`evt_maya`) is **not** published here — that
one happens live, in Scene 3:

```bash
cd ..   # back to repo root
gcloud pubsub topics publish rides \
  --message='{"event_id":"evt_1001","user_id":"u_910","driver_id":"d_233","event_type":"trip_completed","fare":8.75,"city":"Oakland","timestamp":"2026-07-22T21:48:30Z"}'
gcloud pubsub topics publish rides \
  --message='{"event_id":"evt_1002","user_id":"u_128","driver_id":"d_512","event_type":"trip_completed","fare":41.20,"city":"San Jose","timestamp":"2026-07-22T21:55:05Z"}'
```

---

## Step 5 — Verify you're ready (the "all clear")

```bash
# Both subscriptions have the same event waiting (leave it there — don't ack):
gcloud pubsub subscriptions pull match-sub   --limit=1
gcloud pubsub subscriptions pull billing-sub --limit=1

# BigQuery has rows (may take a few seconds after publishing):
bq query --use_legacy_sql=false \
  "SELECT event_type, city, fare FROM \`rides_analytics.trip_events\` ORDER BY timestamp DESC LIMIT 5"
```

If the pulls return a message and the query returns rows, **you're ready.**

> **Do a full dry run shortly before the talk**, and keep a **screen recording**
> of a successful run as a fallback in case the venue network dies mid-demo.

---

## Cleanup (after the talk)

```bash
cd terraform
terraform destroy      # type "yes" — removes everything it created
```

`destroy` tears down exactly what Terraform built, tracked in the local state
file. Run it before you close Cloud Shell so nothing lingers.
