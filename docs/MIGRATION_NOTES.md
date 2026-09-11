# Gota — Consolidation Notes

This document records the important consolidation decisions.

## Replaced decisions

| Previous material | Consolidated decision |
|---|---|
| Firebase | Supabase |
| Phone OTP | Anonymous Auth |
| Firestore | PostgreSQL + PostGIS |
| Firebase Storage | Supabase Storage |
| Cloud Functions | Supabase Edge Functions |
| Hive/WorkManager mandatory offline queue | Deferred; not Sprint 01 |
| 1–2 photos | 1–3 photos |
| 2 validation confirmations | Validation is independent; resolution requires 3 distinct users |
| PENDIENTE/CONFIRMADA/CERRADA_* | ACTIVE/RESOLVED |
| Phone hash as public identity | Supabase anonymous user ID, never public |
| Google Maps | MapLibre + OpenStreetMap abstraction |
| Parroquia as mandatory MVP relation | Municipality + configurable sector; do not invent geography |

## Reused from previous material

- visual identity and color tokens;
- screen composition;
- community-oriented microcopy;
- review checklist discipline;
- small-task construction workflow;
- prototype interaction patterns;
- accessibility rules;
- explicit handling of offline/empty/error states as UX concerns.

## Prototype status

`prototipo/index.html` is a visual/interaction reference only.

If prototype behavior contradicts this documentation, this documentation wins.
