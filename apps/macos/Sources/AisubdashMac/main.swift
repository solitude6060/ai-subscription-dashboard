import Foundation

let probeArgs = Array(CommandLine.arguments.dropFirst())
if let exitCode = await ProbeRunner.runIfRequested(arguments: probeArgs) {
    exit(exitCode)
}

#if os(macOS)
AisubdashMenuBarApp.main()
#else
fputs("AisubdashMac GUI is only supported on macOS. Use --probe-local or --probe-tailscale <URL>.\n", stderr)
exit(1)
#endif
