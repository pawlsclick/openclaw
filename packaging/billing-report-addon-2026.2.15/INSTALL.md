# Billing report addon — install on OpenClaw 2026.2.15

This addon adds the **get_billing_report** tool and **billing-report** skill for end-of-day usage cost reports. Patches are generated against **main** (commit 7f2d56f1d). They should apply cleanly to OpenClaw 2026.2.15 (3fe22ea) or any close tree; if the other instance’s tree differs, use Option B (manual edits).

## Transfer addon to the other instance

Copy the whole addon folder (this directory) to the target machine, e.g.:

```bash
scp -r packaging/billing-report-addon-2026.2.15 user@other-host:/tmp/
# or create a tarball and extract on the other host:
tar -czvf billing-report-addon-2026.2.15.tar.gz -C packaging billing-report-addon-2026.2.15
```

Then on the other instance, run the steps below from the addon directory (e.g. `/tmp/billing-report-addon-2026.2.15`).

## What you need on the other instance

- OpenClaw source tree at 2026.2.15 (e.g. `git clone ... && git checkout 3fe22ea` or the same version from npm source).
- Node 22+, pnpm.

## Option A: Copy files and apply patches

1. **Copy new files** into your OpenClaw repo root (same paths as in this addon):

   ```bash
   # From the addon directory (where INSTALL.md lives):
   REPO=/path/to/your/openclaw/repo

   cp src/agents/tools/billing-report-tool.ts "$REPO/src/agents/tools/"
   mkdir -p "$REPO/skills/billing-report"
   cp skills/billing-report/SKILL.md "$REPO/skills/billing-report/"
   ```

2. **Apply patches** from the `patches/` directory (from repo root):

   ```bash
   cd "$REPO"
   patch -p1 < /path/to/addon/patches/openclaw-tools.patch
   patch -p1 < /path/to/addon/patches/system-prompt.patch
   ```

   If `patch` reports offset or fuzz, apply the edits manually (see INSTALL.md section "Manual edits" below).

3. **Build and restart:**

   ```bash
   pnpm install
   pnpm build
   ```

   Then restart the gateway (restart the OpenClaw app on macOS, or restart the process that runs `openclaw gateway run`).

## Option B: Manual edits (if patches do not apply)

If your tree differs from 2026.2.15, apply these by hand:

**1. `src/agents/openclaw-tools.ts`**

- After the line `import { createAgentsListTool } from "./tools/agents-list-tool.js";` add:
  `import { createBillingReportTool } from "./tools/billing-report-tool.js";`
- In the `tools` array, after `createSessionStatusTool({ ... }),` add:
  `createBillingReportTool({ config: options?.config }),`

**2. `src/agents/system-prompt.ts`**

- In `coreToolSummaries`, after the `session_status` entry add:
  `get_billing_report: "Return usage cost and token summary for a date range; use for end-of-day billing, daily cost report, or 'what did I spend?' Default: today. Optional: startDate/endDate (YYYY-MM-DD) or days",`
- In the `toolOrder` array, after `"session_status"` add:
  `"get_billing_report",`

## Skill-only (no code change)

To get only the **skill** on an instance where you cannot rebuild (e.g. npm-installed binary):

- Copy `skills/billing-report/SKILL.md` to managed skills:
  `mkdir -p ~/.openclaw/skills/billing-report && cp skills/billing-report/SKILL.md ~/.openclaw/skills/billing-report/`
- The **tool** will not be available unless the addon code is installed and the gateway is restarted after a build.

## Verify

After restart, ask the agent: “Give me an end of day billing report” or “What did I spend today?” It should call `get_billing_report` and return today’s cost/token summary.
