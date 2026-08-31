---
name: codify-guard
description: Turn a regression that already happened into a permanent, deterministic guard wired into the repo's lint, pre-commit, and CI. Works out which kind of guard the failure needs, whether the class is mechanizable at all, writes the checker and a test proving it catches the original failure, and registers it everywhere the repo expects. Use right after fixing a bug, during a post-mortem or QA finding, or any time you think a rule could have prevented what you just saw.
metadata:
  short-description: Fossilize an incident into a CI guard
---

# Codify a Guard

An incident just happened. This turns it into a check that makes the whole
*class* unrepresentable, wired into the repo's existing enforcement, with a
test proving it catches the original failure.

**Invoke it half-formed.** "Something about templates claiming things the code
doesn't do" is enough. Working out which kind of guard this needs, whether it
is mechanizable, and what its exact shape is, is this skill's job, not a
prerequisite for calling it. The reason guards drift away is that they feel
expensive at the moment of noticing. Noticing should be the only work.

## The one rule that decides everything

**A guard must come from a real incident.** Not a hypothetical, not a code
smell, not "this could go wrong." Good guards are fossilized incidents, almost
never produced by brainstorming, because the failures that actually happen are
more specific and stranger than the ones anyone imagines.

Mature repos state this themselves. If the repo has a discipline or code-quality
doc, expect to find a governing rule of the form *"every rule traces to a
specific past failure; rules without a failure behind them become noise, and
noise trains people to bypass the whole system."* **That doc is the source of
truth and outranks this skill.** Find it before writing anything.

If you cannot name the incident, an issue number, a commit, a QA finding, a
review comment, or something that just bit you in this session, **stop and do
not write a guard.** Say so plainly. A speculative guard costs CI time forever
and catches nothing.

## Step 1 — establish the incident and the class

Get four facts. Ask the user only for what you genuinely cannot recover from
git history, the issue tracker, or the session.

1. **The instance.** What concretely broke, in one sentence.
2. **The evidence.** Issue number, commit SHA, failing output, or the finding.
3. **The class.** The general shape. "This template's copy contradicts the
   code" generalizes. "This specific sentence is wrong" does not.
4. **Why nothing caught it.** If an existing check *should* have, the right
   move is usually to fix that check, not add a rival beside it.

State the class back in one sentence and confirm it before writing code.
Getting the class wrong produces a guard that is either useless or unbearable.

## Step 2 — pick the kind of guard

**This is the step most often skipped, and skipping it is why guards end up
weak.** A failure that needs a runtime guard cannot be caught by a static one,
and reaching for the familiar kind produces a check that passes while the bug
recurs. Three kinds, in rough order of cost:

### Static checkers (AST or bounded text)

A property of the source, decidable without running anything. Plain stdlib
`ast` is usually enough; do not reach for a framework.

Fits: banned calls in a directory, required decorator arguments, import
boundaries, naming and structure conventions, confinement of a constant to one
module, file size, duplication, a symbol with no caller.

Three shapes, and picking the wrong one is the usual defect:

- **Per-file** — the property is local to one file. Takes paths; pre-commit
  passes filenames.
- **Whole-tree** — the property is of the tree or a graph across it (an import
  graph, "exactly one of these exists", a registry matching its consumers).
  Takes no paths. **Must refuse to pass on an empty scan**, or it silently
  succeeds when its own file matching breaks.
- **Diff-scoped** — the tree already violates the rule and only newly added or
  modified lines should fail. Needs the merge base and the changed line
  numbers.

### Runtime guards

An assertion that fires during execution, in dev and test, catching what static
analysis provably cannot: violations **at any call depth**, through dynamic
dispatch, behind framework indirection.

Fits: no network I/O while a transaction is open, no I/O while holding a lock,
no request-time content rebuilds, statement or duration budgets.

Shape: track state where it actually lives (a `ContextVar`, a session event
hook, a client wrapper), check it at the boundary that must not be crossed, and
**raise in dev and test but log with a stack in production** so latent paths
surface without breaking users. A runtime guard is itself unit-testable —
assert it fires for a deliberately nested call.

Reach for this when the failure was about *when* or *inside what* something
happened, rather than what the source says. Static analysis cannot see call
depth, so a static check for this class is theatre.

### Structural contracts

A property of how the system is assembled, expressed as a test or a
declarative contract file rather than a bespoke script.

Fits: import contracts (layer A may not import layer B), golden-number parity
between two implementations, query-count budgets, and **reflective tests that
enumerate registrations** — every route has a permission, every registered job
has an index, every enum member is handled. That last shape is the highest
-value and most overlooked: it catches the thing a hand-maintained list always
eventually gets wrong.

Prefer a native tool's own ratchet (a linter's per-file ignores, an
import-linter contract) over a homegrown script wrapping it. Native ratchets
are greppable and already understood.

## Step 3 — confirm it is mechanizable at all

Be honest. This is where the skill earns its keep.

Some classes are genuinely not lintable, and repos that document their
discipline usually say so explicitly. The recurring list: **freshness or
correctness semantics** better encoded as a type than pattern-matched;
**"is this the right abstraction"**; **cohesion**, where line count is a proxy
and a 400-line file doing three unrelated things is worse than a 700-line
cohesive one; and **architectural intent**, which no checker will notice.

Whether a paraphrase of an external rule is faithful to its source is the same
kind of judgment. For that class there is a middle path worth taking: you
cannot check whether prose is faithful, but you can require it to carry a
marker naming a test that pins the property, and fail when the marker names
nothing. **Convert the unverifiable into the checkable, and say plainly that
the guard checks the marker, not the meaning.**

Two refusals, both load-bearing:

- **Never soften a "not mechanizable" verdict into a weak regex.** A guard that
  cannot fail is worse than nothing: it advertises protection that is not there.
- **Never put LLM judgment in the gate.** A nondeterministic check erodes trust
  in every other check, which is worse than having no guard.

Lint is a floor, not a ceiling. It stops known failures from silently recurring
under deadline pressure; it does not produce good design. Say so when that is
the honest answer.

## Step 4 — learn how this repo already does it

Do not invent scaffolding.

- **Read two or three existing guards closely.** Find where they live
  (`scripts/check_*`, `tools/lint_*`, or whatever this repo names them).
- **Find the shared runner.** Mature repos factor argv parsing, reporting, and
  exit codes into one module, often with the per-file / whole-tree /
  diff-scoped split already documented. Use it rather than forking a fourth
  variant.
- **Find the escape-hatch convention** (Step 5). It will already exist.
- **List the registration points explicitly before editing.** Typically the
  checker, its test, a pre-commit config, a task-runner target, and a CI step.
  A guard registered in four of five places is the worst outcome: it passes
  locally and fails in CI, or the reverse.
- **Read `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, and any discipline doc.**
  **Repo conventions win over anything in this skill.**

**Structure the checker for testability.** Expose a pure function taking source
*text* and returning violations, so tests exercise the rule without touching
the filesystem.

## Step 5 — give it the right escape hatch

**A rule with no way out gets bypassed wholesale the first time it is wrong.**
Every guard needs an exit, and which one you choose is a real design decision.
Use the repo's existing convention rather than inventing a parallel one.

- **Waiver marker** — an inline comment silencing one site, with a
  **mandatory reason**. A bare marker must not count: the point is that
  exceptions are visible and argued in review rather than silently
  accumulated. Repos with several guards usually centralize this syntax in one
  module so checkers cannot fork it.
- **Ratchet against a committed baseline** — for a property the tree already
  violates broadly. The baseline may shrink, never grow. Use when you want
  steady pressure rather than a cliff.
- **Shrink-only allowlist** — for a small, enumerable set of known exceptions.
  Document that it may shrink but never grow, and prefer it to a ratchet when
  the exceptions are few and each deserves a name.
- **Diff-scoping** — no escape hatch at all, because only new lines are judged.
- **Split enforcement** — warn locally, enforce in CI. Good for rules that
  should shape behaviour without blocking a work-in-progress commit.

A guard that fails on arrival with no hatch gets waived wholesale, and a waived
guard is dead. Choose deliberately.

## Step 6 — the admission bar

All five. If one cannot be met, report which and stop.

1. **Provenance.** The checker's own docstring names the incident with its
   issue number or SHA, and states the class in one sentence. Someone reading
   it in a year must be able to tell whether it still matters.
2. **Proof-of-catch.** A test reproducing the original failure, asserting the
   guard fires. Make it the first test and say so in its docstring. Follow it
   with the near-misses that must stay silent, which is what stops the guard
   becoming unbearable later.
3. **Green on arrival.** Zero violations, or a documented hatch from Step 5.
4. **Bounded cost.** Measure the runtime. Put whole-repo scans wherever the
   repo runs once-per-build checks, never inside a per-shard test job.
5. **A retirement condition.** One line: what would make this guard obsolete.
   Guards that outlive their class become noise nobody can safely delete.

**Do not ship a guard that fails the bar.** The bar is what keeps a suite of
checks trustworthy instead of a pile people route around.

## Step 7 — prove it is non-vacuous

A guard nobody has watched fail is decoration. The unit test is necessary but
not sufficient, because it can pass while the wiring is wrong.

1. Introduce a real violation in a real file the guard is meant to police.
2. Run the checker **exactly as CI invokes it**. Confirm it fails, and that the
   message names the offending file and line.
3. Revert the violation. Confirm it passes.
4. **Verify the revert actually landed** before trusting step 3.

Step 4 is not paranoia. A probe that silently fails to modify the file produces
a pass that means nothing and looks exactly like success.

For a whole-tree checker, also confirm it **fails rather than passes on an
empty scan**.

## Step 8 — wire it in, everywhere

Register at every point Step 4 identified. Set file triggers to include the
checker script itself, so editing the rule re-runs it. Then run the repo's own
lint, type, and test commands, not just the new guard's test.

## Step 9 — ship it

One guard per change, independently revertible. State in the description: the
incident, the class, which kind of guard and why, the escape hatch, the
non-vacuity probe result, and the retirement condition. Link the issue.

## Anti-patterns

- **Skipping Step 2.** Reaching for a static checker because it is familiar,
  when the failure was about call depth or timing and needs a runtime guard.
- **Guarding the instance, not the class.** Banning one wrong sentence instead
  of requiring claims to be pinned.
- **A guard that cannot fail.** Always probe, and verify the probe landed.
  A whole-tree checker that passes on an empty scan is the common case.
- **No escape hatch, or a bare one.** A waiver without a mandatory reason
  accumulates silently and teaches people the rule is optional.
- **A guard that fails on arrival.** It will be waived, then ignored.
- **LLM judgment in the gate.** Propose with a model, decide with a script.
- **Partial registration.** Local and CI must agree.
- **Scope creep.** One incident, one class, one guard.
