import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { UsageRecord } from "../../../packages/core/src/types";
import { SqliteStorage } from "../../../packages/storage/src/index";

let dataDir: string;
let previousDataDir: string | undefined;

beforeEach(() => {
  previousDataDir = process.env.OPENUSAGE_WEBUI_DIR;
  dataDir = mkdtempSync(join(tmpdir(), "openusage-webui-cli-status-"));
  process.env.OPENUSAGE_WEBUI_DIR = dataDir;
});

afterEach(() => {
  if (previousDataDir === undefined) delete process.env.OPENUSAGE_WEBUI_DIR;
  else process.env.OPENUSAGE_WEBUI_DIR = previousDataDir;
  rmSync(dataDir, { recursive: true, force: true });
});

function record(id: string, providerId: UsageRecord["providerId"], startedAt: string, raw?: unknown): UsageRecord {
  return {
    id,
    providerId,
    tool: raw ? "OpenUsage Plugin Snapshot" : "codex",
    inputTokens: 0,
    outputTokens: 0,
    cacheCreationTokens: 0,
    cacheReadTokens: 0,
    totalTokens: 0,
    costUsd: 0,
    startedAt,
    source: "cli",
    raw,
  } as UsageRecord;
}

async function runStatus(): Promise<string> {
  const proc = Bun.spawn([process.execPath, join(import.meta.dir, "../src/cli-status.ts")], {
    env: { ...process.env, OPENUSAGE_WEBUI_DIR: dataDir, TZ: "UTC" },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return out.replace(/\x1b\[[0-9;]*m/g, "");
}

test("prints a snapshot that is older than the 100 newest records", async () => {
  const storage = new SqliteStorage();
  await storage.init();
  const newer = Array.from({ length: 101 }, (_, i) =>
    record(`event-${i}`, "codex", new Date(Date.UTC(2026, 10, 25, 3, 0, i)).toISOString()),
  );
  await storage.upsertUsageRecords([
    record("colab-snapshot", "colab", "2026-11-25T02:00:00.000Z", {
      lines: [{ type: "text", label: "Balance", value: "341.98 compute units" }],
    }),
    ...newer,
  ]);
  storage.close();

  const out = await runStatus();

  expect(out).toContain("Google Colab");
  expect(out).toContain("341.98 compute units");
});

test("dates the reading by the last success after a failed refresh", async () => {
  const storage = new SqliteStorage();
  await storage.init();
  await storage.upsertUsageRecords([
    record("colab-snapshot", "colab", "2026-11-25T02:00:00.000Z", {
      lines: [{ type: "text", label: "Balance", value: "341.98 compute units" }],
    }),
  ]);
  const status = { providerId: "colab" as const, name: "Google Colab", enabled: true, detected: true };
  await storage.upsertProviderStatus({ ...status, lastRefreshAt: "2026-11-25T02:00:00.000Z" });
  await storage.upsertProviderStatus({ ...status, lastRefreshAt: "2026-11-25T03:00:00.000Z", lastError: "failed" });
  storage.close();

  const out = await runStatus();

  // A 24-hour locale prints 02:00:00.
  expect(out).toMatch(/Updated .*\b0?2:00:00/);
  expect(out).not.toContain("3:00:00");
});

test("prints no update time when the only refresh failed", async () => {
  const storage = new SqliteStorage();
  await storage.init();
  await storage.upsertUsageRecords([
    record("colab-snapshot", "colab", "2026-11-25T02:00:00.000Z", {
      lines: [{ type: "text", label: "Balance", value: "341.98 compute units" }],
    }),
  ]);
  await storage.upsertProviderStatus({
    providerId: "colab", name: "Google Colab", enabled: true, detected: true,
    lastRefreshAt: "2026-11-25T03:00:00.000Z", lastError: "failed",
  });
  storage.close();

  const out = await runStatus();

  expect(out).toContain("341.98 compute units");
  expect(out).not.toContain("Updated");
});
