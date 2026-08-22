---
name: inspect-conversation
description: Inspect a single Pearl AI conversation end-to-end (DB + CloudWatch). Pulls full message history, per-turn tool action trace, dissatisfaction signals, and a correlated CloudWatch log slice from prod, then summarizes flow, tool quality, subwriter fidelity, and engagement signals. Invoke as /inspect-conversation <conversation_id_or_uuid>.
---

# /inspect-conversation

Produces a deep, single-conversation post-mortem from prod data. Pulls every message, every tool action, every explicit dissatisfaction signal, and a CloudWatch log slice that covers the whole conversation window — then renders an opinionated summary that answers a fixed set of quality questions.

This is the partner to the `debug-prod-users` window-scan workflow; use this one when you already know *which* conversation you want to look at.

## Invocation

`/inspect-conversation <id>`

Where `<id>` is one of:
- A numeric `conversation_id` (e.g. `457`) — the primary key in `conversations`, **preferred**.
- A `conversation_uuid` — accepted with or without dashes (e.g. `aa575a29-dbe0-4705-ab4a-441689a44634` or `aa575a29dbe04705ab4a441689a44634`).

If no argument is provided, STOP and ask the user which conversation to inspect before doing anything else.

## Prerequisites — check these first, fail loudly if any is missing

1. **Bastion tunnel is up.** The user runs `bastion-prod` manually in a separate shell. Verify with:
   ```bash
   nc -z "$CLAUDE_DATABASE_HOST" "$CLAUDE_DATABASE_PORT"
   ```
   If it fails, STOP and say exactly: *"The bastion tunnel isn't up. Open another shell, run `bastion-prod`, then re-run this skill."* Do not attempt to start it.

2. **DB env vars set.** Required: `CLAUDE_DATABASE_HOST`, `CLAUDE_DATABASE_PORT`, `CLAUDE_DATABASE_USER`, `CLAUDE_DATABASE_PASSWORD`, `CLAUDE_DATABASE_NAME`. Check these inside the same Python script that runs the queries (read `os.environ` and raise if any are missing) — do NOT use a separate `bash -c` wrapper or `${!var}` indirection, since those need broader shell permissions than the rest of the skill.

3. **AWS CLI authenticated.** Run `aws sts get-caller-identity`. If it fails, STOP and tell the user to auth.

## Step 1 — Pull conversation data from prod RDS

Use `pymysql` via the platform-ai conda environment. All queries are read-only `SELECT`s. Never run DML or DDL.

**Always write the Python to a file at `/tmp/inspect_conversation.py` and invoke it as `conda run -n platform-ai --no-capture-output python3 /tmp/inspect_conversation.py`.** Do NOT use `python3 -c "<inline>"` — inline invocations are harder to pre-approve in the permission allow-list and harder to review.

Connect with:
```python
import os, pymysql
conn = pymysql.connect(
    host=os.environ["CLAUDE_DATABASE_HOST"],
    port=int(os.environ["CLAUDE_DATABASE_PORT"]),
    user=os.environ["CLAUDE_DATABASE_USER"],
    password=os.environ["CLAUDE_DATABASE_PASSWORD"],
    database=os.environ["CLAUDE_DATABASE_NAME"],
    cursorclass=pymysql.cursors.DictCursor,
)
```

### Argument parsing

```python
arg = "<value passed in>".strip()
if arg.isdigit():
    where = "conversation_id = %s"
    param = int(arg)
else:
    where = "REPLACE(conversation_uuid, '-', '') = %s"
    param = arg.replace("-", "").lower()
```

If the lookup returns zero rows, STOP and print: *"No conversation found for `<arg>` in prod."*

### Queries to run

**Conversation header:**
```sql
SELECT conversation_id, conversation_uuid, user_id, organization_id,
       destination, created_at, updated_at
FROM conversations
WHERE <where>;
```

**Full message history** (do NOT truncate `content` — the DB column is capped at 10000 chars per row, so size is bounded):
```sql
SELECT message_id, message_uuid, role, answer_type,
       enforcement_success, enforcement_failure_reason, vote,
       request_timestamp, response_timestamp, duration_ms, content
FROM messages
WHERE conversation_id = :cid
ORDER BY message_id;
```

**Tool actions for every AI message in the conversation:**
```sql
SELECT message_id, action_id, tool_name, action_type, tool_status,
       tool_summary
FROM actions
WHERE message_id IN (:ai_msg_ids)
ORDER BY message_id, action_id;
```

**Explicit dissatisfaction signals** (per-message ratings + feedback):
```sql
SELECT m.message_id,
       GROUP_CONCAT(DISTINCT mr.rating) AS ratings,
       GROUP_CONCAT(DISTINCT mf.feedback_text SEPARATOR ' | ') AS feedback
FROM messages m
LEFT JOIN message_ratings mr ON mr.message_id = m.message_id
LEFT JOIN message_feedback mf ON mf.message_id = m.message_id AND mf.deleted_at IS NULL
WHERE m.conversation_id = :cid
GROUP BY m.message_id;
```

### Emit a single JSON blob to stdout

Have the script print one JSON object with keys `conversation`, `messages`, `actions_by_message_id`, `signals_by_message_id`. The next step reads this back. Use `default=str` so `datetime` values serialize cleanly.

## Step 2 — Find the active prod EB log group

Prod is blue-green across `prod-platform-ai-a` and `prod-platform-ai-b`. The current stdout log group is the one with the most recent event. The active group ends in `stdouterr.log` (not `web.stdout.log`).

```bash
for slot in a b; do
  g="/aws/elasticbeanstalk/prod-platform-ai-${slot}/var/log/eb-docker/containers/eb-current-app/stdouterr.log"
  ts=$(aws logs describe-log-streams --log-group-name "$g" \
        --order-by LastEventTime --descending --max-items 1 \
        --query 'logStreams[0].lastEventTimestamp' --output text 2>/dev/null)
  echo "$g $ts"
done
```

Pick the group with the largest `ts`. Save as `$ACTIVE_LOG_GROUP` and include it in the report header.

## Step 3 — Correlate with CloudWatch logs

**This step is as important as the DB query.** The DB stores the surface symptom; the logs explain the mechanism (sub-writer exceptions, JSON parse failures, model timeouts, validator messages, retry decisions).

Compute the log window from the conversation:
- `start_ms = (earliest non-null request_timestamp − 120s) in ms`
- `end_ms   = (latest non-null response_timestamp + 120s) in ms`

If a conversation has no AI messages, fall back to `created_at` / `updated_at` ± 120s.

The DB stores `conversation_uuid` dashless; logs use dashed UUIDs. Re-insert dashes (8-4-4-4-12) before searching:
```python
u = uuid_no_dashes
dashed = f"{u[0:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
```

Primary search:
```bash
aws logs filter-log-events \
  --log-group-name "$ACTIVE_LOG_GROUP" \
  --start-time <start_ms> --end-time <end_ms> \
  --filter-pattern "<dashed_uuid>" \
  --query 'events[].[timestamp,message]' --output text
```

Then, for each AI message that has a `FAILURE` tool action or `enforcement_success = 0` or `answer_type = 'Warning'`, run a follow-up search on the same window for the relevant tool name and for `ERROR`, `Traceback`, `Exception`, `Warning` so the report can quote the actual failure text alongside the action row.

Run a third pass across the **entire** log window (not just failed turns) for upstream-infrastructure signals — these don't always surface as a tool FAILURE but they shape behavior:
- `TMS`, `upstream`, `Connection`, `Timeout`, `ReadTimeout`, `ConnectError`
- HTTP status hints: `5xx`, ` 500 `, ` 502 `, ` 503 `, ` 504 `, `401`, `403`
- Pearl integration markers: `tms_api`, `tms_client`, `httpx`

If a flagged message has no matching log entries, still include the entry and note "no matching log lines" — don't silently drop it.

## Step 4 — Render the report

Markdown to stdout only. No file output. Show **full** user questions and **full** AI responses verbatim — do not truncate. The `messages.content` column is capped at 10000 chars, so size is bounded.

```
# Conversation <id> — Inspection

- conversation_uuid: <uuid>
- user_id / organization_id: <user> / <org>
- destination: <dest>
- time range: <first request_timestamp> → <last response_timestamp> UTC
- turns: <N user> / <M ai>
- active log group: <ACTIVE_LOG_GROUP>

## Turn-by-turn

### Turn 1 · user (msg_id <id>)
      <full user content, verbatim>

### Turn 1 · ai (msg_id <id>, <duration_ms> ms, answer_type=<type>, enforcement_success=<0|1>)
      <full ai content, verbatim>
- Tools: tool_a ✅, tool_b ❌ (<one-line failure summary>), tool_b ✅ (retry)
- Signals: vote=<n>, rating=<r or none>, feedback=<text or none>
- Log notes: <2–8 line excerpt around any FAILURE or warning; 'no matching log lines' if empty>

### Turn 2 · user (msg_id ...)
...
```

After the turn-by-turn, write a section that **answers the required quality questions in order**. Each answer should reference specific turn numbers / msg_ids / tool names so the reader can audit your reasoning.

```
## Quality assessment

### Overall flow & tone
<2–5 sentences. What was the user trying to do? How coherently did the conversation progress? Was the AI's register consistent (helpful / abrupt / apologetic / repetitive)?>

### Disruptions to the desired flow

**Did the user have to ask the same thing multiple times?**
<Compare user turns. Quote any rephrasings, "no, I meant", "try again", "that's not what I asked", or topical repeats. If clean, say so explicitly.>

**Did the AI have difficulty answering (errors, retries, formatting issues)?**
<List tool failures, enforcement failures, Warning answer types, log-level ERROR/Traceback lines, malformed output, and any turn whose duration is an outlier suggesting silent retries. Note whether each was recovered.>

**Engagement-loss signals**
- **Explicit:** <list any vote=-1, rating=not-helpful, MessageFeedback rows; quote feedback text. "None" if clean.>
- **Implicit:** <look for short low-effort follow-ups ("no", "wrong", "ugh"), abandonment (conversation ends right after a weak AI answer with no user follow-up), growing frustration in successive user turns, sudden topic abandonment, profanity, or large time gaps between user turns. "None" if clean.>

### Tool use

The Pearl agent loop is built around a *collector* (the data-gathering tools — `lookup_entity`, `list_surveys`, `review_survey_responses`, `fetch_sessions`, etc.) that runs, and a *subwriter* (`finalize_answer`) that takes the collected artifacts and authors the final user-facing message. Roughly 8% of tool calls are expected to fail; the design relies on validators (pydantic field/value errors, `validate_survey_id`, `validate_entity_ids`, date-window caps) producing actionable error text the agent can retry against. Evaluate against that design.

**Tool choice (interpretive accuracy)**
<Did the chosen tools match what the user asked for? Quote turns where tool selection was strong or weak — e.g. routing a "show me the responses" question through `review_survey_responses` vs `get_survey_question_results` correctly; reaching for `lookup_entity` when a name needed resolving; *not* reaching for a tool when the answer was already in conversation history. Bad picks include over-fetching, redundant tools, or picking a free-text tool for a structured question.>

**Tool call failures**
<List each `tool_status='FAILURE'` action. For each, name the root cause from the log excerpt (pydantic ValidationError, hallucinated survey_id, date window > cap, missing required arg, upstream timeout, 5xx). `_None._` if clean. Headline number: `<X>/<Y> tool calls failed`.>

**Validation & self-correction**
<For each failure: was there a validator that produced a clear, retry-able error message? Did the agent in fact retry, and did the retry succeed on the corrected args? Quote the corrected call. When the loop works, you should see *failure → validator message in logs → next call with fixed args → success*. When it doesn't, the failure either repeats verbatim or the agent gives up and routes to a Warning.>

**Upstream TMS evidence**
<Inspect the third-pass log scan for upstream-infrastructure signals (5xx, timeouts, connection errors, TMS-side stack traces). If TMS hiccuped during this conversation, separate that from agent-side issues — a 503 from TMS is not the model's fault. `_No upstream TMS errors observed._` if clean.>

**Collector → subwriter handoff**
<For each AI turn, locate the `finalize_answer` action and read its `tool_summary`. That summary is the handoff payload: it's what the subwriter sees from the collector. Did it faithfully describe what the upstream tools actually returned (right row counts, right filters, right entity IDs)? A faithful handoff says "tool X returned 0 rows for student Y on survey Z"; a broken handoff inflates the count, drops the filter, or reframes the data before the subwriter sees it.>

### Subwriter output

**Faithful representation of the data**
<Compare the final AI message content to what the collector actually handed off. Did the subwriter invent numbers, misstate filters, conflate two tools' results, or claim coverage the data doesn't have? Pay special attention to: numeric totals, time ranges, entity names/IDs, and any "we checked X" framing.>

**Effectiveness for the user**
<Did it answer the question the user actually asked, in a form that's useful? An accurate-but-unhelpful answer ("no data, sorry") rates lower than a fewer-words-but-more-useful one ("no responses yet — the assessment window opens next Monday"). Note any clarity wins or losses (good vs poor formatting, missing next steps, walls of boilerplate, missing context the data clearly supports).>

### Conversation inconsistencies

<Compare turns *to each other*, not just each turn to the user's question. Look for:
- **Repeat questions, different answers** — same question (possibly rephrased) answered differently across turns. Quote both answers.
- **Mixed definitions** — terms used inconsistently (e.g. "school" vs "organization", "session" vs "session series", "tutor" vs "user", "survey" vs "survey response"), or the same entity referenced by different labels in different turns.
- **Drifting numbers / IDs** — counts, totals, or IDs that change between turns without the underlying data having changed.
- **Stale references** — turn N+1 acts as if turn N didn't happen, or recapitulates work the agent should already have cached.

These are most often **app-level disruptions** (survey_id/entity_id cache loss across the turn boundary, conversation history rehydration dropping artifacts, a different model variant picking up after a tool retry, a Redis TTL expiry mid-conversation) rather than the model being inherently inconsistent. When possible, name the suspected mechanism. `_No material inconsistencies observed._` if clean.>

### Bottom line
<1–2 sentences: did the user get what they came for? Was it a clean turn, a recovered one, or a degraded experience? Call out the single most important issue worth fixing if any.>
```

If a section is empty (e.g. no tool failures, no explicit signals), still print the header and say `_None._` — don't omit it.

## Safety

- **Read-only DB.** Never run `INSERT` / `UPDATE` / `DELETE` / DDL. If the user asks for follow-up writes, stop and confirm first.
- **Never echo `$CLAUDE_DATABASE_PASSWORD`** — not in commands you print, not in error messages, not in summaries.
- **PII awareness.** Message content may include student/tutor identifying info. Keep the report in the terminal; don't forward it to external tools, pastebins, Slack, or GitHub issues without explicit user approval.
- **Read-only logs.** Never delete or modify CloudWatch streams.
