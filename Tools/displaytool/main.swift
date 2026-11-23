// displaytool: a small CLI for checking that Lidless's display switching works on this Mac.
//
//   displaytool list         show the displays macOS has online
//   displaytool off <secs>   turn the built-in display off, then back on after <secs> (default 10)
//   displaytool on <id>      turn a display back on (the built-in one is usually 1)

import CoreGraphics
import Foundation

func list() {
    let displays = Display.Snapshot.current()
    if let builtin = displays.builtin { print("\(builtin)\tbuilt-in\t\(CGDisplayPixelsWide(builtin))×\(CGDisplayPixelsHigh(builtin))") }
    for id in displays.externals { print("\(id)\texternal\t\(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id))") }
}

func set(_ id: CGDirectDisplayID, enabled: Bool) {
    print(Display.set(id, enabled: enabled) ? "Turned display \(id) \(enabled ? "on" : "off")." : "macOS rejected the change.")
    Thread.sleep(forTimeInterval: 1) // let the window server settle before listing
    list()
}

guard Display.isSupported else {
    print("CGSConfigureDisplayEnabled isn't available on this macOS version.")
    exit(2)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "list", nil:
    list()
case "off":
    let displays = Display.Snapshot.current()
    guard let builtin = displays.builtin, !displays.externals.isEmpty else {
        print("Needs an online built-in display and at least one external display.")
        exit(1)
    }
    let seconds = args.dropFirst().first.flatMap(Double.init) ?? 10
    set(builtin, enabled: false)
    print("Turning it back on in \(Int(seconds))s…")
    Thread.sleep(forTimeInterval: seconds)
    set(builtin, enabled: true)
case "on":
    set(args.dropFirst().first.flatMap(UInt32.init) ?? 1, enabled: true)
default:
    print("usage: displaytool list | off [seconds] | on [display-id]")
    exit(64)
}
