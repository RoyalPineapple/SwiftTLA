import Foundation
import OSLog

private let log = Logger(subsystem: "com.apple.runtime-issues", category: "SwiftTLA")

func runtimeWarning(_ message: String) {
    log.fault("\(message, privacy: .public)")
}
