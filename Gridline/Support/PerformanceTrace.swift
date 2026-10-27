import Foundation

/// Opt-in development measurements. Captures no paths, arguments, or content,
/// and does not alter the executor or scheduling of the measured operation.
/// All mutable storage is protected by the lock; spans may finish on another executor.
nonisolated final class PerformanceTrace: @unchecked Sendable {
    enum Configuration {
        static let environmentKey = "GRIDLINE_PERF_TRACE"
        static let sampleCapacity = 4_096
    }

    enum Measurement: String, Codable, Sendable {
        case elapsed
        case synchronous
    }

    enum Stage: String, Codable, Sendable {
        case gitRequest, gitDecode
        case statusLoad, statusParse, statusMetadata, numstatParse, untrackedRead
        case comparisonLoad, comparisonParse, comparisonMetadata, diffParse
        case refresh, refreshWait, refreshPublish, diffLoad, diffPublish
        case fileFingerprint, fileLoad, fileReload
        case diffColumns, wordHighlight, treeBuild
        case stateEncode, stateWrite, paneUpdate, paneRebuild, metadataSnapshot

        var measurement: Measurement {
            switch self {
            case .gitRequest, .statusLoad, .comparisonLoad, .refresh, .refreshWait, .diffLoad, .fileReload:
                return .elapsed
            default:
                return .synchronous
            }
        }
    }

    enum Counter: String, Sendable {
        case gitLaunched, gitLaunchFailed
        case refreshCoalesced, branchCacheHit, branchCacheMiss
        case staleDiffDiscarded, staleComparisonDiscarded
        case columnCacheHit, columnCacheMiss, highlightCacheHit, highlightCacheMiss
        case fileReloadCoalesced, fileFingerprintUnchanged, persistenceCancelled
        case fileWatcherStartFailed
    }

    struct Span: Sendable {
        fileprivate let owner: ObjectIdentifier
        fileprivate let id: UInt64
        fileprivate let stage: Stage
        fileprivate let startedAt: UInt64
        fileprivate let startedOnMainThread: Bool
    }

    struct Sample: Codable, Sendable {
        let stage: Stage
        let measurement: Measurement
        let durationNanoseconds: UInt64
        let startedOnMainThread: Bool
        let finishedOnMainThread: Bool
        let itemCount: Int?
    }

    struct Snapshot: Codable, Sendable {
        let samples: [Sample]
        let counters: [String: Int]
        let activeSpanCount: Int
        let activeGitRequests: Int
        let peakGitRequests: Int
        let droppedSampleCount: Int
    }

    static let shared = PerformanceTrace(
        isEnabled: ProcessInfo.processInfo.environment[Configuration.environmentKey] == "1"
    )

    let isEnabled: Bool
    private let sampleCapacity: Int
    private let lock = NSLock()
    private var samples: [Sample] = []
    private var nextSampleIndex = 0
    private var nextSpanID: UInt64 = 0
    private var activeSpans = Set<UInt64>()
    private var counters: [String: Int] = [:]
    private var activeGitRequests = 0
    private var peakGitRequests = 0
    private var droppedSampleCount = 0

    init(isEnabled: Bool, sampleCapacity: Int = Configuration.sampleCapacity) {
        #if DEBUG
        self.isEnabled = isEnabled
        #else
        self.isEnabled = false
        #endif
        self.sampleCapacity = max(1, sampleCapacity)
    }

    func begin(_ stage: Stage) -> Span? {
        guard isEnabled else { return nil }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let onMainThread = Thread.isMainThread
        lock.lock()
        defer { lock.unlock() }
        nextSpanID &+= 1
        activeSpans.insert(nextSpanID)
        if stage == .gitRequest {
            activeGitRequests += 1
            peakGitRequests = max(peakGitRequests, activeGitRequests)
        }
        return Span(owner: ObjectIdentifier(self), id: nextSpanID, stage: stage,
                    startedAt: startedAt, startedOnMainThread: onMainThread)
    }

    func end(_ span: Span?, itemCount: Int? = nil) {
        guard isEnabled, let span, span.owner == ObjectIdentifier(self) else { return }
        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let onMainThread = Thread.isMainThread
        lock.lock()
        defer { lock.unlock() }
        guard activeSpans.remove(span.id) != nil else { return }
        if span.stage == .gitRequest { activeGitRequests -= 1 }
        let sample = Sample(
            stage: span.stage,
            measurement: span.stage.measurement,
            durationNanoseconds: finishedAt - span.startedAt,
            startedOnMainThread: span.startedOnMainThread,
            finishedOnMainThread: onMainThread,
            itemCount: itemCount
        )
        if samples.count < sampleCapacity {
            samples.append(sample)
        } else {
            samples[nextSampleIndex] = sample
            nextSampleIndex = (nextSampleIndex + 1) % sampleCapacity
            droppedSampleCount += 1
        }
    }

    func increment(_ counter: Counter) {
        guard isEnabled else { return }
        lock.lock()
        counters[counter.rawValue, default: 0] += 1
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let ordered = nextSampleIndex == 0 ? samples
            : Array(samples[nextSampleIndex...]) + Array(samples[..<nextSampleIndex])
        return Snapshot(samples: ordered, counters: counters, activeSpanCount: activeSpans.count,
                        activeGitRequests: activeGitRequests, peakGitRequests: peakGitRequests,
                        droppedSampleCount: droppedSampleCount)
    }

    /// Only reset between workloads; an active measurement must not be lost.
    @discardableResult
    func reset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeSpans.isEmpty else { return false }
        samples.removeAll(keepingCapacity: true)
        nextSampleIndex = 0
        counters.removeAll(keepingCapacity: true)
        activeGitRequests = 0
        peakGitRequests = 0
        droppedSampleCount = 0
        return true
    }
}
