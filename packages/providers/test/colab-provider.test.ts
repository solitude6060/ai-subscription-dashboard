import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "bun:test";
import { createRequestHandler } from "../../../apps/server/src/index";
import { isProviderRefreshable, providerCards } from "../../../apps/web/src/provider-ui";
import type { UsageRecord } from "../../core/src/types";
import { SqliteStorage } from "../../storage/src/index";
import * as providers from "../src/index";
import { runCommand, type CcusageCommandRunner } from "../src/providers/ccusage";
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
const runnerDeadlineMs = 5_000;
const fixtureSleep = "await Bun.sleep(30_000)";

function isRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
    return false;
  }
}

async function stopFixture(pidPath: string): Promise<void> {
  const file = Bun.file(pidPath);
  if (!(await file.exists())) return;
  const pid = Number(await file.text());
  if (!isRunning(pid)) return;

  process.kill(pid, "SIGKILL");
  const stopBy = performance.now() + runnerDeadlineMs;
  while (isRunning(pid)) {
    expect(performance.now()).toBeLessThan(stopBy);
    await Bun.sleep(25);
  }
}

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
        { type: "text", label: "Usage Rate", value: "3.00 units/hr, 12.3 h left" },
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

  test("the shared runner times out when the command exits before its output closes", async () => {
    const dir = mkdtempSync(join(import.meta.dir, ".colab-runner-"));
    const pidPath = join(dir, "child.pid");
    const parent = `
      const command = [process.execPath, "-e", ${JSON.stringify(fixtureSleep)}];
      if (process.platform === "linux") command.unshift("setsid");
      const child = Bun.spawn(command, {
        stdout: "inherit",
        stderr: "inherit",
      });
      await Bun.write(${JSON.stringify(pidPath)}, String(child.pid));
      child.unref();
      process.exit(0);
    `;

    try {
      const result = await runCommand(process.execPath, ["-e", parent], runnerDeadlineMs)
        .finally(() => stopFixture(pidPath));
      expect(result).toEqual({
        ok: false,
        stdout: "",
        stderr: `${process.execPath} command timed out`,
      });
      expect(isRunning(Number(await Bun.file(pidPath).text()))).toBe(false);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 30_000);

  test("the shared runner stops a command still running at the deadline", async () => {
    const dir = mkdtempSync(join(import.meta.dir, ".colab-runner-"));
    const pidPath = join(dir, "command.pid");
    const command = `
      await Bun.write(${JSON.stringify(pidPath)}, String(process.pid));
      ${fixtureSleep};
    `;

    try {
      await expect(runCommand(process.execPath, ["-e", command], runnerDeadlineMs)).resolves.toEqual({
        ok: false,
        stdout: "",
        stderr: `${process.execPath} command timed out`,
      });
      expect(isRunning(Number(await Bun.file(pidPath).text()))).toBe(false);
    } finally {
      await stopFixture(pidPath);
      rmSync(dir, { recursive: true, force: true });
    }
  }, 30_000);

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

test("the providers package exports ColabProvider", () => {
  expect(Reflect.get(providers, "ColabProvider")).toBe(ColabProvider);
});

test("the registry returns a Google Colab provider using the supplied environment", async () => {
  const provider = providers
    .getProviders({ env: { COLAB_CLI_PATH: process.execPath } })
    .find((item) => item.id === "colab");

  expect(provider).toBeInstanceOf(ColabProvider);
  expect(provider?.name).toBe("Google Colab");
  await expect(provider?.detect()).resolves.toBe(true);
});

test("the WebUI lists Google Colab", () => {
  expect(providerCards).toContainEqual({ providerId: "colab", name: "Google Colab" });
});

test("the WebUI can refresh Google Colab", () => {
  expect(isProviderRefreshable("colab")).toBe(true);
});

test("server refresh replaces the Colab snapshot and latest-snapshots returns it", async () => {
  const dataDir = mkdtempSync(join(import.meta.dir, ".colab-storage-"));
  const previousDataDir = process.env.OPENUSAGE_WEBUI_DIR;
  process.env.OPENUSAGE_WEBUI_DIR = dataDir;
  const storage = new SqliteStorage();
  try {
    let stdout = observedUsage;
    const provider = new ColabProvider({
      env: { COLAB_CLI_PATH: process.execPath },
      runner: async () => ({ ok: true, stdout }),
    });
    await storage.init();
    const before = await storage.getUsageSummary();
    const handle = createRequestHandler(storage, { host: "127.0.0.1", port: 6736 }, undefined, [provider]);

    for (const balance of ["341.98", "340.98"]) {
      stdout = observedUsage.replace("341.98", balance);
      const refresh = await handle(new Request("http://127.0.0.1:6736/api/providers/colab/refresh", {
        method: "POST",
      }));
      expect(refresh.status).toBe(200);
      expect(await refresh.json()).toEqual({
        ok: true,
        results: [{ providerId: "colab", ok: true, records: 1 }],
      });
    }

    const response = await handle(new Request("http://127.0.0.1:6736/api/usage/latest-snapshots"));
    expect(response.status).toBe(200);
    const records = await response.json() as UsageRecord[];
    expect(records).toEqual([expect.objectContaining({
      id: snapshotId,
      providerId: "colab",
      tool: "OpenUsage Plugin Snapshot",
      source: "cli",
      raw: {
        lines: [{ ...balanceLine, value: "340.98 compute units" }, zeroRateLine, noSessionsLine],
      },
    })]);
    expect(await storage.listUsageRecords({ providerId: "colab" })).toHaveLength(1);
    const after = await storage.getUsageSummary();
    expect(after.today).toMatchObject({ totalTokens: before.today.totalTokens, costUsd: before.today.costUsd });
    expect(after.month).toMatchObject({ totalTokens: before.month.totalTokens, costUsd: before.month.costUsd });
  } finally {
    storage.close();
    if (previousDataDir === undefined) delete process.env.OPENUSAGE_WEBUI_DIR;
    else process.env.OPENUSAGE_WEBUI_DIR = previousDataDir;
    rmSync(dataDir, { recursive: true, force: true });
  }
});
