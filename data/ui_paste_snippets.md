# Copy-paste snippets for the hand-build (UI) segment

Everything you paste into the Console while building the scratch copy by hand,
in the order the forms ask for it. Scratch names (`-manual`) keep this separate
from the real stack Terraform builds - `terraform apply` would fail on a name
collision otherwise.

## 1. Topic form - the Avro schema

Topic ID: `rides-manual` · Schema ID: `trip-event-manual` · Type: Avro ·
Message encoding: JSON

```json
{
  "type": "record",
  "name": "TripCompleted",
  "fields": [
    { "name": "event_id",    "type": "string" },
    { "name": "user_id",     "type": "string" },
    { "name": "rider_email", "type": "string" },
    { "name": "driver_id",   "type": "string" },
    { "name": "event_type",  "type": "string" },
    { "name": "fare",        "type": "double" },
    { "name": "city",        "type": "string" },
    { "name": "timestamp",   "type": "string" }
  ]
}
```

## 2. Subscription form - the message transform

Subscription ID: `analytics-manual-sub` · Topic: `rides-manual` ·
Delivery type: Pull · Function name: `maskEmail`

```javascript
function maskEmail(message, metadata) {
  const event = JSON.parse(message.data);
  if (event.rider_email) {
    event.rider_email = event.rider_email.replace(/^(.).*(@.*)$/, "$1***$2");
  }
  message.data = JSON.stringify(event);
  return message;
}
```

## 3. Test transform - sample message

Paste as the test input; the output should show `m***@example.com`:

```json
{"event_id":"evt_maya","user_id":"u_456","rider_email":"maya@example.com","driver_id":"d_789","event_type":"trip_completed","fare":24.50,"city":"San Francisco","timestamp":"2026-07-22T22:15:00Z"}
```

## 4. Publish a message by hand (topic page - Messages tab - Publish message)

Valid event - the schema accepts it:

```json
{"event_id":"evt_manual","user_id":"u_456","rider_email":"maya@example.com","driver_id":"d_789","event_type":"trip_completed","fare":24.50,"city":"San Francisco","timestamp":"2026-07-22T22:15:00Z"}
```

Broken event - `fare` as text, the schema REJECTS it (that's the point):

```json
{"event_id":"evt_bad","user_id":"u_999","rider_email":"partner-bot@example.com","driver_id":"d_000","event_type":"trip_completed","fare":"not-a-number","city":"Nowhere","timestamp":"2026-07-22T22:20:00Z"}
```

## 5. The reveal

Stop here - no BigQuery table, no IAM, no dead-letter yet, and that's the
hard 75%. In a terminal:

```bash
cd terraform && terraform init && terraform apply   # type "yes"
```

Cleanup of the scratch copy (anytime): delete `analytics-manual-sub`, then
`rides-manual`, then the `trip-event-manual` schema in the console - or:

```bash
gcloud pubsub subscriptions delete analytics-manual-sub
gcloud pubsub topics delete rides-manual
gcloud pubsub schemas delete trip-event-manual
```
