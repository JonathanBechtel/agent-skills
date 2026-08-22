---
name: create-product-pitch
description: Generate a 1-page product pitch - problem, audience, hypothesis, core user flow, headline features, scope boundaries, success signal - from a feature idea or an existing tech spec. Produces the why context that create-qa-checklist and create-project need but tech specs rarely cover. Use when asked for a product pitch, to frame a feature before speccing it, or to start the orchestrator skill chain.
---

# Create Product Pitch

Generate a 1-page product pitch (Shape Up "pitch" tradition, not a full PRD) for a feature, before any tech spec or ticket work. The pitch is the **why** — target user, success signal, scope rationale, headline features. Downstream skills consume it to anchor their judgment calls about scope and coverage.

**Usage:** `/create-product-pitch <topic-or-spec-file> [--out DIR] [--feature NAME]`

**Default output:** `docs/plans/<feature-slug>-pitch.md`

## Core Principle

A pitch sells the feature in one page. It answers: who is this for, what pain does it remove, what does success look like, what is the headline user value (the "advertisables"), and what are we explicitly NOT doing (and why).

If you can't make a section concrete, push back on the user before generating filler. A vague pitch produces a vague tech spec produces vague tickets.

## Step 1 — Parse Arguments and Source Context

Extract:
- First positional: a topic phrase OR a path to an existing tech spec markdown file
- `--out` output directory, default `docs/plans`
- `--feature` feature slug

If the positional is a file path:
- Read the file
- Extract whatever product context is already there (`## Overview`, `## Goals`, `## Non-goals` style sections)
- Note gaps the pitch needs to fill

If the positional is a topic phrase:
- Use it as the working title
- The user will need to fill in the substantive sections; emit a skeleton with clear placeholders and surface gaps in the Step 5 summary

If `docs/plans/ai-orchestrator-ticket-spec.md` exists, read it for repo-specific product context references (e.g. positioning files, target user notes).

If product-context files exist in the repo (e.g. `BUSINESS_MODELS.md`, `docs/positioning*.md`, `docs/competitor*.md`, `docs/*roadmap*.md`), read them briefly — they typically constrain the success signal, audience, and competitive sections.

## Step 2 — Probe for Specificity

Before writing the file, decide whether you have enough information for a USEFUL pitch. If any of these answers are vague or missing, ask the user before generating:

1. **Who specifically is the target user?** ("our users" doesn't count — push to persona / segment / use case.)
2. **What measurable behavior change defines success?** ("more engagement" doesn't count — push to a metric, signal, or observable user behavior.)
3. **What is one thing you are explicitly NOT doing and why?**

If the user can't answer any of these concretely, the feature isn't ready for a pitch yet. Surface this and stop, rather than producing filler.

## Step 3 — Write the Pitch

Write `<feature-slug>-pitch.md` using this structure. Each section is short — no more than one paragraph (or one bullet list). If you find yourself writing more, you're drifting into the tech spec.

```markdown
# <Feature Name> — Product Pitch

> One-line elevator description. What the feature is and who it's for, in plain language.

**Tech spec:** `docs/<spec-name>.md` _(or `_to be written_` if the pitch precedes the spec)_

## Problem

[1-2 sentences. What user pain or business gap this addresses. Concrete enough that a stranger reads it and immediately gets why this matters.]

## Audience

- **Primary:** [Persona or segment. Be specific — "draft-curious NBA fans who already follow scouting Twitter" beats "basketball fans".]
- **Secondary** (optional): [Adjacent personas who also benefit.]

## Hypothesis

If we ship this, then **[observable user behavior]** will change because **[mechanism]**.

Example: "If we ship the consensus board as the homepage hero, then repeat visits during draft season will increase because users now have a single canonical answer to 'where is X ranked right now?' that updates faster than any individual source."

## Core User Flow

The primary happy path through the feature. 3-7 numbered steps, each from the user's POV (not the system's).

1. User [does X]
2. User sees [Y]
3. User [interacts]
4. User leaves with [outcome]

## Headline Features (Advertisables)

3-5 bullets that could appear on a marketing page, in a tweet, or in a release announcement. Each must:

- Describe observable user value, not internal architecture.
- Be falsifiable — you can point at the shipped feature and say yes or no.
- Be a thing the user (not the developer) cares about.

Good: "See every analyst's rank for a single player on one screen."
Bad: "Standardized consensus aggregation service with O(n log n) ranking."

- [Headline feature 1]
- [Headline feature 2]
- ...

## Scope Boundaries

What we are **explicitly NOT doing** in this work, and **why**. The "why" matters more than the "what" — it lets future agents (and future you) distinguish scope creep from legitimate extension.

- **Not doing:** [Thing]
  - **Why:** [Reason — usually one of: deferred to a later project, intentionally minimal first cut, out of business scope, dependency would block]

## Success Signal

One or two observable signals that say "this worked." Prefer signals measurable with what the project will actually ship — don't depend on instrumentation that isn't in scope.

- **Primary:** [Metric or behavior]
- **Secondary** (optional): [Metric or behavior]

## Competitive / Context

(Optional.) Links to competitor analysis, positioning notes, or business-model docs that constrain or motivate this work.

- [Link or reference]
```

Field-by-field rules:

- **No internal architecture language** in any section. Words like "service," "endpoint," "migration," "schema," "API" belong in the tech spec, not here.
- **Hypothesis must be falsifiable.** "Users will love it" is not a hypothesis; "users will return within 7 days more often" is.
- **Headline Features and Core User Flow must be reconcilable.** Each headline feature should appear, implicitly or explicitly, in the user flow. If a headline feature doesn't show up in the flow, ask whether it actually matters to the user.
- **Scope Boundaries should be opinionated.** A pitch with no "we're not doing X" section is too vague — every real feature has natural extensions you're choosing to defer.

## Step 4 — Summarize

Report to the user:

- Pitch path
- Any sections that came out underspecified or filler-y (so the user can tighten them before downstream skills propagate the vagueness)
- Recommended next step:
  - If no tech spec exists yet: write the tech spec, using this pitch as the anchor for "what to build."
  - If a tech spec already exists: run `/create-qa-checklist <spec-file>` next, then `/create-project`.

Do not create tickets, write code, or run orchestration from this skill. The pitch is consumed by downstream skills, not by execution agents directly.
