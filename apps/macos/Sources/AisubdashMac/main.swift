import Foundation

if let probe = ProbeRunner(arguments: Array(CommandLine.arguments.dropFirst())) {
    Task { exit(await probe.run()) }
    dispatchMain()
}

#if os(macOS)
AisubdashMenuBarApp.main()
#else
fputs("AisubdashMac GUI is only supported on macOS. Use --probe-local or --probe-tailscale <URL>.\n", stderr)
exit(1)
#endif
