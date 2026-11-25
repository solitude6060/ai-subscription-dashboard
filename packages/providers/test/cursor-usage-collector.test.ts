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
      event("2026-11-16T07:45:00.000Z", 100),
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

describe("CursorUsageCollector complete days", () => {
  const dailyFlags = (records: UsageRecord[]) => records
    .filter((record) => record.endedAt === undefined)
    .map((record) => [record.startedAt, record.completeDay === true])
    .sort((left, right) => String(left[0]).localeCompare(String(right[0])));

  test("marks each daily row whose query covers its whole UTC day", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-16T05:00:00.000Z", 1), event("2026-11-17T23:59:00.000Z", 2)], 2),
      request("2026-11-16T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));

    expect(dailyFlags(collector.records("cursor"))).toEqual([
      ["2026-11-16T00:00:00.000Z", true],
      ["2026-11-17T00:00:00.000Z", true],
    ]);
  });

  test("does not mark a day the query ends inside, such as today", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-25T08:00:00.000Z", 1)], 1),
      request("2026-11-25T00:00:00.000Z", "2026-11-25T12:00:00.000Z"));

    expect(dailyFlags(collector.records("cursor"))).toEqual([["2026-11-25T00:00:00.000Z", false]]);
  });

  test("does not mark days of a query without an explicit range", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-16T05:00:00.000Z", 1)], 1), "{}");

    expect(dailyFlags(collector.records("cursor"))).toEqual([["2026-11-16T00:00:00.000Z", false]]);
  });
});

describe("CursorUsageCollector ranges", () => {
  const dailyFlags = (records: UsageRecord[]) => records
    .filter((record) => record.endedAt === undefined)
    .map((record) => [record.startedAt, record.completeDay === true]);

  test.each([
    ["after its end", "2026-11-18T01:00:00.000Z"],
    ["before its start", "2026-11-16T23:00:00.000Z"],
  ])("fails a query that returns an event %s", (_name, outside) => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T01:00:00.000Z", 3), event(outside, 5)], 2),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));

    expect(collector.records("cursor")).toEqual([]);
  });

  test.each([["covering first"], ["partial first"]])("a day fed by a covering and a partial query is not complete (%s)", (order) => {
    const collector = new CursorUsageCollector();
    const covering = () => collector.capture(200, page([event("2026-11-17T01:00:00.000Z", 3)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T23:59:59.999Z"));
    const partial = () => collector.capture(200, page([event("2026-11-17T05:00:00.000Z", 2)], 1),
      request("2026-11-17T00:00:00.000Z", "2026-11-17T12:00:00.000Z"));
    if (order === "covering first") { covering(); partial(); } else { partial(); covering(); }

    expect(dailyFlags(collector.records("cursor"))).toEqual([["2026-11-17T00:00:00.000Z", false]]);
  });

  test("a range with only a start is not complete", () => {
    const collector = new CursorUsageCollector();
    collector.capture(200, page([event("2026-11-17T01:00:00.000Z", 3)], 1),
      JSON.stringify({ startDate: String(Date.parse("2026-11-17T00:00:00.000Z")), page: 1, pageSize: 1000 }));

    expect(dailyFlags(collector.records("cursor"))).toEqual([["2026-11-17T00:00:00.000Z", false]]);
  });
});
