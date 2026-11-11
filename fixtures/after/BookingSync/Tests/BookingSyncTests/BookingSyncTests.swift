import Foundation
import LegacyCalendarAPI
import Observation
import Testing
@testable import BookingSync

// R15: XCTest → Swift Testing. Every test from the "before" fixture is kept;
// the new ones are regression tests for bugs the compiler can't see.

struct AlwaysApprove: PaymentAuthorizing {
    func authorize(guest: String, amountCents: Int) async throws { await Task.yield() }
}

struct DeclineGuest: PaymentAuthorizing {
    struct Declined: Error {}
    let guest: String
    func authorize(guest: String, amountCents: Int) async throws {
        if guest == self.guest { throw Declined() }
    }
}

func makeClient() -> CalendarClient { CalendarClient(data: [1: [1, 2, 3, 4, 5], 2: [10, 11]]) }

@Suite("AvailabilityCache")
struct AvailabilityCacheTests {
    @Test func cacheReturnsAvailability() async throws {
        let cache = AvailabilityCache(client: makeClient())
        #expect(try await cache.availability(for: 1).freeNights == [1, 2, 3, 4, 5])
        _ = try await cache.availability(for: 1)
        #expect(await cache.fetchCount == 1)
    }

    @Test func unknownListingFails() async {
        let cache = AvailabilityCache(client: makeClient())
        await #expect(throws: CalendarAPIError.self) { try await cache.availability(for: 99) }
    }

    /// Regression (R21): before the fix, 20 concurrent callers made up to 20 fetches.
    @Test(arguments: 0..<10)
    func concurrentCallersShareOneFetch(run: Int) async throws {
        let cache = AvailabilityCache(client: makeClient())
        try await withThrowingTaskGroup(of: AvailabilitySnapshot.self) { group in
            for _ in 0..<20 { group.addTask { try await cache.availability(for: 1) } }
            try await group.waitForAll()
        }
        #expect(await cache.fetchCount == 1)
    }
}

@Suite("BookingCoordinator")
struct BookingCoordinatorTests {
    @Test func booking() async throws {
        let coordinator = BookingCoordinator(cache: AvailabilityCache(client: makeClient()), payments: AlwaysApprove(), store: ReservationStore())
        let reservation = try await coordinator.book(guest: "alice", listingID: 1, nights: 1...2, amountCents: 100)
        #expect(reservation.nights == 1...2)
    }

    /// Regression (R21): before the fix, every guest passed the check while the
    /// first one was suspended in payment, and the same nights were sold 3 times.
    @Test(arguments: 0..<20)
    func theSameNightsAreSoldOnce(run: Int) async {
        let store = ReservationStore()
        let coordinator = BookingCoordinator(cache: AvailabilityCache(client: makeClient()), payments: AlwaysApprove(), store: store)
        let results = await withTaskGroup(of: Bool.self) { group in
            for guest in ["alice", "bob", "carol"] {
                group.addTask { (try? await coordinator.book(guest: guest, listingID: 1, nights: 2...3, amountCents: 100)) != nil }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count(where: { $0 }) == 1)
        #expect(store.all().count == 1)
    }

    @Test func aDeclinedPaymentReleasesTheHold() async throws {
        let coordinator = BookingCoordinator(cache: AvailabilityCache(client: makeClient()), payments: DeclineGuest(guest: "bob"), store: ReservationStore())
        await #expect(throws: SyncError.paymentDeclined) {
            try await coordinator.book(guest: "bob", listingID: 1, nights: 1...2, amountCents: 100)
        }
        #expect(try await coordinator.book(guest: "alice", listingID: 1, nights: 1...2, amountCents: 100).guest == "alice")
    }
}

@Suite("ConflictResolver")
struct ConflictResolverTests {
    let local = [Reservation(guest: "a", listingID: 1, nights: 1...2), Reservation(guest: "b", listingID: 1, nights: 5...6)]
    let server = [Reservation(guest: "s", listingID: 1, nights: 2...3)]

    @Test func serverWins() {
        #expect(ConflictResolver.resolve(local: local, server: server).map(\.guest) == ["s", "b"])
    }

    @MainActor @Test func concurrentVersionGivesTheSameResult() async {
        #expect(await ConflictResolver.resolved(local: local, server: server).map(\.guest) == ["s", "b"])
    }
}

@Suite("AvailabilityFeed")
struct AvailabilityFeedTests {
    @Test func streamDeliversPushesForItsListing() async {
        let client = makeClient()
        let feed = AvailabilityFeed(client: client)
        var updates = feed.updates(for: 2).makeAsyncIterator()
        client.simulatePush(RawChange(listingID: 1, freeNights: [1]))      // filtered out
        client.simulatePush(RawChange(listingID: 2, freeNights: [10]))
        #expect(await updates.next()?.listingID == 2)
    }

    /// Regression (R22): cancelling the consumer unregisters its handler.
    @Test func cancellingTheConsumerUnregisters() async {
        let feed = AvailabilityFeed(client: makeClient())
        let updates = feed.updates()                    // registers now
        let consumer = Task { for await _ in updates {} }
        #expect(feed.handlerCount == 1)
        consumer.cancel()
        await consumer.value
        #expect(feed.handlerCount == 0)
    }

    @available(*, deprecated)
    @Test func legacyHandlerAPIStillWorks() async {
        let client = makeClient()
        let feed = AvailabilityFeed(client: client)
        await withCheckedContinuation { continuation in
            feed.addHandler { snapshot in
                if snapshot.listingID == 2 { continuation.resume() }
            }
            client.simulatePush(RawChange(listingID: 2, freeNights: [10]))
        }
    }
}

@Suite("SyncEngine")
struct SyncEngineTests {
    @Test func pollsOnlyWhenTheClockMoves() async {
        let clock = ManualClock()
        let engine = SyncEngine(cache: AvailabilityCache(client: makeClient()), clock: clock, interval: .seconds(30))
        engine.watch([1, 2])
        engine.start()
        engine.start()                                                    // idempotent

        #expect(await eventually { clock.sleeperCount == 1 })            // pass 1 done, sleeping
        #expect(engine.completedPasses == 1)

        clock.advance(by: .seconds(30))
        #expect(await eventually { engine.completedPasses == 2 && clock.sleeperCount == 1 })

        engine.stop()
        #expect(await eventually { clock.sleeperCount == 0 })            // the sleep was cancelled
        clock.advance(by: .seconds(300))
        #expect(engine.completedPasses == 2)
        #expect(!engine.isRunning)
    }

    /// Regression (R23): before the fix, the polling task kept the engine alive forever.
    @Test func droppingTheEngineStopsPolling() async {
        let clock = ManualClock()
        weak var weakEngine: SyncEngine?
        do {
            let engine = SyncEngine(cache: AvailabilityCache(client: makeClient()), clock: clock)
            weakEngine = engine
            engine.start()
            #expect(await eventually { clock.sleeperCount == 1 })
        }
        #expect(weakEngine == nil)                                        // not retained while sleeping
        #expect(await eventually { clock.sleeperCount == 0 })            // deinit cancelled the loop
    }
}

@Suite("BookingViewModel")
@MainActor
struct BookingViewModelTests {
    @Test func loads() async {
        let client = makeClient()
        let viewModel = BookingViewModel(listingID: 1, cache: AvailabilityCache(client: client), feed: AvailabilityFeed(client: client))
        await viewModel.load()
        #expect(viewModel.snapshot?.freeNights.count == 5)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func failureSetsAnErrorMessage() async {
        let client = makeClient()
        let viewModel = BookingViewModel(listingID: 99, cache: AvailabilityCache(client: client), feed: AvailabilityFeed(client: client))
        await viewModel.load()
        #expect(viewModel.errorMessage == "Couldn't load availability")
    }

    @Test func pushesUpdateTheSnapshot() async {
        let client = makeClient()
        let viewModel = BookingViewModel(listingID: 2, cache: AvailabilityCache(client: client), feed: AvailabilityFeed(client: client))
        // Deterministic wait: Observation tells us when `snapshot` changes (no polling, no sleeping).
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = viewModel.snapshot } onChange: { continuation.resume() }
            client.simulatePush(RawChange(listingID: 2, freeNights: [11]))
        }
        #expect(viewModel.snapshot?.freeNights == [11])
    }

    /// Regression (R23): the subscription task doesn't keep the view model alive.
    @Test func viewModelDeinitUnsubscribes() async {
        let client = makeClient()
        let feed = AvailabilityFeed(client: client)
        weak var weakModel: BookingViewModel?
        do {
            let viewModel = BookingViewModel(listingID: 1, cache: AvailabilityCache(client: client), feed: feed)
            weakModel = viewModel
            #expect(feed.handlerCount == 1)
        }
        #expect(weakModel == nil)
        #expect(await eventually { feed.handlerCount == 0 })
    }

    @available(*, deprecated)
    @Test func legacyCompletionAPIStillWorks() async {
        let client = makeClient()
        let viewModel = BookingViewModel(listingID: 1, cache: AvailabilityCache(client: client), feed: AvailabilityFeed(client: client))
        await withCheckedContinuation { continuation in
            viewModel.load { continuation.resume() }
        }
        #expect(viewModel.snapshot?.freeNights.count == 5)
    }
}
