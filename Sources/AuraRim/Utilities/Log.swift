import Foundation
import os

/// Structured logging via os.Logger, split into the categories named in the spec.
/// Never log raw audio, license keys, or private metadata.
enum Log {
    private static let subsystem = AppBrand.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let rendering = Logger(subsystem: subsystem, category: "rendering")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let licensing = Logger(subsystem: subsystem, category: "licensing")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
