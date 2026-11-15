import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { OpenUsagePluginProvider } from "../src/index";

describe("OpenUsagePluginProvider isolation behavior", () => {
  test("keeps plugin HOME aligned with the configured home directory", async () => {
    const home = mkdtempSync(join(tmpdir(), "openusage-provider-home-"));
    const provider = new OpenUsagePluginProvider({
      providerId: "synthetic",
      name: "Synthetic",
      homeDir: home,
      env: { HOME: "/ambient-home" },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "isolated-home",
          probe(ctx) {
            return { lines: [ctx.line.text({ label: "Home", value: ctx.host.env.get("HOME") })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Home", value: home }],
    });
  });

  test("expands plugin ccusage home paths against configured homeDir", async () => {
    const home = mkdtempSync(join(tmpdir(), "openusage-ccusage-home-"));
    const capturedEnv: Array<Record<string, string | undefined> | undefined> = [];
    const provider = new OpenUsagePluginProvider({
      providerId: "codex",
      name: "Codex",
      pluginId: "codex",
      homeDir: home,
      env: { OPENUSAGE_TEST_ENV: "ccusage-env" },
      ccusageRunner: (_command, _args, env) => {
        capturedEnv.push(env);
        return {
          exitCode: 0,
          stdout: '{"daily":[]}',
          stderr: "",
        };
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "codex",
          probe(ctx) {
            const result = ctx.host.ccusage.query({ provider: "codex", homePath: "~/codex-home" });
            return { plan: result.status, lines: [ctx.line.text({ label: "Status", value: result.status })] };
          },
        };
      `,
    });

    await provider.refresh();

    expect(capturedEnv[0]?.CODEX_HOME).toBe(join(home, "codex-home"));
    expect(capturedEnv[0]?.OPENUSAGE_TEST_ENV).toBe("ccusage-env");
  });

  test("prefers locally saved GitHub keychain token before environment fallback", async () => {
    const pluginDataDir = mkdtempSync(join(tmpdir(), "openusage-gh-local-env-keychain-"));
    const provider = new OpenUsagePluginProvider({
      providerId: "github-copilot",
      name: "GitHub Copilot",
      pluginDataDir,
      env: { GH_TOKEN: "env-gh-token" },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "gh-local-env",
          probe(ctx) {
            ctx.host.keychain.writeGenericPassword("gh:github.com", "local-gh-token");
            const token = ctx.host.keychain.readGenericPassword("gh:github.com");
            return { lines: [ctx.line.text({ label: "Token", value: token })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Token", value: "local-gh-token" }],
    });
  });

  test("falls back to environment GitHub token when local keychain entry is blank", async () => {
    const pluginDataDir = mkdtempSync(join(tmpdir(), "openusage-gh-blank-local-keychain-"));
    const provider = new OpenUsagePluginProvider({
      providerId: "github-copilot",
      name: "GitHub Copilot",
      pluginDataDir,
      env: { GH_TOKEN: "env-gh-token" },
      gitHubTokenRunner: () => {
        throw new Error("gh CLI should not be used when GH_TOKEN is available");
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "gh-blank-local",
          probe(ctx) {
            ctx.host.keychain.writeGenericPassword("gh:github.com", "   ");
            const token = ctx.host.keychain.readGenericPassword("gh:github.com");
            return { lines: [ctx.line.text({ label: "Token", value: token })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Token", value: "env-gh-token" }],
    });
  });

  test("runs GitHub CLI token lookup with configured homeDir environment", async () => {
    const home = mkdtempSync(join(tmpdir(), "openusage-gh-home-"));
    const ambientKey = "OPENUSAGE_TEST_AMBIENT_GITHUB";
    const previousAmbient = process.env[ambientKey];
    process.env[ambientKey] = "ambient-value";
    const capturedEnv: Array<Record<string, string | undefined> | undefined> = [];
    try {
      const provider = new OpenUsagePluginProvider({
        providerId: "github-copilot",
        name: "GitHub Copilot",
        homeDir: home,
        env: {},
        gitHubTokenRunner: (_args, opts) => {
          capturedEnv.push(opts.env);
          return {
            exitCode: 0,
            stdout: Buffer.from("gh-cli-token\n"),
          };
        },
        scriptText: `
          globalThis.__openusage_plugin = {
            id: "gh-env",
            probe(ctx) {
              const token = ctx.host.keychain.readGenericPassword("gh:github.com");
              return { lines: [ctx.line.text({ label: "Token", value: token })] };
            },
          };
        `,
      });

      await provider.refresh();

      expect(capturedEnv[0]?.HOME).toBe(home);
      expect(capturedEnv[0]?.[ambientKey]).toBeUndefined();
    } finally {
      if (previousAmbient === undefined) {
        delete process.env[ambientKey];
      } else {
        process.env[ambientKey] = previousAmbient;
      }
    }
  });

  test("uses injected GitHub token runner before the global spawn fallback", async () => {
    const home = mkdtempSync(join(tmpdir(), "openusage-gh-runner-"));
    const capturedEnv: Array<Record<string, string | undefined> | undefined> = [];
    const provider = new OpenUsagePluginProvider({
      providerId: "github-copilot",
      name: "GitHub Copilot",
      homeDir: home,
      gitHubTokenRunner: (_args: string[], opts: { env?: Record<string, string | undefined> }) => {
        capturedEnv.push(opts.env);
        return {
          exitCode: 0,
          stdout: Buffer.from("runner-gh-token\n"),
        };
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "gh-runner",
          probe(ctx) {
            const token = ctx.host.keychain.readGenericPassword("gh:github.com");
            return { lines: [ctx.line.text({ label: "Token", value: token })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Token", value: "runner-gh-token" }],
    });
    expect(capturedEnv[0]?.HOME).toBe(home);
  });

  test("prefers locally saved GitHub keychain token before gh CLI fallback", async () => {
    const pluginDataDir = mkdtempSync(join(tmpdir(), "openusage-gh-local-keychain-"));
    const provider = new OpenUsagePluginProvider({
      providerId: "github-copilot",
      name: "GitHub Copilot",
      pluginDataDir,
      gitHubTokenRunner: () => {
        throw new Error("gh CLI should not be used when local keychain has a token");
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "gh-local",
          probe(ctx) {
            ctx.host.keychain.writeGenericPassword("gh:github.com", "local-gh-token");
            const token = ctx.host.keychain.readGenericPassword("gh:github.com");
            return { lines: [ctx.line.text({ label: "Token", value: token })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Token", value: "local-gh-token" }],
    });
  });

  test("ignores blank configured homeDir values", async () => {
    const provider = new OpenUsagePluginProvider({
      providerId: "synthetic",
      name: "Synthetic",
      homeDir: "   ",
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "blank-home",
          probe(ctx) {
            return { lines: [ctx.line.text({ label: "AppData", value: ctx.app.appDataDir })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "AppData", value: join(process.env.HOME?.trim() || homedir(), ".openusage-webui") }],
    });
  });

  test("reads the agy token from the Secret Service keyring when the local store misses", async () => {
    const calls: string[][] = [];
    const provider = new OpenUsagePluginProvider({
      providerId: "antigravity",
      name: "Antigravity",
      pluginId: "antigravity",
      pluginDataDir: mkdtempSync(join(tmpdir(), "openusage-agy-keyring-")),
      env: {},
      secretServiceRunner: (args) => {
        calls.push(args);
        return { exitCode: 0, stdout: Buffer.from('{"token":{"access_token":"keyring-token"}}\n') };
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "agy-keyring",
          probe(ctx) {
            const raw = ctx.host.keychain.readGenericPassword("gemini", "antigravity");
            return { lines: [ctx.line.text({ label: "Raw", value: raw })] };
          },
        };
      `,
    });

    const records = await provider.refresh();

    expect(records[0]?.raw).toMatchObject({
      lines: [{ type: "text", label: "Raw", value: '{"token":{"access_token":"keyring-token"}}' }],
    });
    expect(calls).toHaveLength(1);
    expect(calls[0]?.slice(-2)).toEqual(["gemini", "antigravity"]);
  });

  test("reports a missing keyring item as not found", async () => {
    const provider = new OpenUsagePluginProvider({
      providerId: "antigravity",
      name: "Antigravity",
      pluginId: "antigravity",
      pluginDataDir: mkdtempSync(join(tmpdir(), "openusage-agy-keyring-miss-")),
      env: {},
      secretServiceRunner: () => ({ exitCode: 3, stdout: Buffer.from("") }),
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "agy-keyring-miss",
          probe(ctx) {
            try {
              ctx.host.keychain.readGenericPassword("gemini", "antigravity");
              return { lines: [ctx.line.text({ label: "Result", value: "found" })] };
            } catch (e) {
              return { lines: [ctx.line.text({ label: "Result", value: String(e) })] };
            }
          },
        };
      `,
    });

    const records = await provider.refresh();
    const line = (records[0]?.raw as { lines: Array<{ value: string }> }).lines[0];

    expect(line?.value).toContain("not found");
  });

  test.each([
    ["another keychain service", "claude-code", "claude", "Claude Code-credentials", "user"],
    ["another plugin asking for gemini", "gemini-cli", "gemini-cli", "gemini", "antigravity"],
    ["another gemini account", "antigravity", "antigravity", "gemini", "other-account"],
  ] as const)("never reads the Secret Service keyring for %s", async (_case, providerId, pluginId, service, account) => {
    let runnerCalls = 0;
    const provider = new OpenUsagePluginProvider({
      providerId,
      name: "Keyring Scope",
      pluginId,
      pluginDataDir: mkdtempSync(join(tmpdir(), "openusage-keyring-scope-")),
      env: {},
      secretServiceRunner: () => {
        runnerCalls += 1;
        return { exitCode: 0, stdout: Buffer.from("must-not-be-returned") };
      },
      scriptText: `
        globalThis.__openusage_plugin = {
          id: "keyring-scope",
          probe(ctx) {
            try {
              const value = ctx.host.keychain.readGenericPassword(${JSON.stringify(service)}, ${JSON.stringify(account)});
              return { lines: [ctx.line.text({ label: "Result", value: "found:" + value })] };
            } catch (e) {
              return { lines: [ctx.line.text({ label: "Result", value: String(e) })] };
            }
          },
        };
      `,
    });

    const records = await provider.refresh();
    const line = (records[0]?.raw as { lines: Array<{ value: string }> }).lines[0];

    expect(runnerCalls).toBe(0);
    expect(line?.value).toContain("not found");
  });
});
