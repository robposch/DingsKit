#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import Foundation
import UIKit
import BackgroundTasks
import DingsKit

/// A snapshot of the OS-level conditions that decide whether the background
/// refresh task can run *at all* while the app is closed or the device is
/// locked. These are the things our code can't control but that silently block
/// `BGAppRefreshTask`, so we read and display them rather than guess.
public struct BackgroundDiagnostics: Sendable {
    /// "Available" / "Denied" / "Restricted" — `UIApplication.backgroundRefreshStatus`.
    public let backgroundRefreshLabel: String
    /// True only when refresh is `.available`; false means the OS will never run it.
    public let backgroundRefreshOK: Bool
    /// Low Power Mode suspends Background App Refresh entirely while it's on.
    public let lowPowerMode: Bool
    /// `earliestBeginDate` of our pending request, if one is queued with the system.
    public let pendingEarliest: Date?
    /// Whether a refresh request for our identifier is currently pending.
    public let hasPending: Bool

    @MainActor
    public static func gather() async -> BackgroundDiagnostics {
        let status = UIApplication.shared.backgroundRefreshStatus
        let label: String
        switch status {
        case .available:  label = coreLocalized("Available")
        case .denied:     label = coreLocalized("Denied")
        case .restricted: label = coreLocalized("Restricted")
        @unknown default: label = coreLocalized("Unknown")
        }

        // `BGTaskRequest` is not `Sendable` in every SDK, so the requests never
        // leave the callback: only the two values we need cross back.
        let taskID = Dings.config.backgroundTaskID
        let (hasPending, pendingEarliest): (Bool, Date?) = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                let ours = requests.first { $0.identifier == taskID }
                continuation.resume(returning: (ours != nil, ours?.earliestBeginDate))
            }
        }

        return BackgroundDiagnostics(
            backgroundRefreshLabel: label,
            backgroundRefreshOK: status == .available,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            pendingEarliest: pendingEarliest,
            hasPending: hasPending
        )
    }
}
#endif
