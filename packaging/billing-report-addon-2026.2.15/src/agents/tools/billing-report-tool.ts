import { Type } from "@sinclair/typebox";
import type { OpenClawConfig } from "../../config/config.js";
import { loadConfig } from "../../config/config.js";
import type { AnyAgentTool } from "./common.js";
import { loadCostUsageSummary } from "../../infra/session-cost-usage.js";
import { formatTokenCount, formatUsd } from "../../utils/usage-format.js";

const BillingReportToolSchema = Type.Object({
  startDate: Type.Optional(Type.String()),
  endDate: Type.Optional(Type.String()),
  days: Type.Optional(Type.Number()),
});

function parseDateToMs(raw: string): number | undefined {
  const trimmed = raw.trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(trimmed);
  if (!match) {
    return undefined;
  }
  const [, year, month, day] = match;
  const ms = Date.UTC(parseInt(year, 10), parseInt(month, 10) - 1, parseInt(day, 10));
  return Number.isNaN(ms) ? undefined : ms;
}

function parseDateRange(params: {
  startDate?: string;
  endDate?: string;
  days?: number;
}): { startMs: number; endMs: number } {
  const now = new Date();
  const todayStartMs = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const todayEndMs = todayStartMs + 24 * 60 * 60 * 1000 - 1;

  const startMs = params.startDate ? parseDateToMs(params.startDate) : undefined;
  const endMs = params.endDate ? parseDateToMs(params.endDate) : undefined;

  if (startMs !== undefined && endMs !== undefined) {
    return { startMs, endMs: endMs + 24 * 60 * 60 * 1000 - 1 };
  }

  const days = params.days;
  if (typeof days === "number" && Number.isFinite(days)) {
    const clampedDays = Math.max(1, Math.floor(days));
    const start = todayStartMs - (clampedDays - 1) * 24 * 60 * 60 * 1000;
    return { startMs: start, endMs: todayEndMs };
  }

  return { startMs: todayStartMs, endMs: todayEndMs };
}

export function createBillingReportTool(opts?: { config?: OpenClawConfig }): AnyAgentTool {
  return {
    label: "Billing report",
    name: "get_billing_report",
    description:
      "Return usage cost and token summary for a date range. Use for end-of-day billing, daily cost report, or 'what did I spend?' Default: today only. Optional: startDate/endDate (YYYY-MM-DD) or days (last N days).",
    parameters: BillingReportToolSchema,
    execute: async (_toolCallId, args) => {
      const params = args as Record<string, unknown>;
      const startDate = typeof params.startDate === "string" ? params.startDate : undefined;
      const endDate = typeof params.endDate === "string" ? params.endDate : undefined;
      const days =
        typeof params.days === "number" && Number.isFinite(params.days) ? params.days : undefined;

      const { startMs, endMs } = parseDateRange({ startDate, endDate, days });
      const cfg = opts?.config ?? loadConfig();
      const summary = await loadCostUsageSummary({ startMs, endMs, config: cfg });

      const lines: string[] = [];
      if (summary.daily.length === 0) {
        lines.push("No usage in this period.");
      } else {
        for (const day of summary.daily) {
          const costStr = formatUsd(day.totalCost) ?? "n/a";
          const tokenStr = formatTokenCount(day.totalTokens);
          const partial = day.missingCostEntries > 0 ? " (partial)" : "";
          lines.push(`${day.date}: ${costStr}${partial} · ${tokenStr} tokens`);
        }
        const totalCostStr = formatUsd(summary.totals.totalCost) ?? "n/a";
        const totalTokenStr = formatTokenCount(summary.totals.totalTokens);
        const totalPartial = summary.totals.missingCostEntries > 0 ? " (partial)" : "";
        lines.push(`Total: ${totalCostStr}${totalPartial} · ${totalTokenStr} tokens`);
      }

      const reportText = lines.join("\n");
      return {
        content: [{ type: "text", text: reportText }],
        details: {
          ok: true,
          startMs,
          endMs,
          days: summary.days,
          totals: summary.totals,
          daily: summary.daily,
        },
      };
    },
  };
}
