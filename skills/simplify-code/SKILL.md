---
name: simplify-code
description: Review recently changed code for reuse, duplication, quality, and efficiency, then apply behavior-preserving simplifications. Use before shipping substantial application changes or when asked to simplify a diff.
metadata:
  short-description: Review and simplify changed code across runtimes
---

# Simplify changed code

Review the selected diff and apply only concrete, behavior-preserving improvements. This shared package works in Claude Code and Codex; it does not depend on either runtime's bundled review commands.

## Scope

Read the repository instructions. Use the caller's base, paths, focus, and review-only constraint when supplied. Otherwise use the branch's merge base with its intended PR base, plus staged and unstaged changes. Include relevant new untracked source files, but exclude unrelated work and generated artifacts. If the base cannot be established, review the known working diff and disclose the limitation.

Changed code is the target, but the whole repository is available as evidence: search for existing helpers, fixtures, and equivalent implementations before proposing a new abstraction. Comparing changed files only against one another misses code copied from an unchanged module.

## Independent review

When delegation is available, launch three read-only reviewers in parallel. This skill explicitly requests that delegation. Give each reviewer the same diff, repository instructions, and access to surrounding code, with distinct ownership:

- **Reuse and duplication:** find copied logic, repeated scaffolding, and existing helpers or fixtures that can replace new code without changing semantics. Check fixture scope and mutation isolation before suggesting shared fixtures.
- **Quality and simplicity:** find unnecessary state, redundant branches, dead abstractions, and indirect interfaces that can be removed. Preserve useful boundaries and avoid making unrelated style changes.
- **Efficiency:** find repeated lookups, unnecessary work in loops, repeated setup, and avoidable scans or allocations. Require evidence from control flow, query counts, or measurements; preserve locking, transaction, cache lifetime, and freshness semantics.

In Claude Code use its Agent capability; in Codex use the available spawn-agent capability and collect the results. Reviewers must not edit, commit, publish, or invoke ship. If delegation is unavailable, perform the three passes sequentially and disclose that fallback. Never claim independent review when it did not run.

Each reviewer reports the location, concrete issue, existing reuse candidate where relevant, and smallest behavior-preserving change. A clean pass is a valid result; do not manufacture findings.

## Apply and verify

Deduplicate findings and inspect the cited code before applying them. Keep only improvements supported by the actual diff. Do not extract a helper merely because two fragments look similar: verify their contracts, callers, and likely reuse. Preserve tests, coverage gates, provenance, and public behavior. This review complements deterministic duplication guards; it does not replace or disable them.

The parent owns all edits. Respect other contributors' changes and do not revert unrelated work. Review-only requests produce findings without edits. Skip speculative performance claims, broad refactors, and changes requiring a new product or architectural decision. Surface correctness bugs separately to the caller; do not quietly turn a cleanup into a behavior change.

Run the repository's relevant checks for the edited slice. If a cleanup fails verification, stop and report the failing check and exact cleanup diff; do not ship it or discard other work. When invoked by ship, return the result to ship for its verification and commit rules. Otherwise do not commit or publish unless separately authorized.

Report which passes ran, changes applied or reasons for skipping findings, verification results, and any limitations. If no justified cleanup exists, say so and leave the code unchanged.
