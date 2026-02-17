---
name: billing-report
description: Provide end-of-day or date-range usage cost reports from OpenClaw session logs. Trigger when the user asks for a billing report, daily cost summary, or what they spent.
metadata: { "openclaw": { "emoji": "💸" } }
---

# Billing report

## Overview

Use the **get_billing_report** tool to return usage cost and token totals for a date range. Cost is computed from session transcripts using the model rates in OpenClaw config (`models.providers.<provider>.models[].cost` in openclaw.json).

## When to use

- "Give me an end of day billing report"
- "What did I spend today?"
- "Daily cost summary"
- "Usage cost for this week"
- "How much did we use last 7 days?"

## How to use

1. **Today only (default):** Call `get_billing_report` with no parameters.
2. **Specific date range:** Call with `startDate` and `endDate` (YYYY-MM-DD).
3. **Last N days:** Call with `days` (e.g. `days: 7`).

The tool returns per-day cost and token counts plus a total. Use that text as the basis for your reply.

## Cost source

Rates are defined per model in config under `models.providers.<provider>.models[].cost` (input, output, cacheRead, cacheWrite per million tokens). The same data backs the gateway `usage.cost` API and the `/usage cost` channel command.

## Install (running instance)

- **Tool:** The tool is in core. Rebuild and restart the gateway so the agent loads the new tool: `pnpm build` then restart the OpenClaw app (macOS) or restart the gateway process (e.g. `pkill -9 -f openclaw-gateway; nohup openclaw gateway run ...`).
- **Skill:** Bundled from the repo `skills/` when running from source. To use the skill on a deployed instance, either (1) ensure the repo’s `skills/billing-report/` is in the bundled skills dir (e.g. set `OPENCLAW_BUNDLED_SKILLS_DIR` to that path, or ship a `skills/` next to the binary), or (2) copy `skills/billing-report/SKILL.md` into `~/.openclaw/skills/billing-report/SKILL.md` (managed skills). No separate install step for the skill when running from this repo.
