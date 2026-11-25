# Google Colab

The WebUI displays the Google Colab compute-unit balance for the account signed in to the Colab CLI on the server.

## Setup

1. Install `google-colab-cli` with `uv tool install google-colab-cli` on the WebUI server. Use the OS account that runs the server and sign in with the CLI.
2. Run `colab usage` with that account and check that it prints `Current balance`. To specify an executable, set `COLAB_CLI_PATH` to its absolute path in the server environment. The server trims surrounding whitespace and reports an error if the resulting non-empty path is invalid. When the variable is unset or blank, the server checks its own `PATH`, then `$HOME/.local/bin/colab`.
3. On the **Providers** page, refresh **Google Colab**.

## Dashboard Lines

| Line | Value |
| --- | --- |
| Balance | Remaining compute units |
| Usage Rate | Compute units consumed per hour, when reported. When the rate is positive, the hours left (balance divided by the rate, one decimal place) follow on the same line. |
| Active Sessions | Active assignments, when reported |

The snapshot has no quota limit or reset time. It contributes no tokens or cost to usage totals.

## Refresh Errors

The **Providers** page shows errors if the CLI is missing, exits unsuccessfully, takes longer than 20 seconds, or returns unrecognised usage output. If detection fails, check that the CLI is executable and visible to the server. If the CLI exits with an error, run `colab usage` as the server's OS account and check the error it reports.
