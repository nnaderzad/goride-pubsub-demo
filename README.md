# One Ride Through GoRide - Cloud Pub/Sub Tech Spotlight Demo

A short, visual, **story-driven** demo companion to the Cloud Pub/Sub Tech
Spotlight deck. In ~8 minutes it follows **one ride through a ride company called
GoRide**: Maya finishes a $24.50 trip across San Francisco, the app publishes
**one event**, and we watch the whole company react - dispatch assigns drivers,
finance charges her card, and the data team's BigQuery dashboard updates in
seconds. Then two things go wrong (a corrupted event, a poison message) and
nothing breaks.

The deck's promise - *"publish once, let everything react"* - told as a story
instead of a feature list.

**Hybrid by design:** the infrastructure is **versioned Terraform** (reproducible,
one command up, one command down), but the live surface is the **Google Cloud
Console UI** (visual, no-code), with the payoff landing in **BigQuery**. Every
live scene has a `gcloud`/`bq` CLI fallback.

## The story

```
GoRide app ──>  rides topic  ──┬─> match-sub     > Dispatch          (pull)
   (Maya)      (Avro schema)   ├─> billing-sub   > Finance           (pull)
                               └─> analytics-sub > BigQuery/data team (export)
                                   (SMT masks     rides_analytics.trip_events
                                    rider_email)

        Poison message on match-sub ──> rides-dead-letter ──> dead-letter-sub
```

One publish → three departments react independently. Adding a fourth (fraud,
notifications, ML) is just one more subscription - zero changes upstream.

## What's in here

| Path | What it is |
|------|------------|
| [`SETUP.md`](SETUP.md) | **Do this first.** Pre-talk setup: enable APIs, `terraform apply`, pre-bake "earlier rides," verify. |
| [`DEMO_WALKTHROUGH.md`](DEMO_WALKTHROUGH.md) | The story - six scenes following Maya's ride, driven in the console, with CLI fallbacks. |
| [`notebook/goride_demo.ipynb`](notebook/goride_demo.ipynb) | The same six scenes as a **runnable notebook** using the `google-cloud-pubsub` client library - publish, pull, callback + ack, BigQuery query, schema rejection. The teaching-friendly surface. |
| [`commands.sh`](commands.sh) | Every `gcloud`/`bq` command in order - the CLI fallback for each scene. |
| `terraform/` | All the infrastructure as code: topic + schema, three subscriptions, a Single Message Transform (`transforms/mask_email.js`) on the analytics subscription, dead-letter, BigQuery dataset/table, IAM. |
| `data/sample_events.json` | The cast's event payloads - Maya's live event, the earlier rides, and the deliberately-broken one. |

## How the story maps to the deck

| Scene | Story beat | Deck concept |
|-------|-----------|--------------|
| 1 | Friday night - the old direct-call architecture hurt | "One tap, many systems" |
| 2 | Tour of GoRide's machinery | Publisher → Topic → Subscription → Subscriber; schemas |
| 3 | Maya's trip completes; you publish it live | Asynchronous publish - producer never waits |
| 4 | Dispatch and Finance each pull their own copy | Fan-out vs. load-balancing; acking |
| 5 | The data team already sees her ride in BigQuery - with her email masked | Export delivery; the "BigQuery hop"; Single Message Transforms |
| 6 | A corrupted event bounces; a poison message is quarantined | Schemas, dead-letter, retry - production features |

## Quick start

```bash
# 1. Point Cloud Shell at your billing-enabled project
gcloud config set project YOUR_PROJECT_ID
gcloud services enable pubsub.googleapis.com bigquery.googleapis.com

# 2. Stand it all up
cd terraform && terraform init && terraform apply   # type "yes"

# 3. Read the outputs (console URLs + publish command), then follow SETUP.md
#    step 4 onward to pre-bake, and DEMO_WALKTHROUGH.md to run the talk.
```

Cost is effectively **~$0** (a few tiny messages, a few BigQuery rows - inside the
Always Free tier). Teardown is `terraform destroy`.

## Requirements

- A Google Cloud project with **billing enabled**.
- **Google Cloud Shell** (recommended) - Terraform, `gcloud`, and `bq`
  pre-installed and pre-authenticated. Nothing to install locally.

> **Not yet run against a live project.** The Terraform reflects the documented
> Pub/Sub + BigQuery-subscription + IAM behavior, but do a full dry run before
> presenting (see [`SETUP.md`](SETUP.md)). The most likely first-run hiccup is IAM
> propagation on the BigQuery subscription - re-run `terraform apply` once and it
> resolves.
