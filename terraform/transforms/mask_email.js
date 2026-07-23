// Single Message Transform (SMT) attached to analytics-sub.
//
// Runs INSIDE Pub/Sub, per message, at delivery time - just before the message
// is written to BigQuery. The topic stores the full event (finance's receipt
// flow needs the real address); this masks rider_email in-flight so PII never
// lands in the warehouse: maya@example.com -> m***@example.com.
//
// `message.data` is the message body as a string (our topic uses JSON
// encoding); return the (modified) message to continue delivery.
function maskEmail(message, metadata) {
  const event = JSON.parse(message.data);
  if (event.rider_email) {
    event.rider_email = event.rider_email.replace(/^(.).*(@.*)$/, "$1***$2");
  }
  message.data = JSON.stringify(event);
  return message;
}
