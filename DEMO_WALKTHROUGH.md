# One Ride Through GoRide — Demo Walkthrough

A **~8-minute live demo** for the Pub/Sub Tech Spotlight, told as a story: we
follow **one ride, end to end, through a ride company called GoRide** — and watch
every part of the company react to a single published event.

> **Philosophy: pre-bake everything, run one thing live.** The infrastructure and
> a few earlier rides are prepared in [`SETUP.md`](SETUP.md) before the talk.
> Live, you publish *one* event — Maya's ride — and reveal what was already
> flowing. Nothing to stand up on stage.

**The cast:**

| Who | Their problem | Where they live in the demo |
|-----|---------------|------------------------------|
| **Maya** — a rider in San Francisco | Wants a ride on a busy Friday night | The event you publish (`user_id: u_456`) |
| **The GoRide app** | Must tell the whole company about her trip — instantly | The publisher (that's you, on stage) |
| **Dispatch** | Needs to assign drivers the moment trips happen | `match-sub` |
| **Finance** | Needs to charge her card — independently of dispatch | `billing-sub` |
| **The data team** | Needs live dashboards, not last night's batch job | `analytics-sub` → BigQuery |
| **A buggy partner app** | Sends corrupted events | The schema bounces it |
| **A poison message** | Could jam the Friday-night rush | The dead-letter topic catches it |

```
GoRide app ──▶  rides topic  ──┬─▶ match-sub     ▶ Dispatch
   (Maya)      (Avro schema)   ├─▶ billing-sub   ▶ Finance
                               └─▶ analytics-sub ▶ BigQuery (data team)

        Poison message on match-sub ──▶ rides-dead-letter
```

**Before you start:** finish [`SETUP.md`](SETUP.md). Have four console tabs open
(URLs are in the `terraform apply` output): the **rides topic**, **match-sub**,
**billing-sub**, and **BigQuery**. Keep `data/sample_events.json` open to copy
payloads from, and `commands.sh` handy — every scene has a CLI fallback.

---

## Run of show

| Scene | ~time | The story beat | The concept it lands |
|-------|-------|----------------|----------------------|
| 1 | 1:00 | Friday night at GoRide — the old way hurts | Why direct calls fail |
| 2 | 1:30 | Tour of the machinery | Topic, subscriptions, schema |
| 3 | 1:00 | Maya's trip completes — publish it live | Async publish |
| 4 | 2:00 | Dispatch and Finance both react | Fan-out |
| 5 | 1:30 | The data team already sees it | BigQuery, real-time |
| 6 | 1:00 | Two things go wrong — nothing breaks | Schema + dead-letter |

---

### Scene 1 — Friday night at GoRide (~1:00) · *no clicks*

> "It's Friday night in San Francisco. Maya opens the GoRide app and requests a
> ride. That one tap has to reach **dispatch** to find her a driver, **finance**
> to get ready to charge her card, and the **data team's** live dashboards.
>
> The old GoRide architecture did this with direct calls: the trip service called
> dispatch, then billing, then analytics, one by one. Maya stared at a spinner
> while every call finished. The night the payments service went down, *ride
> requests* started failing — payments took the whole tap down with it. And when
> the fraud team wanted in on trip events, they had to ask for changes to the
> trip service's core code."

*(This is your deck's "One tap, many systems" slide, made personal.)*

> "GoRide fixed it with one architectural move: the app now **publishes each trip
> event once** to Pub/Sub, and everyone who cares subscribes. Let me show you
> tonight's setup — and then Maya will take her ride."

---

### Scene 2 — Tour of the machinery (~1:30)

Open the **rides topic** tab. Walk it as *GoRide's* infrastructure, not as
console features:

- **The `rides` topic** — "This is the company's front door for trip events. The
  app publishes here, and its job is done."
- **The Subscriptions list** — `match-sub`, `billing-sub`, `analytics-sub`.
  "Dispatch, finance, and the data team each opened their own subscription.
  Notice what's *not* here: any mention of them in the publisher. The app has no
  idea these three exist."
- **The Schema** attached to the topic — "The one thing GoRide *does* enforce
  company-wide: every trip event must look like this — seven fields, `fare` is a
  number. It's the data contract between teams. We'll see it earn its keep in the
  final scene."

> 💡 **Concept landed:** Publisher → Topic → Subscription → Subscriber, as real
> infrastructure — with the producer fully decoupled from every consumer.

---

### Scene 3 — Maya's trip completes (~1:00) · *the live moment*

> "Maya's ride just ended — $24.50 across town. Right now, **I am the GoRide
> app**, and I'm going to do the one thing the app does: publish the event."

On the **rides topic** page → **Messages** tab → **Publish message**. Paste
Maya's event (from `data/sample_events.json`, `event_id` `evt_maya`):

```json
{"event_id":"evt_maya","user_id":"u_456","driver_id":"d_789","event_type":"trip_completed","fare":24.50,"city":"San Francisco","timestamp":"2026-07-22T22:15:00Z"}
```

Click **Publish**.

> "Done — instantly. The app didn't wait for dispatch, didn't wait for finance,
> didn't wait for analytics. Maya's phone shows 'trip complete' and she's already
> walking away. **The publisher never blocks on the rest of the company.**
>
> But three departments just got word. Let's go visit them."

**CLI fallback:** `terraform output publish_command`, or `commands.sh` Scene 3.

---

### Scene 4 — Dispatch and Finance both react (~2:00)

**Visit dispatch first.** Switch to the **match-sub** tab → **Messages** →
**Pull**.

> "Here's dispatch's inbox — and there's Maya's trip, `evt_maya`. Dispatch marks
> her driver free and puts him back in the Friday-night pool."

**Now visit finance.** Switch to the **billing-sub** tab → **Pull**.

> "And here is the *same event, again* — finance's **own copy**. They'll charge
> her card and send the receipt. Finance never talked to dispatch. Neither knows
> the other pulled it. If finance's systems were down for an hour, their copy
> would wait here — and dispatch wouldn't notice a thing."

> 💡 **Concepts landed:**
> - **Fan-out** — *every subscription gets its own copy.* One publish, N
>   independent reactions. When the fraud team finally wants in? **One new
>   subscription. Zero changes** to the app, dispatch, or finance.
> - **vs. load-balancing** — "If dispatch got busy and added a second worker on
>   `match-sub`, those two would **split** the messages — that's scaling one job.
>   Separate subscriptions = separate jobs."
> - **Acking** — "When dispatch acks, it's saying *'processed successfully.'*
>   Until then, Pub/Sub keeps redelivering. GoRide's rule: process first, ack
>   after — so a crash mid-processing never loses a trip."

**CLI fallback:** `commands.sh` Scene 4 — pull from each subscription.

---

### Scene 5 — The data team already sees it (~1:30)

> "While we were visiting dispatch and finance, the third subscriber never even
> needed a person. Let's check the data team's warehouse."

Switch to the **BigQuery** tab and run (also in `terraform output run_this_query`):

```sql
SELECT event_type, city, fare, timestamp
FROM `rides_analytics.trip_events`
ORDER BY timestamp DESC
LIMIT 20;
```

> "There's tonight's rides — and look at the top: **Maya's trip is already a
> row.** No ETL job, no nightly batch, no code. The `analytics-sub` is a BigQuery
> subscription — Pub/Sub streams events straight into the table. This is where
> GoRide's surge dashboard reads from, and it's seconds behind reality — remember
> the deck's '10th trip this month → loyalty push' flow? It starts exactly here."

If `evt_maya` hasn't landed yet, re-run the query — it streams in within seconds.
(And this is *why we pre-baked rows*: the payoff never depends on live timing.)

> 💡 **Concept landed:** the third delivery type — **export** — and the deck's
> "BigQuery hop": the same event that drove operations also feeds analytics, in
> real time.

---

### Scene 6 — Two things go wrong. Nothing breaks. (~1:00)

> "It's still Friday night, so of course something goes wrong. Two somethings."

**First: the buggy partner app.** "A partner integration ships a bug — it sends
`fare` as text." Publish this (Messages tab, or `commands.sh` optional scene):

```json
{"event_id":"evt_bad","user_id":"u_999","driver_id":"d_000","event_type":"trip_completed","fare":"not-a-number","city":"Nowhere","timestamp":"2026-07-22T22:20:00Z"}
```

→ **Rejected at publish time.**

> "The schema bounced it at the front door. Dispatch, finance, and the dashboard
> never see garbage — the contract holds for everyone, automatically."

**Second: the poison message.** Open the **rides-dead-letter** topic (just show
the config on `match-sub`):

> "And if a message gets *through* but dispatch keeps crashing on it? After 5
> failed deliveries, `match-sub` routes it to this dead-letter topic. The broken
> message gets quarantined for an engineer to inspect Monday morning — and the
> Friday-night rush keeps flowing behind it."

> 💡 **Concept landed:** production features are configuration, not code —
> schemas, dead-letter, retry policy.

---

## The closer

> "One tap. **One publish.** Dispatch reacted, finance reacted, the dashboard
> updated — three departments, each at their own pace, each with their own copy.
> A corrupted event got bounced and a poison message got quarantined, and none of
> it touched Maya's experience. The GoRide app knows about **none** of this — it
> published once, and everything reacted.
>
> That's Cloud Pub/Sub: **publish once. Let everything react.**"

---

## Cleanup

```bash
cd terraform && terraform destroy   # type "yes"
```

## If something goes wrong live (for real)

- **Live publish is slow / rejected:** fall back to the pre-baked rows in
  BigQuery (Scene 5) — they're already there. For a rejected publish, check the
  JSON matches the schema (all seven fields, `fare` numeric).
- **A Pull shows nothing:** the message may have been acked on a previous run.
  Publish Maya's event again with a new `event_id` and pull again.
- **Network dies:** play the screen recording you captured during setup.
