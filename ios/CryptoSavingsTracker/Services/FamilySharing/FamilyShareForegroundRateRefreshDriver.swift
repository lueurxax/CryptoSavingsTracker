import Foundation

/// Active 5-minute timer that triggers `ExchangeRateService.refreshRatesIfStale()`
/// during foreground sessions with active sharing.
///
/// The 15-minute periodic guard acts as a safety net to catch missed refreshes.
@MainActor
final class FamilyShareForegroundRateRefreshDriver {

    private let exchangeRateService: ExchangeRateServiceProtocol
    private let scheduler: FamilyShareScheduler
    private let rollout: FamilyShareRollout
    private let hasActiveSharing: @Sendable () -> Bool
    private let clock: FamilyShareClock

    private var refreshTimer: (any FamilyShareCancellable)?
    private var guardTimer: (any FamilyShareCancellable)?
    private var lastRefreshAttempt: Date?
    private var isActive = false

    init(
        exchangeRateService: ExchangeRateServiceProtocol,
        clock: FamilyShareClock = SystemClock(),
        scheduler: FamilyShareScheduler = GCDScheduler(),
        rollout: FamilyShareRollout = .shared,
        hasActiveSharing: @escaping @Sendable () -> Bool = { true }
    ) {
        self.exchangeRateService = exchangeRateService
        self.clock = clock
        self.scheduler = scheduler
        self.rollout = rollout
        self.hasActiveSharing = hasActiveSharing
    }

    /// Start the refresh driver. Called on foreground entry when sharing is active.
    func start() {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        guard hasActiveSharing() else { return }
        guard !isActive else { return }
        isActive = true

        Task { [weak self] in
            await self?.performRefresh()
        }

        // Primary 5-minute refresh timer
        refreshTimer = scheduler.schedulePeriodic(
            interval: FamilyShareFreshnessPolicy.rateCacheTTL
        ) { [weak self] in
            await self?.performRefresh()
        }

        // 15-minute safety-net guard
        guardTimer = scheduler.schedulePeriodic(
            interval: FamilyShareFreshnessPolicy.periodicGuardInterval
        ) { [weak self] in
            await self?.performGuardCheck()
        }
    }

    /// Suspend the driver. Called on background entry or when sharing stops.
    func suspend() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = nil
        guardTimer?.cancel()
        guardTimer = nil
    }

    /// Teardown for rollback.
    func teardown() {
        suspend()
        lastRefreshAttempt = nil
    }

    // MARK: - Private

    private func performRefresh() async {
        guard isActive, rollout.isFreshnessPipelineEnabled() else { return }
        guard hasActiveSharing() else {
            suspend()
            return
        }
        lastRefreshAttempt = clock.now()
        await exchangeRateService.refreshRatesIfStale()
    }

    private func performGuardCheck() async {
        guard isActive, rollout.isFreshnessPipelineEnabled() else { return }
        guard hasActiveSharing() else {
            suspend()
            return
        }

        // Check if the primary timer missed a refresh
        if let lastAttempt = lastRefreshAttempt {
            let elapsed = clock.now().timeIntervalSince(lastAttempt)
            if elapsed < FamilyShareFreshnessPolicy.rateCacheTTL {
                return // Primary timer is working fine
            }
        }

        // Force a refresh as safety net
        await exchangeRateService.refreshRatesIfStale()
        lastRefreshAttempt = clock.now()
    }
}
