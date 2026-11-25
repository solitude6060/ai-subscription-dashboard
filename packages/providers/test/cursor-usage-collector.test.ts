import { describe, expect, test } from "bun:test";
import type { UsageRecord } from "../../core/src/types";
import { CursorUsageCollector } from "../src/providers/structured-usage";

const event = (timestamp: string, totalTokens: number) => ({
  timestamp: String(Date.parse(timestamp)),
  model: "composer-2",
  chargedCents: 1,
  tokenUsage: { totalTokens },
});

function request(start: string, end: string, page = 1, pageSize = 1000): string {
  return JSON.stringify({ startDate: String(Date.parse(start)), endDate: String(Date.parse(end)), page, pageSize });
}

function page(events: unknown[], total?: number): string {
  return JSON.stringify(total === undefined
    ? { usageEventsDisplay: events }
    : { totalUsageEventsCount: total, usageEventsDisplay: events });
}

function summary(records: UsageRecord[]) {
  return records
    .map((record) => [record.endedAt === undefined ? "day" : "hour", record.startedAt, record.totalTokens])
    .sort((left, right) => String(left[1]).localeCompare(String(right[1])) || String(left[0]).localeCompare(String(right[0])));
}

describe("CursorUsageCollector per query", () => {
  test("emits no record for the day or hours before a query start inside a day", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([
      event("2026-11-16T05:10:00.000Z", 100),
      event("2026-11-16T09:10:00.000Z", 20),
      event("2026-11-17T01:10:00.000Z", 3),
    ], 3), request("2026-11-16T07:30:00.000Z", "2026-11-17T12:00:00.000Z"));

    expect(summary(collector.records("cursor"))).toEqual([
      ["hour", "2026-11-16T09:00:00.000Z", 20],
      ["day", "2026-11-17T00:00:00.000Z", 3],
      ["hour", "2026-11-17T01:00:00.000Z", 3],
    ]);
  });

  test("keeps the day and its first hour when the query starts exactly at 00:00 UTC", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T00:10:00.000Z", 3)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));

    expect(summary(collector.records("cursor"))).toEqual([
      ["day", "2026-11-17T00:00:00.000Z", 3],
      ["hour", "2026-11-17T00:00:00.000Z", 3],
    ]);
  });

  test("emits nothing for a query that returns more events than its total", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T01:10:00.000Z", 3), event("2026-11-17T01:20:00.000Z", 3)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));

    expect(collector.records("cursor")).toEqual([]);
  });

  test("tracks completeness per query", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T01:10:00.000Z", 3)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));
    collector.capture(200, page([event("2026-11-18T01:10:00.000Z", 5)], 3),
      request("2026-11-18T00:00:00.000Z", "2026-11-18T23:59:59.999Z"));

    expect(summary(collector.records("cursor"))).toEqual([
      ["day", "2026-11-17T00:00:00.000Z", 3],
      ["hour", "2026-11-17T01:00:00.000Z", 3],
    ]);
  });

  test("keeps a complete query when another query fails", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T01:10:00.000Z", 3)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));
    collector.capture(500, "{}", request("2026-11-18T00:00:00.000Z", "2026-11-18T23:59:59.999Z"));

    expect(summary(collector.records("cursor"))).toEqual([
      ["day", "2026-11-17T00:00:00.000Z", 3],
      ["hour", "2026-11-17T01:00:00.000Z", 3],
    ]);
  });

  test("emits nothing for a query whose total changes between pages", () => {
    const collector = new CursorUsageCollector();
    const start = "2026-11-17T00:00:00.000Z";
    const end = "2026-11-17T23:59:59.999Z";
    collector.capture(200, page([event("2026-11-17T03:00:00.000Z", 1), event("2026-11-17T02:00:00.000Z", 1)], 3),
      request(start, end, 1, 2));
    collector.capture(200, page([event("2026-11-17T02:00:00.000Z", 1), event("2026-11-17T01:00:00.000Z", 1)], 4),
      request(start, end, 2, 2));

    expect(collector.records("cursor")).toEqual([]);
  });

  test("without a total, a page shorter than the request page size completes the query", () => {
    const collector = new CursorUsageCollector();
    const events = Array.from({ length: 500 }, () => event("2026-11-17T01:10:00.000Z", 1));
    collector.capture(200, page(events), request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));

    expect(summary(collector.records("cursor"))).toEqual([
      ["day", "2026-11-17T00:00:00.000Z", 500],
      ["hour", "2026-11-17T01:00:00.000Z", 500],
    ]);
  });
});
