import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "bun:test";
import type { CcusageCommandRunner } from "../src/providers/ccusage";
import { ColabProvider } from "../src/providers/colab";

const observedUsage = [
  "Current balance: 341.98 compute units",
  "Usage rate: 0.00/hr",
  "Active assignments: 0",
].join("\n");
const balanceLine = { type: "text", label: "Balance", value: "341.98 compute units" };
const zeroRateLine = { type: "text", label: "Usage Rate", value: "0.00 units/hr" };
const noSessionsLine = { type: "text", label: "Active Sessions", value: "0" };
const snapshotId = createHash("sha256").update("colab|usage").digest("hex");
const now = Date.parse("2026-11-25T10:00:00.000Z");

function makeProvider(
  result: Awaited<ReturnType<CcusageCommandRunner>> = { ok: true, stdout: observedUsage },
  env: NodeJS.ProcessEnv = { COLAB_CLI_PATH: process.execPath },
) {
  const calls: Array<{ command: string; args: string[]; timeoutMs?: number }> = [];
  const provider = new ColabProvider({
    env,
    now: () => now,
    runner: async (command, args, timeoutMs) => {
      calls.push({ command, args, timeoutMs });
      return result;
    },
  });
  return { provider, calls };
}

describe("ColabProvider", () => {
  test("refresh runs usage once and renders the observed output as text", async () => {
    const { provider, calls } = makeProvider();

    expect((await provider.refresh()).map((record) => record.raw)).toEqual([
      { lines: [balanceLine, zeroRateLine, noSessionsLine] },
    ]);
    expect(calls).toEqual([{ command: process.execPath, args: ["usage"], timeoutMs: 20_000 }]);
  });

  test("a positive usage rate adds the estimated time left to one decimal place", async () => {
    const { provider } = makeProvider({
      ok: true,
      stdout: "Current balance: 37.00 compute units\r\nUsage rate: 3.00/hr\r\nActive assignments: 2\r\n",
    });

    expect((await provider.refresh()).map((record) => record.raw)).toEqual([{
      lines: [
        { type: "text", label: "Balance", value: "37.00 compute units" },
        { type: "text", label: "Usage Rate", value: "3.00 units/hr" },
        { type: "text", label: "Time Left", value: "12.3 h" },
        { type: "text", label: "Active Sessions", value: "2" },
      ],
    }]);
  });

  test("missing optional lines leave only the balance", async () => {
    const { provider } = makeProvider({ ok: true, stdout: "Current balance: 341.98 compute units" });

    expect((await provider.refresh()).map((record) => record.raw)).toEqual([{ lines: [balanceLine] }]);
  });

  test.each([
    ["missing", "Usage rate: 0.00/hr\nActive assignments: 0"],
    ["non-numeric", "Current balance: unknown compute units"],
    ["wrong case", "Current Balance: 341.98 compute units"],
  ])("refresh rejects a %s balance", async (_description, stdout) => {
    const { provider } = makeProvider({ ok: true, stdout });

    await expect(provider.refresh()).rejects.toThrow(/Unrecognised Google Colab usage output.*Current balance/);
  });

  test.each([
    ["Usage rate", "Usage rate: stopped/hr"],
    ["Active assignments", "Active assignments: 0.5"],
  ])("refresh rejects a malformed %s line", async (label, line) => {
    const { provider } = makeProvider({
      ok: true,
      stdout: `Current balance: 341.98 compute units\n${line}`,
    });

    await expect(provider.refresh()).rejects.toThrow(new RegExp(`Unrecognised Google Colab usage output.*${label}`));
  });

  test("refresh reports a failed command with only the first line of stderr", async () => {
    const { provider } = makeProvider({ ok: false, stdout: observedUsage, stderr: "Sign in first\r\nDebug details" });

    await expect(provider.refresh()).rejects.toThrow(/^Google Colab command failed: Sign in first$/);
  });

  test("refresh reports a timeout from the command runner", async () => {
    const { provider } = makeProvider({ ok: false, stdout: "", stderr: "colab command timed out" });

    await expect(provider.refresh()).rejects.toThrow(/colab command timed out/);
  });

  test("refresh finds the executable using the override, then PATH, then the home directory", async () => {
    const dir = mkdtempSync(join(import.meta.dir, ".colab-executables-"));
    try {
      const override = join(dir, "custom-colab");
      const pathDir = join(dir, "bin");
      const homeBin = join(dir, ".local", "bin");
      mkdirSync(pathDir);
      mkdirSync(homeBin, { recursive: true });
      const pathColab = join(pathDir, "colab");
      const homeColab = join(homeBin, "colab");
      for (const executable of [override, pathColab, homeColab]) {
        symlinkSync(process.execPath, executable);
      }
      const nonExecutable = join(dir, "not-executable");
      writeFileSync(nonExecutable, "");

      for (const [env, command] of [
        [{ COLAB_CLI_PATH: override, PATH: pathDir, HOME: dir }, override],
        [{ COLAB_CLI_PATH: nonExecutable, PATH: pathDir, HOME: dir }, pathColab],
        [{ PATH: dir, HOME: dir }, homeColab],
      ] as const) {
        const { provider, calls } = makeProvider(undefined, env);
        await provider.refresh();
        expect(calls.map((call) => call.command)).toEqual([command]);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("detect finds an executable without running any command", async () => {
    const { provider, calls } = makeProvider();

    await expect(provider.detect()).resolves.toBe(true);
    expect(calls).toEqual([]);
  });

  test("detect returns false and refresh explains how to configure a missing executable", async () => {
    const { provider, calls } = makeProvider(undefined, {
      COLAB_CLI_PATH: import.meta.path,
      PATH: "",
    });

    await expect(provider.refresh()).rejects.toThrow(/executable not found.*COLAB_CLI_PATH/i);
    await expect(provider.detect()).resolves.toBe(false);
    expect(calls).toEqual([]);
  });

  test("refresh returns a single CLI snapshot with a fixed id and the refresh timestamp", async () => {
    const { provider } = makeProvider();
    const expected = [{
      id: snapshotId,
      providerId: "colab",
      tool: "OpenUsage Plugin Snapshot",
      source: "cli",
      startedAt: new Date(now).toISOString(),
      raw: { lines: [balanceLine, zeroRateLine, noSessionsLine] },
    }];

    expect(await provider.refresh()).toEqual(expected);
    expect(await provider.refresh()).toEqual(expected);
  });
});
