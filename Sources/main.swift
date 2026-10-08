import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot") {
    exit(Snapshot.run(arguments: Array(args[(i + 1)...])))
}
if let i = args.firstIndex(of: "--icon") {
    exit(Snapshot.icon(arguments: Array(args[(i + 1)...])))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
