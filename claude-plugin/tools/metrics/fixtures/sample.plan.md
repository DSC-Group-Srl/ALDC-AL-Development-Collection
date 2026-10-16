# Plan: U-04 — Customer credit check on release

Blocks release of a sales order when the customer is over the credit limit and calls the
external rating service through HttpClient.

**Tier:** MEDIUM · **Base:** 0000000 · **Branch:** aldc/U-04
**Test environment:** sandbox-tests
**Approved:** 2026-10-16

## Work packages

| WP | Title | Wave | Depends on | Owns (globs) | Objects (IDs) | Test codeunits (IDs) | Domains | Review |
|----|-------|------|-----------|--------------|---------------|----------------------|---------|--------|
| WP-1 | Data model | 1 | — | `app/src/Credit/Tables/**` | Table 50100 "Credit Setup", Enum 50101 "Credit Rating" | 50200 "Credit Setup Tests" | tables | light |
| WP-2 | Release check | 2 | WP-1 | `app/src/Credit/Release/**` | Codeunit 50110 "Credit Check" | 50210 "Credit Check Tests", 50211 "Credit Rating Tests" | events, performance | full |
| WP-3 | Rating API | 2 | WP-1 | `app/src/Credit/Api/**` | Page 50120 "Credit Rating API" | — | api | light |

**Codeunit → WP:** 50200 → WP-1 · 50210 → WP-2 · 50211 → WP-2

## Planned objects

| Object type | New/Ext | Count | Est. complexity (S/M/L) |
|-------------|---------|------:|-------------------------|
| table | New | 1 | M |
| Table extension | New | 1 | S |
| enum | New | 1 | S |
| codeunit | New | 1 | L |
| codeunit | Ext | 1 | M |
| API page | New | 1 | M |
| test codeunit | New | 3 | M |
| profile | New | 1 | S |

## Open questions

1. Block or warn when the rating service is down? → warn
2. Which credit limit field wins for a bill-to customer?
3. {question — options} → {answer, once given}

## Wave log

## Deferred
