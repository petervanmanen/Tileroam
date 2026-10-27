import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import BackgroundTasks
#endif

/// Work the user started that may go on when they leave the app: iOS 26's continued processing
/// (`BGContinuedProcessingTask`). The system shows the progress in a Live Activity, where the user
/// can also stop it; when it does (or the system has to), `onExpire` is called. Used for the Garmin
/// download, whose first run goes through years of activities at a calm pace.
///
/// Each run has its own identifier under `identifierPrefix` (permitted with a wildcard in
/// Info.plist, `BGTaskSchedulerPermittedIdentifiers`). The Mac app keeps running in the background
/// anyway, so there it does nothing.
@MainActor
final class ContinuedWork {
    nonisolated static let identifierPrefix = "nl.petervanmanen.Tileroam.garmin."

    private var onExpire: () -> Void = {}
    private var isFinished = false
    /// Progress to show once the system has started the task.
    private var latest: (done: Int64, total: Int64, subtitle: String)?
    #if os(iOS) && !targetEnvironment(macCatalyst)
    private var task: BGContinuedProcessingTask?
    #endif

    enum StartError: LocalizedError {
        case unavailable, notRegistered, refused(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Downloading in the background isn't available on this device.")
            case .notRegistered, .refused:
                String(localized: "iOS didn't allow downloading in the background just now. Keep Tileroam open, or try again.")
            }
        }
    }

    /// Starts it. Fails when the system doesn't offer it (the Mac) or refuses the request: the
    /// work then simply runs while the app is open.
    static func start(title: String, subtitle: String, onExpire: @escaping () -> Void) -> Result<ContinuedWork, StartError> {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let work = ContinuedWork()
        work.onExpire = onExpire
        let identifier = identifierPrefix + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                work.began(task)
            }
        }
        guard registered else { return .failure(.notRegistered) }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return .failure(.refused(error.localizedDescription))
        }
        return .success(work)
        #else
        return .failure(.unavailable)
        #endif
    }

    /// The device can continue work in the background (iPhone and iPad, not the Mac).
    nonisolated static var isSupported: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Shows how far it is ("12 activities"); `total` is the best estimate so far.
    func progress(done: Int, total: Int, subtitle: String) {
        latest = (Int64(done), Int64(max(total, done, 1)), subtitle)
        show()
    }

    /// Tells the system the work is done (or stopped).
    func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true
        #if os(iOS) && !targetEnvironment(macCatalyst)
        task?.setTaskCompleted(success: success)
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func began(_ task: BGContinuedProcessingTask) {
        guard !isFinished else {
            task.setTaskCompleted(success: true) // done before the system got to it
            return
        }
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, !self.isFinished else { return }
                self.onExpire()
                self.finish(success: false)
            }
        }
        show()
    }
    #endif

    private func show() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard let task, let latest else { return }
        task.progress.totalUnitCount = latest.total
        task.progress.completedUnitCount = latest.done
        task.updateTitle(task.title, subtitle: latest.subtitle)
        #endif
    }
}
