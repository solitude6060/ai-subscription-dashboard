import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteStorage } from "../src/index";
import type { UsageRecord } from "../../core/src/types";

let dataDir: string;
let previousDataDir: string | undefined;

beforeEach(() => {
  previousDataDir = process.env.OPENUSAGE_WEBUI_DIR;
  dataDir = mkdtempSync(join(tmpdir(), "openusage-webui-test-"));
  process.env.OPENUSAGE_WEBUI_DIR = dataDir;
});

afterEach(() => {
  if (previousDataDir === undefined) delete process.env.OPENUSAGE_WEBUI_DIR;
  else process.env.OPENUSAGE_WEBUI_DIR = previousDataDir;
  rmSync(dataDir, { recursive: true, force: true });
});

const HOUR = 3600000;

function daily(overrides: Partial<UsageRecord> & Pick<UsageRecord, "id" | "providerId" | "tool" | "source">): UsageRecord {
  return { model: "model", totalTokens: 100, startedAt: "2026-10-09T00:00:00.000Z", ...overrides };
}

function hourly(
  overrides: Partial<UsageRecord> & Pick<UsageRecord, "id" | "providerId" | "tool" | "source" | "startedAt">,
): UsageRecord {
  return {
    model: "model",
    totalTokens: 10,
    endedAt: new Date(Date.parse(overrides.startedAt) + HOUR).toISOString(),
    ...overrides,
  };
}

const DAILY_BATCH: UsageRecord[] = [
  daily({ id: "d-claude", providerId: "claude-code", tool: "ccusage", source: "local-log", totalTokens: 300 }),
  daily({ id: "d-cursor", providerId: "cursor", tool: "Cursor Usage Event", source: "api", totalTokens: 60 }),
  daily({ id: "d-grok", providerId: "grok", tool: "Grok Session", source: "local-log", totalTokens: 70 }),
];

const HOURLY_BATCH: UsageRecord[] = [
  // Starts on the same instant as the daily Cursor row, so it must not enter the replaceScopes delete.
  hourly({ id: "h-cursor-0", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-09T00:00:00.000Z", totalTokens: 25, costUsd: 0.5 }),
  hourly({ id: "h-cursor-5", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-09T05:00:00.000Z", totalTokens: 35 }),
  hourly({ id: "h-claude-3", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-09T03:00:00.000Z", model: "All Models", totalTokens: 300 }),
];

async function snapshot(storage: SqliteStorage) {
  const records = (await storage.listUsageRecords({ limit: 1000 }))
    .map(({ createdAt: _createdAt, ...rest }) => rest)
    .sort((left, right) => left.id.localeCompare(right.id));
  return {
    records,
    summary: await storage.getUsageSummary(),
    breakdown: await storage.getTokenUsageBreakdown(),
    positive: await storage.listPositiveTokenRows("2026-10-01T00:00:00.000Z"),
  };
}

describe("token_hourly storage", () => {
  test("hourly records stay out of usage_records and every other reader", async () => {
    const plain = new SqliteStorage(join(dataDir, "plain.sqlite"));
    const mixed = new SqliteStorage(join(dataDir, "mixed.sqlite"));
    await plain.init();
    await mixed.init();
    await plain.upsertUsageRecords(DAILY_BATCH, { replaceScopes: true });
    await mixed.upsertUsageRecords([...DAILY_BATCH, ...HOURLY_BATCH], { replaceScopes: true });

    expect(await snapshot(mixed)).toEqual(await snapshot(plain));

    plain.close();
    mixed.close();
    const db = new Database(join(dataDir, "mixed.sqlite"), { readonly: true });
    const rows = db
      .query("SELECT provider_id, tool, hour_start, model, total_tokens, cost_usd FROM token_hourly ORDER BY provider_id, hour_start")
      .all();
    db.close();
    expect(rows).toEqual([
      { provider_id: "claude-code", tool: "ccusage", hour_start: "2026-10-09T03:00:00.000Z", model: "All Models", total_tokens: 300, cost_usd: null },
      { provider_id: "cursor", tool: "Cursor Usage Event", hour_start: "2026-10-09T00:00:00.000Z", model: "model", total_tokens: 25, cost_usd: 0.5 },
      { provider_id: "cursor", tool: "Cursor Usage Event", hour_start: "2026-10-09T05:00:00.000Z", model: "model", total_tokens: 35, cost_usd: null },
    ]);
  });

  test("a later batch overwrites the same hour instead of adding a row", async () => {
    const storage = new SqliteStorage(join(dataDir, "hourly.sqlite"));
    await storage.init();
    await storage.upsertUsageRecords([HOURLY_BATCH[1]!]);
    await storage.upsertUsageRecords([{ ...HOURLY_BATCH[1]!, totalTokens: 50 }]);
    storage.close();

    const db = new Database(join(dataDir, "hourly.sqlite"), { readonly: true });
    const rows = db.query("SELECT total_tokens FROM token_hourly").all();
    db.close();
    expect(rows).toEqual([{ total_tokens: 50 }]);
  });
});

describe("token_hourly rows of a replaced day", () => {
  const hourlyRows = (path: string) => {
    const db = new Database(path, { readonly: true });
    const rows = db.query("SELECT provider_id, tool, hour_start, model, total_tokens FROM token_hourly ORDER BY provider_id, tool, hour_start, model").all();
    db.close();
    return rows;
  };

  test("a replaced closed Cursor day loses the hours and models the batch no longer has", async () => {
    const path = join(dataDir, "replace.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const day = "2026-11-16T00:00:00.000Z";
    const tool = "Cursor Usage Event";
    await storage.upsertUsageRecords([
      daily({ id: "d-old", providerId: "cursor", tool, source: "api", startedAt: day, model: "helios-alpha", totalTokens: 13 }),
      hourly({ id: "h-old-0", providerId: "cursor", tool, source: "api", startedAt: day, model: "helios-alpha", totalTokens: 9 }),
      hourly({ id: "h-old-4", providerId: "cursor", tool, source: "api", startedAt: "2026-11-16T04:00:00.000Z", model: "helios-alpha", totalTokens: 4 }),
    ], { replaceScopes: true });
    await storage.upsertUsageRecords([
      daily({ id: "d-new", providerId: "cursor", tool, source: "api", startedAt: day, model: "Other", totalTokens: 9 }),
      hourly({ id: "h-new", providerId: "cursor", tool, source: "api", startedAt: day, model: "Other", totalTokens: 9 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toEqual([
      { provider_id: "cursor", tool, hour_start: day, model: "Other", total_tokens: 9 },
    ]);
  });

  test("keeps Grok hourly rows upsert-only, since a scan can skip an unreadable transcript", async () => {
    const path = join(dataDir, "grok.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const day = "2026-11-16T00:00:00.000Z";
    const tool = "Grok Session";
    await storage.upsertUsageRecords([
      daily({ id: "d-g", providerId: "grok", tool, source: "local-log", startedAt: day, totalTokens: 15 }),
      hourly({ id: "h-g-9", providerId: "grok", tool, source: "local-log", startedAt: "2026-11-16T09:00:00.000Z", totalTokens: 5 }),
      hourly({ id: "h-g-10", providerId: "grok", tool, source: "local-log", startedAt: "2026-11-16T10:00:00.000Z", totalTokens: 10 }),
    ], { replaceScopes: true });
    await storage.upsertUsageRecords([
      daily({ id: "d-g", providerId: "grok", tool, source: "local-log", startedAt: day, totalTokens: 10 }),
      hourly({ id: "h-g-10", providerId: "grok", tool, source: "local-log", startedAt: "2026-11-16T10:00:00.000Z", totalTokens: 10 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toHaveLength(2);
  });

  test("keeps today's Cursor hourly rows upsert-only, since an earlier refresh can commit after a later one", async () => {
    const path = join(dataDir, "today.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const today = `${new Date().toISOString().slice(0, 10)}T00:00:00.000Z`;
    const tool = "Cursor Usage Event";
    await storage.upsertUsageRecords([
      hourly({ id: "h-t-old", providerId: "cursor", tool, source: "api", startedAt: today, model: "helios-alpha", totalTokens: 9 }),
    ]);
    await storage.upsertUsageRecords([
      daily({ id: "d-t", providerId: "cursor", tool, source: "api", startedAt: today, model: "Other", totalTokens: 9 }),
      hourly({ id: "h-t-new", providerId: "cursor", tool, source: "api", startedAt: today, model: "Other", totalTokens: 9 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toHaveLength(2);
  });

  test("does not delete hourly rows for a daily row that does not start at 00:00 UTC", async () => {
    const path = join(dataDir, "not-midnight.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const tool = "Cursor Usage Event";
    await storage.upsertUsageRecords([
      hourly({ id: "h-17", providerId: "cursor", tool, source: "api", startedAt: "2026-11-17T05:00:00.000Z", totalTokens: 5 }),
    ]);
    await storage.upsertUsageRecords([
      daily({ id: "d-930", providerId: "cursor", tool, source: "api", startedAt: "2026-11-16T09:30:00.000Z", totalTokens: 7 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toHaveLength(1);
  });

  test("keeps hourly rows of a day the batch does not replace", async () => {
    const path = join(dataDir, "other-day.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const source = "api";
    const tool = "Cursor Usage Event";
    await storage.upsertUsageRecords([
      hourly({ id: "h-15", providerId: "cursor", tool, source, startedAt: "2026-11-15T23:00:00.000Z", totalTokens: 5 }),
      hourly({ id: "h-17", providerId: "cursor", tool, source, startedAt: "2026-11-17T00:00:00.000Z", totalTokens: 3 }),
    ]);
    await storage.upsertUsageRecords([
      daily({ id: "d-16", providerId: "cursor", tool, source, startedAt: "2026-11-16T00:00:00.000Z", totalTokens: 7 }),
      hourly({ id: "h-16", providerId: "cursor", tool, source, startedAt: "2026-11-16T00:00:00.000Z", totalTokens: 7 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toEqual([
      { provider_id: "cursor", tool, hour_start: "2026-11-15T23:00:00.000Z", model: "model", total_tokens: 5 },
      { provider_id: "cursor", tool, hour_start: "2026-11-16T00:00:00.000Z", model: "model", total_tokens: 7 },
      { provider_id: "cursor", tool, hour_start: "2026-11-17T00:00:00.000Z", model: "model", total_tokens: 3 },
    ]);
  });

  test("keeps hourly rows when the batch has hourly rows but no daily row for that day", async () => {
    const path = join(dataDir, "no-daily.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const tool = "Cursor Usage Event";
    await storage.upsertUsageRecords([
      hourly({ id: "h-05", providerId: "cursor", tool, source: "api", startedAt: "2026-11-16T05:00:00.000Z", totalTokens: 5 }),
    ]);
    await storage.upsertUsageRecords([
      hourly({ id: "h-09", providerId: "cursor", tool, source: "api", startedAt: "2026-11-16T09:00:00.000Z", totalTokens: 9 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toHaveLength(2);
  });

  test("keeps ccusage hourly rows when its daily scope is replaced", async () => {
    const path = join(dataDir, "ccusage.sqlite");
    const storage = new SqliteStorage(path);
    await storage.init();
    const day = "2026-11-16T00:00:00.000Z";
    await storage.upsertUsageRecords([
      hourly({ id: "h-cc", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-11-16T03:00:00.000Z", model: "All Models", totalTokens: 30 }),
    ]);
    await storage.upsertUsageRecords([
      daily({ id: "d-cc", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: day, totalTokens: 40 }),
    ], { replaceScopes: true });
    storage.close();

    expect(hourlyRows(path)).toEqual([
      { provider_id: "claude-code", tool: "ccusage", hour_start: "2026-11-16T03:00:00.000Z", model: "All Models", total_tokens: 30 },
    ]);
  });
});

describe("listAllowanceTokenRows", () => {
  const FROM = "2026-10-01T00:00:00.000Z";

  async function seeded(records: UsageRecord[]) {
    const storage = new SqliteStorage();
    await storage.init();
    await storage.upsertUsageRecords(records, { replaceScopes: true });
    return storage;
  }

  test("a UTC day with hourly rows returns only those rows, a day without keeps its daily row", async () => {
    const storage = await seeded([
      daily({ id: "d-9", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-09T00:00:00.000Z", totalTokens: 60 }),
      daily({ id: "d-8", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-08T00:00:00.000Z", totalTokens: 40 }),
      hourly({ id: "h-a", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-09T05:00:00.000Z", totalTokens: 25, costUsd: 0.5 }),
      hourly({ id: "h-b", providerId: "cursor", tool: "Cursor Usage Event", source: "api", startedAt: "2026-10-09T23:00:00.000Z", totalTokens: 35 }),
    ]);
    const rows = (await storage.listAllowanceTokenRows(FROM)).sort((l, r) => l.startedAt.localeCompare(r.startedAt));
    storage.close();

    expect(rows).toEqual([
      { providerId: "cursor", model: "model", tokens: 40, costUsd: null, startedAt: "2026-10-08T00:00:00.000Z", bucketEnd: "2026-10-09T00:00:00.000Z" },
      { providerId: "cursor", model: "model", tokens: 25, costUsd: 0.5, startedAt: "2026-10-09T05:00:00.000Z", bucketEnd: "2026-10-09T06:00:00.000Z" },
      { providerId: "cursor", model: "model", tokens: 35, costUsd: null, startedAt: "2026-10-09T23:00:00.000Z", bucketEnd: "2026-10-10T00:00:00.000Z" },
    ]);
  });

  test("hourly rows of one provider or tool do not replace another provider's daily row", async () => {
    const storage = await seeded([
      daily({ id: "d-cursor", providerId: "cursor", tool: "Cursor Usage Event", source: "api", totalTokens: 60 }),
      daily({ id: "d-grok", providerId: "grok", tool: "Grok Session", source: "local-log", totalTokens: 70 }),
      hourly({ id: "h-grok", providerId: "grok", tool: "Grok Session", source: "local-log", startedAt: "2026-10-09T05:00:00.000Z", totalTokens: 70 }),
    ]);
    const rows = await storage.listAllowanceTokenRows(FROM);
    storage.close();

    expect(rows.map((row) => [row.providerId, row.tokens, row.bucketEnd]).sort()).toEqual([
      ["cursor", 60, "2026-10-10T00:00:00.000Z"],
      ["grok", 70, "2026-10-09T06:00:00.000Z"],
    ]);
  });

  test("a ccusage local day pairs with its UTC hours under Asia/Taipei", async () => {
    const previousTz = process.env.TZ;
    process.env.TZ = "Asia/Taipei";
    try {
      expect(new Date(2026, 9, 9).toISOString()).toBe("2026-10-08T16:00:00.000Z");
      const storage = await seeded([
        daily({ id: "d-09", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-09T00:00:00.000Z", totalTokens: 300 }),
        daily({ id: "d-10", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-10T00:00:00.000Z", totalTokens: 90 }),
        // Local 2026-10-09 runs from 16:00Z on the 8th to 15:00Z on the 9th.
        hourly({ id: "h-first", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-08T16:00:00.000Z", model: "All Models", totalTokens: 100 }),
        hourly({ id: "h-last", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-09T15:00:00.000Z", model: "All Models", totalTokens: 200 }),
      ]);
      const rows = (await storage.listAllowanceTokenRows(FROM)).sort((l, r) => l.startedAt.localeCompare(r.startedAt));
      storage.close();

      expect(rows).toEqual([
        { providerId: "claude-code", model: "All Models", tokens: 100, costUsd: null, startedAt: "2026-10-08T16:00:00.000Z", bucketEnd: "2026-10-08T17:00:00.000Z" },
        { providerId: "claude-code", model: "All Models", tokens: 200, costUsd: null, startedAt: "2026-10-09T15:00:00.000Z", bucketEnd: "2026-10-09T16:00:00.000Z" },
        { providerId: "claude-code", model: "model", tokens: 90, costUsd: null, startedAt: "2026-10-09T16:00:00.000Z", bucketEnd: "2026-10-10T16:00:00.000Z" },
      ]);
    } finally {
      process.env.TZ = previousTz ?? "UTC";
    }
  });

  test("Claude hourly rows preserve same-day Pi usage and survive Pi owner cleanup", async () => {
    const previousTz = process.env.TZ;
    process.env.TZ = "Asia/Taipei";
    const storage = await seeded([
      daily({ id: "native", providerId: "claude-code", tool: "ccusage", source: "local-log", totalTokens: 300, costUsd: 2 }),
      daily({ id: "pi", providerId: "claude-code", tool: "Pi Session", source: "local-log", model: "Pi Model", totalTokens: 40, costUsd: 3 }),
      hourly({ id: "native-hour", providerId: "claude-code", tool: "ccusage", source: "local-log", model: "All Models", startedAt: "2026-10-09T05:00:00.000Z", totalTokens: 300, costUsd: 2 }),
    ]);
    try {
      const rows = await storage.listAllowanceTokenRows(FROM);
      expect(rows.reduce((sum, row) => sum + row.tokens, 0)).toBe(340);
      expect(rows.find((row) => row.model === "Pi Model")).toMatchObject({
        startedAt: "2026-10-08T16:00:00.000Z", bucketEnd: "2026-10-09T16:00:00.000Z", tokens: 40,
      });
      expect((await storage.listUsageRecords()).map((row) => row.id).sort()).toEqual(["native", "pi"]);
      expect((await storage.getUsageSummary()).byProvider[0]?.costUsd).toBe(5);
      await storage.upsertUsageRecords([{
        id: "no-pi-owner", providerId: "claude-code", tool: "OpenUsage Plugin Snapshot",
        startedAt: "2026-10-11T00:00:00.000Z", source: "api",
        raw: { piSessionOwnership: { ownerId: null, days: ["2026-10-09T00:00:00.000Z"] } },
      }], { replaceScopes: true });
      expect(await storage.listAllowanceTokenRows(FROM)).toEqual([
        { providerId: "claude-code", model: "All Models", tokens: 300, costUsd: 2,
          startedAt: "2026-10-09T05:00:00.000Z", bucketEnd: "2026-10-09T06:00:00.000Z" },
      ]);
      expect((await storage.listUsageRecords()).some((row) => row.id === "native")).toBe(true);
    } finally {
      storage.close();
      process.env.TZ = previousTz ?? "UTC";
    }
  });

  test("ignores zero-token hourly rows and hours older than the cutoff", async () => {
    const storage = await seeded([
      hourly({ id: "h-zero", providerId: "grok", tool: "Grok Session", source: "local-log", startedAt: "2026-10-09T05:00:00.000Z", totalTokens: 0 }),
      hourly({ id: "h-old", providerId: "grok", tool: "Grok Session", source: "local-log", startedAt: "2026-09-20T05:00:00.000Z", totalTokens: 5 }),
    ]);
    const rows = await storage.listAllowanceTokenRows(FROM);
    storage.close();
    expect(rows).toEqual([]);
  });
});

describe("deleteUsageRecordsForProvider", () => {
  test("removes the provider's hourly rows and keeps other providers' rows", async () => {
    const storage = new SqliteStorage(join(dataDir, "delete.sqlite"));
    await storage.init();
    await storage.upsertUsageRecords([
      hourly({ id: "h-gone", providerId: "claude-code:work", tool: "ccusage", source: "local-log", startedAt: "2026-10-09T03:00:00.000Z", model: "All Models", totalTokens: 300 }),
      hourly({ id: "h-kept", providerId: "claude-code", tool: "ccusage", source: "local-log", startedAt: "2026-10-09T03:00:00.000Z", model: "All Models", totalTokens: 50 }),
    ]);

    await storage.deleteUsageRecordsForProvider("claude-code:work");
    storage.close();

    const db = new Database(join(dataDir, "delete.sqlite"), { readonly: true });
    const rows = db.query("SELECT provider_id FROM token_hourly").all();
    db.close();
    expect(rows).toEqual([{ provider_id: "claude-code" }]);
  });
});
