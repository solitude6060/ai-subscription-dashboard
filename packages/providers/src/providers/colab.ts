import { createHash } from "node:crypto";
import { join } from "node:path";
import type { UsageRecord } from "../../../core/src/types";
import type { UsageProvider } from "../types";
import { runCommand } from "./ccusage";

const COMMAND_TIMEOUT_MS = 20_000;
const SNAPSHOT_ID = createHash("sha256").update("colab|usage").digest("hex");

export interface ColabProviderOptions {
  env?: NodeJS.ProcessEnv;
  runner?: typeof runCommand;
  now?: () => number;
}

export class ColabProvider implements UsageProvider {
  id = "colab" as const;
  name = "Google Colab";
  private readonly env: NodeJS.ProcessEnv;
  private readonly runner: typeof runCommand;
  private readonly now: () => number;

  constructor(options: ColabProviderOptions = {}) {
    this.env = options.env ?? process.env;
    this.runner = options.runner ?? runCommand;
    this.now = options.now ?? Date.now;
  }

  async detect(): Promise<boolean> {
    return this.findExecutable() !== null;
  }

  async refresh(): Promise<UsageRecord[]> {
    const executable = this.findExecutable();
    if (!executable) {
      throw new Error("Google Colab executable not found. Install google-colab-cli or set COLAB_CLI_PATH.");
    }

    const result = await this.runner(executable, ["usage"], COMMAND_TIMEOUT_MS, { env: this.env });
    if (!result.ok) {
      const detail = result.stderr?.split(/\r?\n/, 1)[0]?.trim();
      throw new Error(detail ? `Google Colab command failed: ${detail}` : "Google Colab command failed.");
    }

    const output = result.stdout.split(/\r?\n/).map((line) => line.trim());
    const balance = usageValue(output, "Current balance", /^([+-]?\d+(?:\.\d+)?) compute units$/);
    if (balance === undefined) {
      throw new Error("Unrecognised Google Colab usage output: missing Current balance.");
    }
    const rate = usageValue(output, "Usage rate", /^([+-]?\d+(?:\.\d+)?)\/hr$/);
    const assignments = usageValue(output, "Active assignments", /^([+-]?\d+)$/);

    const lines = [{ type: "text", label: "Balance", value: `${balance} compute units` }];
    if (rate !== undefined) {
      // At most three lines: the dashboard collapses a card with more, balance included.
      const left = Number(rate) > 0 ? `, ${(Number(balance) / Number(rate)).toFixed(1)} h left` : "";
      lines.push({ type: "text", label: "Usage Rate", value: `${rate} units/hr${left}` });
    }
    if (assignments !== undefined) {
      lines.push({ type: "text", label: "Active Sessions", value: assignments });
    }

    return [{
      id: SNAPSHOT_ID,
      providerId: this.id,
      tool: "OpenUsage Plugin Snapshot",
      source: "cli",
      startedAt: new Date(this.now()).toISOString(),
      raw: { lines },
    }];
  }

  private findExecutable(): string | null {
    const { COLAB_CLI_PATH, PATH, HOME } = this.env;
    const options = { PATH: PATH ?? "" };
    return (COLAB_CLI_PATH ? Bun.which(COLAB_CLI_PATH, options) : null)
      ?? Bun.which("colab", options)
      ?? (HOME ? Bun.which(join(HOME, ".local", "bin", "colab"), options) : null);
  }
}

function usageValue(lines: string[], label: string, pattern: RegExp): string | undefined {
  const prefix = `${label}:`;
  const line = lines.find((candidate) => candidate.startsWith(prefix));
  if (line === undefined) return undefined;

  const value = line.slice(prefix.length).trim().match(pattern)?.[1];
  if (value === undefined || !Number.isFinite(Number(value))) {
    throw new Error(`Unrecognised Google Colab usage output: invalid ${label}.`);
  }
  return value;
}
