# macOS menu bar code review

PR #69, initial code head `2104b7c1184a7c85404bd48632421b05d36fa406`, base
`8b08db8ade55e7ddcd153a84aac6cb0d91542890`. Independent reviewers received the
same source and workflow diff. Raw transcripts and CI logs are retained locally.
The GitHub macOS run [44940207923](https://github.com/solitude6060/ai-subscription-dashboard/actions/runs/44940207923)
compiled the signed arm64 bundle, passed 18 Swift tests, and read one synthetic quota
through each configured source.

| Finding | Severity | Verified effect | Disposition |
| --- | --- | --- | --- |
| Unrecognized launch arguments | High | ProbeRunner returns exit status 2 for OS or Xcode launch arguments and main exits before SwiftUI. | Limit probe handling to the two supported flags and verify an ordinary launch. |
| Default system proxy | Medium | The initial ephemeral configuration leaves `connectionProxyDictionary` nil, so it inherits proxy settings. | Use explicit direct session settings for the private origins. |
| Pin shown as missing before data loads | Medium | A persisted pin follows the same branch when the dashboard is nil and when a loaded dashboard omits the quota. | Track unavailable readings separately and test both states. |
| Refresh and read timeouts share a session | Medium | The initial session combines a 12-second request timeout and 120-second resource timeout with different per-request timeouts. | Match each request class to its session limits. |
| Native launch evidence | Medium | The first runner exercised the signed binary's probe modes and did not enter SwiftUI. | Add a hosted GUI-process launch smoke check. Physical interaction remains separate. |
| Remote Open Dashboard can initiate refresh | Medium | A deliberate click opens the existing Web application. Its browser JavaScript owns automatic provider refresh. | Preserve the approved interaction. The native client issues only GET requests to the remote, and the plan explicitly uses the Web dashboard for remote refresh. |
| Endpoint placeholder and build assertions | Low | The example hostname omitted a label. The initial workflow printed the architecture without asserting it. | Use a valid example and assert the required bundle properties. |

The backend's one-snapshot contract is verified by
`listLatestUsageSnapshots` in `packages/storage/src/sqlite-storage.ts`, which selects
row number 1 for each provider ID. The percent display uses the underlying percent
value consistent with `apps/web/src/components/usage-line.tsx`. Hosted CI uses an
aliased IPv4 address. The app's actual menu interaction and private tailnet connectivity
still require the target Mac.

[Apple session proxy settings](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/connectionproxydictionary.md)

Gemini 4 Neon separately blocked the initial revision. It identified a possible
main-queue deadlock when SwiftUI starts from the async entry point. A synchronous
GUI entry point preserves AppKit's startup context. Neon also traced request
cancellation from popover dismissal into the generic stale-network-error branch.
Exercise both the cancelled-read state and ordinary GUI launch during remediation.
