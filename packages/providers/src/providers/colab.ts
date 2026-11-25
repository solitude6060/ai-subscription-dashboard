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
      throw new Error("Google Colab executable not found. Set COLAB_CLI_PATH to an executable or unset it to use an installed google-colab-cli.");
    }

    const result = await this.runner(executable, ["usage"], COMMAND_TIMEOUT_MS, { env: this.env });
    if (!result.ok) {
      const firstLine = result.stderr?.split(/\r\n?|\n/).find((line) => line.trim())?.trim();
      const detail = firstLine?.match(/^.{1,200}/su)?.[0];
      throw new Error(detail ? `Google Colab command failed: ${detail}` : "Google Colab command failed.");
    }

    const output = result.stdout.split(/\r?\n/).map((line) => line.trim());
    const balance = usageValue(output, "Current balance", /^([+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?) compute units$/);
    if (balance === undefined) {
      throw new Error("Unrecognised Google Colab usage output: missing Current balance.");
    }
    const rate = usageValue(output, "Usage rate", /^((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)\/hr$/);
    const assignments = usageValue(output, "Active assignments", /^((?:\d{1,3}(?:,\d{3})+|\d+))$/);

    const lines = [{ type: "text", label: "Balance", value: `${balance.text} compute units` }];
    if (rate !== undefined) {
      // At most three lines: the dashboard collapses a card with more, balance included.
      const hoursLeft = balance.amount / rate.amount;
      const left = balance.amount >= 0 && rate.amount > 0 && Number.isFinite(hoursLeft)
        ? `, ${hoursLeft.toFixed(1)} h left`
        : "";
      lines.push({ type: "text", label: "Usage Rate", value: `${rate.text} units/hr${left}` });
    }
    if (assignments !== undefined) {
      lines.push({ type: "text", label: "Active Sessions", value: assignments.text });
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
    const override = COLAB_CLI_PATH?.trim();
    const options = { PATH: PATH ?? "" };
    if (override) return Bun.which(override, options);
    return Bun.which("colab", options)
      ?? (HOME ? Bun.which(join(HOME, ".local", "bin", "colab"), options) : null);
  }
}

function usageValue(lines: string[], label: string, pattern: RegExp) {
  const prefix = `${label}:`;
  const line = lines.find((candidate) => candidate.startsWith(prefix));
  if (line === undefined) return undefined;

  const text = line.slice(prefix.length).trim().match(pattern)?.[1];
  const amount = Number(text?.replaceAll(",", ""));
  if (text === undefined || !Number.isFinite(amount)) {
    throw new Error(`Unrecognised Google Colab usage output: invalid ${label}.`);
  }
  return { text, amount };
}
