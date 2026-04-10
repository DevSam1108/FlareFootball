---
description: Read current project state from source files and diagnostics, then update all memory-bank files and CLAUDE.md to reflect reality.
---

You are updating the Flare Football POC memory bank. Follow every step in order.

> **⚠️ CRITICAL: NEVER run `git commit`, `git push`, `git init`, or any git write commands. This project has NO git repository. It is local-only by explicit developer decision. This rule is ABSOLUTE and has been violated in the past — do NOT repeat.**

---

## Step 1 — Read the Existing Memory Bank + CLAUDE.md

Read all files so you know what was previously recorded and can detect what has changed:

- `CLAUDE.md`
- `memory-bank/activeContext.md`
- `memory-bank/progress.md`
- `memory-bank/systemPatterns.md`
- `memory-bank/techContext.md`
- `memory-bank/productContext.md`
- `memory-bank/projectbrief.md`
- `memory-bank/changelog.md`
- `memory-bank/issueLog.md`
- `memory-bank/decisionLog.md`

---

## Step 2 — Read Key Source Files

Read the following files to understand the current state of the code:

- `lib/main.dart`
- `lib/config/detector_config.dart`
- `lib/screens/live_object_detection/live_object_detection_screen.dart`
- `lib/screens/home/home_screen.dart`
- `pubspec.yaml`
- `ios/Podfile`

---

## Step 3 — Run Diagnostics

Run these commands to understand the current state:

```bash
flutter analyze
flutter test
```

---

## Step 4 — Synthesise What Has Changed

Before writing anything, reason through:

- What is now fully working that wasn't before?
- What new issues, gaps, or regressions have appeared?
- What architectural decisions have been made since the last update?
- What is the most important immediate next step right now?
- Have any new patterns, services, or screens been introduced?
- Have any known issues from the previous memory bank been resolved?
- Have any dependencies changed in pubspec.yaml?
- Have any new files been created or existing files been removed?

---

## Step 5 — Update `memory-bank/activeContext.md`

Rewrite the file to reflect the current state. Always include all of these sections — never remove a section, even if its content hasn't changed:

**Current Focus** — one paragraph on what is actively being worked on right now.

**What Is Fully Working** — bullet list of complete, confirmed-working functionality. Be specific (e.g., "YOLO live camera detection renders on both platforms when model files are present").

**What Is Partially Done / In Progress** — bullet list with code snippets where helpful. If a feature exists but its behaviour is unknown or unconfirmed, say so explicitly.

**Known Gaps** — configuration placeholders, orphaned files, stub implementations, stale tests. Each gap should state what it affects and whether it blocks detection.

**Model Files: Developer Machine Setup Required** — keep this section verbatim unless the setup process has genuinely changed.

**Active Environment Variable** — keep the `flutter run` commands verbatim.

**Immediate Next Steps** — 3 to 5 numbered, concrete actions. Each should be something a developer could act on in the next session.

---

## Step 6 — Update `memory-bank/progress.md`

Rewrite the file to reflect current progress. Always include all of these sections:

**What Has Been Built and Works** — grouped by area. Use ✅ for each confirmed working item. Add or remove items as reality dictates.

**What Is Incomplete or Needs Decisions** — one subsection per open item. Use status markers:
- ⚠️ Needs clarification or decision
- 🔑 Config/key missing
- 📝 Copy or content placeholder
- 🗑️ Dead code or orphaned file
- ⚙️ Stub or unimplemented feature
- 🧪 Stale or broken test

For each item include: current status, what the blocker is, and what resolution looks like.

**Decisions Made** — table with Decision and Rationale columns. Add any new decisions made since the last update. Do not remove existing decisions.

**POC Evaluation Checklist** — table tracking the core research questions. Use ✅ (confirmed), ⏳ (to be evaluated), or ❓ (unknown/blocked). Update any items whose status has changed.

---

## Step 7 — Update `memory-bank/systemPatterns.md` (only if architecture changed)

Only rewrite this file if you detected actual architectural changes: a new pattern introduced, a new data flow, a new screen, a change to how an existing system works, or removal of a pattern.

If nothing architectural changed, leave the file untouched.

If it did change, update only the affected sections. Preserve all unchanged sections verbatim.

---

## Step 8 — Update `memory-bank/techContext.md` (only if tech stack changed)

Only update this file if dependencies, platform configurations, build commands, or dev environment details have changed.

If nothing changed, leave the file untouched.

---

## Step 9 — Update `memory-bank/productContext.md` (only if product context changed)

Only update this file if UI structure, user experience goals, product decisions, or scope changed.

If nothing changed, leave the file untouched.

---

## Step 10 — Update `memory-bank/projectbrief.md` (only if project scope changed)

Only update this file if the project's purpose, scope, success criteria, or status changed.

If nothing changed, leave the file untouched.

---

## Step 11 — Update `memory-bank/changelog.md`

Add a new entry at the top (below the header and warning) for the current session if any code changes were made. Include:

- Date
- Summary (one paragraph)
- Changes (bullet list)
- Verification (flutter analyze + flutter test results)

If no code changes were made this session, leave the file untouched.

---

## Step 12 — Update `memory-bank/issueLog.md`

Add new entries if any bugs were discovered, investigated, or fixed during this session. Each entry should include:

- Issue ID (increment from last)
- Title
- Root cause
- Solution that worked
- Verified status

If no new issues were encountered, leave the file untouched.

---

## Step 13 — Update `memory-bank/decisionLog.md`

Add new ADR entries if any non-trivial technical decisions were made during this session. A "non-trivial decision" is one where:

- Multiple approaches were considered and one was chosen over others
- A technology, package, or pattern was selected
- An architectural or design trade-off was made
- A feature was deliberately deferred or rejected
- A bug fix involved choosing between multiple solutions

Each new entry should follow the existing ADR format:

- **ADR-NNN** (increment from last entry)
- **Date**
- **Context** — what problem was being solved
- **Options Considered** — every alternative evaluated (at least 2)
- **Decision** — what was chosen
- **Rationale** — why this option won
- **Trade-offs Accepted** — what was given up
- **Status** — Accepted / Superseded by ADR-XXX

Place new entries in the appropriate project phase section, or create a new section if work has moved to a new milestone.

If no decisions were made this session, leave the file untouched.

---

## Step 14 — Update `CLAUDE.md`

Review `CLAUDE.md` against the current state of the codebase and update if any of the following changed:

- Tech stack or dependencies
- Key file map (new files added, files removed)
- Architecture rules
- Known issues and technical debt
- "What Never to Touch" items
- Build commands
- Model file setup instructions

If nothing changed, leave the file untouched.

---

## Step 15 — Report What Changed

After all writes are complete, output a concise summary:

- Which files were updated
- For each updated file: what specifically changed (new items added, items resolved, status changes)
- Any gaps or ambiguities you noticed that should be flagged for the next session
