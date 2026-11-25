// Start the real Bun API with one synthetic collector and an isolated database.
import { startServer } from "../server/src/index";
import type { UsageProvider } from "../../packages/providers/src/index";

if (!process.env.OPENUSAGE_WEBUI_DIR) {
  throw new Error("Set OPENUSAGE_WEBUI_DIR to the test database directory");
}

const provider: UsageProvider = {
  id: "synthetic",
  name: "Demo Provider",
  detect: async () => true,
  refresh: async () => [{
    id: "native-client-smoke",
    providerId: "synthetic",
    tool: "OpenUsage Plugin Snapshot",
    startedAt: new Date().toISOString(),
    source: "api",
    raw: {
      lines: [{ type: "progress", label: "Session", used: 23, limit: 100, format: { kind: "percent" } }],
    },
  }],
};

const server = await startServer({ providers: [provider] });
console.log(`Fixture API listening on ${server.hostname}:${server.port}`);
