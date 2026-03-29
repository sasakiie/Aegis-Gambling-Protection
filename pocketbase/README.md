# AEGIS PocketBase Backend Artifacts

This directory contains the Phase B backend artifacts for the AEGIS
community-report backend.

Contents:
- `collections/` - collection definitions for `reports` and `ad_rules`
- `hooks/` - PocketBase JS hook logic for rate limiting and real-time
  aggregation

These files are intended to lock the backend contract used by the Flutter
client services added in Phase B.

## Collections

- `reports.collection.json`
  - raw client-submitted reports
  - clients may create only
  - server-controlled fields are populated by hooks
- `ad_rules.collection.json`
  - trusted syncable rules
  - clients may read only trusted records
  - clients may not create/update/delete

## Hooks

- `phase_b_reports.pb.js`
  - normalizes inbound reports
  - enforces the daily quota of 5 reports per token
  - stamps `created_by_token` and `status`
  - performs real-time aggregation after each accepted report
  - promotes rules only when selector consistency and threshold rules pass

## Environment

The Flutter app expects:

- `POCKETBASE_URL`

to be set in `.env`.

## Notes

- Hook APIs may need small adjustments based on the exact PocketBase version
  used at deployment time.
- The logic and field names here intentionally follow
  [phase_b_implementation_spec.md](/c:/Kmitl/Junior/term2/pratical_proj/Aegis_prog/phase_b_implementation_spec.md).
