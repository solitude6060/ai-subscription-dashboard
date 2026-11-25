import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = join(import.meta.dir, "../src/cli-status.ts");

let home: string;

beforeEach(() => {
  home = mkdtempSync(join(tmpdir(), "openusage-cli-refresh-"));
  mkdirSync(join(home, "data"), { recursive: true });
});

afterEach(() => {
  rmSync(home, { recursive: true, force: true });
});

function stubServer(databasePath: string) {
  const posts: string[] = [];
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      const url = new URL(request.url);
      if (url.pathname === "/api/health") return Response.json({ ok: true, databasePath });
      if (request.method === "POST" && url.pathname === "/api/providers/refresh") {
        posts.push(url.pathname);
        return Response.json({ ok: true, results: [{ providerId: "cursor", ok: true, records: 3 }] });
      }
      return new Response("not found", { status: 404 });
    },
  });
  return { server, posts };
}

// Minimal environment so the CLI never sees the real home, keyring or provider credentials.
async function runRefresh(port: number): Promise<string> {
  const proc = Bun.spawn(["bun", CLI, "--refresh"], {
    env: {
      PATH: process.env.PATH ?? "",
      HOME: home,
      OPENUSAGE_WEBUI_DIR: join(home, "data"),
      OPENUSAGE_WEBUI_PORT: String(port),
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = await new Response(proc.stdout).text();
  await proc.exited;
  return output.replace(/\x1b\[[0-9;]*m/g, "");
}

describe("status:refresh beside a running WebUI server", () => {
  test("asks a server on the same database to refresh instead of writing itself", async () => {
    const { server, posts } = stubServer(join(home, "data", "openusage.sqlite"));
    try {
      const output = await runRefresh(server.port);
      expect(posts).toEqual(["/api/providers/refresh"]);
      expect(output).toContain("Refreshed through the WebUI server");
      expect(output).not.toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 60_000);

  test("refreshes locally when the server uses another database", async () => {
    const { server, posts } = stubServer(join(home, "other", "openusage.sqlite"));
    try {
      const output = await runRefresh(server.port);
      expect(posts).toEqual([]);
      expect(output).toContain("Refreshing providers...");
    } finally {
      server.stop(true);
    }
  }, 60_000);

  test("refreshes locally when no server answers", async () => {
    const { server } = stubServer("");
    const port = server.port;
    server.stop(true);
    const output = await runRefresh(port);
    expect(output).toContain("Refreshing providers...");
  }, 60_000);
});
