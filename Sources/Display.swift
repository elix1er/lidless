import CoreGraphics
import Foundation

/// Turns the built-in display on and off, as if the lid were closed.
///
/// Uses `CGSConfigureDisplayEnabled`, a private CoreGraphics function. It is looked up
/// at runtime, so a macOS release that removes it makes `isSupported` false instead of crashing.
enum Display {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureEnabled: ConfigureEnabled? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(symbol, to: ConfigureEnabled.self)
    }()

    static var isSupported: Bool { configureEnabled != nil }

    /// The displays macOS currently knows about. A disabled built-in display is absent.
    struct Snapshot {
        let builtin: CGDirectDisplayID?
        let externals: [CGDirectDisplayID]

        static func current() -> Snapshot {
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
            let online = ids.prefix(Int(count))
            return Snapshot(
                builtin: online.first { CGDisplayIsBuiltin($0) != 0 },
                externals: online.filter { CGDisplayIsBuiltin($0) == 0 }
            )
        }
    }

    /// Enables or disables a display until logout. Returns whether macOS accepted the change.
    @discardableResult
    static func set(_ display: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard let configureEnabled else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard configureEnabled(config, display, enabled) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}
