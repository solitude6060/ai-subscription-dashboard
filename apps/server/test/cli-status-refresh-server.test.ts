import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { getProviders } from "../../../packages/providers/src/index";
import { SqliteStorage } from "../../../packages/storage/src/index";

const CLI = join(import.meta.dir, "../src/cli-status.ts");

let home: string;
let previousDir: string | undefined;

// Every provider is disabled in the test database, so the local branch prints its header and
// returns without running provider probes (ccusage via bunx/npx, Colab, a /proc scan).
beforeEach(async () => {
  home = mkdtempSync(join(tmpdir(), "openusage-cli-refresh-"));
  mkdirSync(join(home, "data"), { recursive: true });
  previousDir = process.env.OPENUSAGE_WEBUI_DIR;
  process.env.OPENUSAGE_WEBUI_DIR = join(home, "data");
  const storage = new SqliteStorage(join(home, "data", "openusage.sqlite"));
  await storage.init();
  for (const provider of getProviders()) {
    await storage.upsertProviderStatus({ providerId: provider.id, name: provider.name, enabled: false, detected: false });
  }
  storage.close();
});

afterEach(() => {
  if (previousDir === undefined) delete process.env.OPENUSAGE_WEBUI_DIR;
  else process.env.OPENUSAGE_WEBUI_DIR = previousDir;
  rmSync(home, { recursive: true, force: true });
});

function stubServer(databasePath: string, refreshStatus = 200, refreshBody: unknown = { ok: true, results: [{ providerId: "cursor", ok: true, records: 3 }] }, healthDelayMs = 0) {
  const posts: string[] = [];
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      const url = new URL(request.url);
      if (url.pathname === "/api/health") {
        if (healthDelayMs) await Bun.sleep(healthDelayMs);
        return Response.json({ ok: true, databasePath });
      }
      if (request.method === "POST" && url.pathname === "/api/providers/refresh") {
        posts.push(url.pathname);
        if (refreshStatus !== 200) return new Response("boom", { status: refreshStatus });
        return Response.json(refreshBody);
      }
      return new Response("not found", { status: 404 });
    },
  });
  return { server, posts };
}

// Minimal environment so the CLI never sees the real home, keyring or provider credentials.
async function runRefresh(port: number, dataDir = join(home, "data")) {
  const proc = Bun.spawn(["bun", CLI, "--refresh"], {
    cwd: home,
    env: { PATH: process.env.PATH ?? "", HOME: home, OPENUSAGE_WEBUI_DIR: dataDir, OPENUSAGE_WEBUI_PORT: String(port) },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { output: stdout.replace(/\x1b\[[0-9;]*m/g, ""), stderr, exitCode };
}

describe("status:refresh beside a running WebUI server", () => {
  test("asks a server on the same database to refresh instead of writing itself", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"));
    try {
      const { output, exitCode } = await runRefresh(server.port);
      expect(exitCode).toBe(0);
      expect(posts).toEqual(["/api/providers/refresh"]);
      expect(output).toContain("Refreshed through the WebUI server");
      expect(output).not.toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("matches the server's database when the CLI is given a relative data directory", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"));
    try {
      const { exitCode } = await runRefresh(server.port, "data");
      expect(exitCode).toBe(0);
      expect(posts).toEqual(["/api/providers/refresh"]);
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("matches the server's database through a symlinked directory", async () => {
    symlinkSync(join(home, "data"), join(home, "link"));
    const { server, posts } = stubServer(join(home, "link", "openusage.sqlite"));
    try {
      const { exitCode } = await runRefresh(server.port);
      expect(exitCode).toBe(0);
      expect(posts).toEqual(["/api/providers/refresh"]);
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("refreshes locally when the server reports a relative database path", async () => {
    const { server, posts } = stubServer("data/openusage.sqlite");
    try {
      const { output, exitCode } = await runRefresh(server.port);
      expect(exitCode).toBe(0);
      expect(posts).toEqual([]);
      expect(output).toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("refreshes locally when the server uses another database", async () => {
    const { server, posts } = stubServer(join(home, "other", "openusage.sqlite"));
    try {
      const { output, exitCode } = await runRefresh(server.port);
      expect(exitCode).toBe(0);
      expect(posts).toEqual([]);
      expect(output).toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("refreshes locally when no server answers", async () => {
    const { server } = stubServer("");
    const port = server.port;
    server.stop(true);
    const { output, exitCode } = await runRefresh(port);
    expect(exitCode).toBe(0);
    expect(output).toContain("Refreshing providers...");
  }, 30_000);

  test("fails without a local write when the server refresh fails", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"), 500);
    try {
      const { output, stderr, exitCode } = await runRefresh(server.port);
      expect(posts).toEqual(["/api/providers/refresh"]);
      expect(exitCode).not.toBe(0);
      expect(stderr).toContain("HTTP 500");
      expect(output).not.toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("fails without a local write when the server answers without a results list", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"), 200, { ok: true });
    try {
      const { output, exitCode } = await runRefresh(server.port);
      expect(posts).toEqual(["/api/providers/refresh"]);
      expect(exitCode).not.toBe(0);
      expect(output).not.toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);

  test("fails without a local write when the server does not answer the health probe in time", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"), 200, undefined, 3000);
    try {
      const { output, stderr, exitCode } = await runRefresh(server.port);
      expect(exitCode).not.toBe(0);
      expect(posts).toEqual([]);
      expect(stderr).toContain("did not answer");
      expect(output).not.toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 30_000);
});
