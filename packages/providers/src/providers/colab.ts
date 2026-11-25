import type { UsageRecord } from "../../../core/src/types";
import type { UsageProvider } from "../types";
import type { CcusageCommandRunner } from "./ccusage";

export interface ColabProviderOptions {
  env?: NodeJS.ProcessEnv;
  runner?: CcusageCommandRunner;
  now?: () => number;
}

export class ColabProvider implements UsageProvider {
  id = "colab" as const;
  name = "Google Colab";

  constructor(_options: ColabProviderOptions = {}) {}

  async detect(): Promise<boolean> {
    return false;
  }

  async refresh(): Promise<UsageRecord[]> {
    return [];
  }
}
