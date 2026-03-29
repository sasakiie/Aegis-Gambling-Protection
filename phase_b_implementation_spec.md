# AEGIS Phase B Implementation Spec

This document defines the implementation contract for Phase B of AEGIS:
- PocketBase backend
- Anonymous auth
- Report submission
- Server-to-client rule sync
- Anti-poisoning moderation flow

This spec is intended to freeze the contract before implementation so the Flutter client and PocketBase backend can evolve against the same assumptions.

## 1. Goals

Phase B exists to add a shared backend knowledge layer without weakening safety.

Primary goals:
- Allow clients to submit gambling reports and selector reports
- Prevent direct client poisoning of production rules
- Limit abuse with anonymous token-based rate limiting
- Sync only trusted rules back to clients
- Merge server-approved rules into local Hive cache safely

Non-goals for this phase:
- Full admin dashboard UI
- Complex cron infrastructure
- Multi-region scaling

## 2. System Boundaries

Trusted:
- PocketBase schema
- PocketBase access rules
- PocketBase hooks
- Admin moderation actions

Untrusted:
- All client-submitted report payloads
- Anonymous users
- Selectors supplied by clients
- Client-side counters and quotas

Important rule:
- The client must never be able to write `verified`, `report_count`, or `created_by_token` directly into trusted rule records.

## 3. Core Collections

### 3.1 `reports`

Raw inbound reports submitted by clients.

Fields:
- `domain` : text, required, normalized lowercase domain
- `selectors` : json array of strings, optional
- `is_gambling` : bool, required
- `reason` : text, optional
- `report_type` : text, required
- `client_version` : text, optional
- `created_by_token` : text, required, server-controlled
- `status` : text, default `pending`
- `created` : datetime, system field
- `updated` : datetime, system field

Allowed `report_type` values:
- `gambling_site`
- `ad_selector`
- `false_positive`
- `selector_miss`

Rules:
- Client may create
- Client may not update/delete
- Client may not set server-controlled fields

### 3.2 `ad_rules`

Trusted rules eligible for client sync.

Fields:
- `domain` : text, unique, required
- `selectors` : json array of strings
- `is_gambling` : bool, required
- `report_count` : number, default `0`
- `verified` : bool, default `false`
- `source_type` : text, required
- `created_by_token` : text, optional
- `last_reported_at` : datetime, optional
- `created` : datetime, system field
- `updated` : datetime, system field

Allowed `source_type` values:
- `admin_verified`
- `report_promoted`
- `seeded`

Rules:
- Client read allowed only when:
  - `verified = true`
  - OR `report_count >= 10`
- Client create/update/delete forbidden

### 3.3 `users`

PocketBase built-in auth collection used for anonymous auth.

Usage:
- Every reporting client authenticates anonymously first
- The user id or auth identity is treated as the token identity for quota enforcement

## 4. Error Contract

Client and backend must agree on error handling semantics.

### 4.1 HTTP Status Mapping

`400 Bad Request`
- Meaning: validation error
- Client action: show field-level or form-level validation message

`401 Unauthorized`
- Meaning: auth/session invalid or expired
- Client action:
  - attempt session refresh or re-auth anonymously
  - if re-auth fails, disable report UI gracefully

`429 Too Many Requests`
- Meaning: daily report quota exceeded
- Client action:
  - show non-fatal status message
  - do not retry automatically

`5xx Server Error`
- Meaning: backend unavailable or hook/server failure
- Client action:
  - degrade gracefully
  - keep browser/detection flow running
  - disable or postpone report/sync features

### 4.2 Client UX Messages

Suggested strings:
- `400` -> `Please check the report details and try again.`
- `401` -> `Report session expired. Reconnecting...`
- `429` -> `Report is temporarily unavailable because the daily limit has been reached.`
- `5xx` -> `Report is temporarily unavailable. Please try again later.`

## 5. Anonymous Auth Contract

### 5.1 Required Flow

On first app launch:
1. Client requests anonymous auth from PocketBase
2. Client stores session locally
3. Client reuses session for report/sync calls

When session expires:
1. Client tries refresh or re-login anonymously
2. If recovery succeeds, continue
3. If recovery fails, disable report features gracefully

### 5.2 Graceful Failure Requirement

Auth failure must not crash the app.

If auth is unavailable:
- Browser and local detection continue normally
- Report button is disabled or returns a non-fatal message
- Sync may be postponed

## 6. Rate Limiting

### 6.1 Policy

Baseline quota:
- max `5` reports per token per day

This quota is enforced server-side, not only client-side.

### 6.2 Enforcement Strategy

PocketBase hook must reject over-quota create requests for `reports`.

Implementation style:
- `onRecordCreateRequest` or equivalent request-stage hook is preferred
- If only post-create hooks are practical in a given setup, implementation must still prevent the record from persisting when over quota

Pseudo-flow:
1. Read `created_by_token`
2. Count today's reports for that token
3. If count >= 5, reject with `429`

### 6.3 Why Server Enforcement Is Mandatory

Client-side enforcement alone is insufficient because:
- modified clients can bypass it
- replay/spam attacks remain possible

## 7. Moderation and Promotion Flow

### 7.1 High-Level Flow

1. Client submits a record into `reports`
2. PocketBase hook or aggregation logic re-evaluates all reports for that domain
3. If promotion criteria are satisfied, create or update `ad_rules`
4. Admin may later mark a rule as `verified = true`
5. Clients sync only trusted `ad_rules`

### 7.2 Promotion Criteria

Promote `reports` into `ad_rules` when all of the following are true:
- `report_count >= 10`
- and a single selector set or canonical selector appears in at least `60%` of reports for that domain

If the report is for a site-level gambling classification without selectors:
- promotion may still happen when repeated consistent `is_gambling = true` reports reach threshold
- admin verification remains preferred for ambiguous cases

### 7.3 Selector Consistency Definition

For this phase, selector consistency is defined as:
- normalize selectors by trimming whitespace
- group identical selectors
- compute dominant selector frequency
- promote only if dominant selector support is at least `60%`

This keeps moderation deterministic and avoids relying fully on admin review.

## 8. Aggregation Strategy

For project scope, use real-time aggregation.

When:
- aggregation runs immediately after a new `reports` record is accepted

Why:
- simpler than scheduled jobs
- enough for current scope
- easier to validate during development/demo

Tradeoff:
- heavier per-write query cost
- acceptable for low to moderate project traffic

Future upgrade path:
- move aggregation to scheduled job or external worker if traffic grows

## 9. Sync Contract

### 9.1 Client Download Filter

Client may sync only records from `ad_rules` where:
- `verified = true`
- OR `report_count >= 10`

### 9.2 Incremental Sync

Client stores `lastSyncedAt` locally.

Sync query must request only:
- trusted records
- and records with `updated > lastSyncedAt`

Suggested query shape:
- `(verified=true || report_count>=10) && updated > "<lastSyncedAt>"`

### 9.3 First Sync

If `lastSyncedAt` does not exist:
- perform full trusted sync

### 9.4 Recovery

If incremental sync fails because cursor/state is invalid:
- log the failure
- fallback to full trusted sync

## 10. Flutter Client Responsibilities

### 10.1 `server_auth_service.dart`

Responsibilities:
- initialize anonymous session
- check auth state
- refresh or re-login when needed
- expose whether report features are currently available

### 10.2 `report_service.dart`

Responsibilities:
- validate report payload before send
- ensure anonymous auth exists
- submit report to PocketBase
- map backend errors into UI-safe states

### 10.3 `server_sync_service.dart`

Responsibilities:
- fetch trusted rules only
- use `lastSyncedAt` cursor
- merge remote records into local Hive cache
- persist sync timestamp

## 11. Merge Strategy with Hive

Local store remains Hive via `AdRemovalCache`.

Merge rules:
- server verified rules override local AI-generated rules
- newer trusted server record may replace local cache for same domain
- `needsReview=true` local entries may be overwritten by trusted server rules
- conflicting local non-verified state must not overwrite trusted server data

Suggested precedence:
1. server verified
2. server promoted/trusted
3. local AI cache
4. local unresolved review state

## 12. Validation Rules

### 12.1 Client Validation

Before submit:
- domain must parse successfully
- domain must be normalized lowercase without scheme
- selectors length must be bounded
- selector strings must be bounded in size
- reason length must be bounded

### 12.2 Server Validation

Reject reports when:
- `domain` empty or malformed
- `selectors` payload too large
- selector count exceeds allowed max
- duplicate spam is detected in a short window

## 13. Logging Requirements

Must log:
- auth success/failure
- auth recovery attempts
- report success/failure
- rate limit rejection
- sync counts
- merge actions
- fallback to full sync

The Flutter side should route these into `DebugLogger` where practical.

## 14. Milestones

### Milestone 1: Backend Contract Freeze
- finalize schema
- finalize error contract
- finalize promotion criteria
- finalize incremental sync cursor contract

### Milestone 2: PocketBase Enforcement
- create collections
- configure rules
- implement anonymous auth flow
- implement server-side rate limit hook
- implement real-time aggregation hook

### Milestone 3: Flutter Services
- add `server_auth_service.dart`
- add `report_service.dart`
- add `server_sync_service.dart`
- map backend errors to UX states

### Milestone 4: Hive Integration
- merge synced rules into `AdRemovalCache`
- persist `lastSyncedAt`
- define conflict resolution behavior in code

### Milestone 5: UI and QA
- report dialog/status
- auth unavailable state
- sync status state
- unit/integration/widget/manual tests

## 15. Definition of Done

Phase B is done when:
- anonymous auth works automatically
- report submission works with validation
- server-side rate limiting rejects over-quota requests
- aggregation promotes trusted rules deterministically
- client sync downloads only trusted delta records
- synced rules merge into Hive correctly
- auth/report failures degrade gracefully
- tests cover auth, report, sync, merge, and quota behavior

