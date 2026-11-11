import XCTest
import LegacyCalendarAPI
@testable import BookingSync

final class AlwaysApprove: PaymentAuthorizing {
    func authorize(guest: String, amountCents: Int) async throws {}
}

final class BookingSyncTests: XCTestCase {
    func makeClient() -> CalendarClient { CalendarClient(data: [1: [1, 2, 3, 4, 5], 2: [10, 11]]) }

    func testCacheReturnsAvailability() async throws {
        let cache = AvailabilityCache(client: makeClient())
        let snapshot = try await cache.availability(for: 1)
        XCTAssertEqual(snapshot.freeNights, [1, 2, 3, 4, 5])
        _ = try await cache.availability(for: 1)
        let count = await cache.fetchCount
        XCTAssertEqual(count, 1)
    }

    func testUnknownListingFails() async {
        let cache = AvailabilityCache(client: makeClient())
        do {
            _ = try await cache.availability(for: 99)
            XCTFail("expected an error")
        } catch {}
    }

    func testBooking() async throws {
        let cache = AvailabilityCache(client: makeClient())
        let coordinator = BookingCoordinator(cache: cache, payments: AlwaysApprove(), store: ReservationStore())
        let reservation = try await coordinator.book(guest: "alice", listingID: 1, nights: 1...2, amountCents: 100)
        XCTAssertEqual(reservation.nights, 1...2)
    }

    func testConflictResolverServerWins() {
        let local = [Reservation(guest: "a", listingID: 1, nights: 1...2), Reservation(guest: "b", listingID: 1, nights: 5...6)]
        let server = [Reservation(guest: "s", listingID: 1, nights: 2...3)]
        XCTAssertEqual(ConflictResolver.resolve(local: local, server: server).map(\.guest), ["s", "b"])
    }

    func testFeedDeliversPushes() {
        let client = makeClient()
        let feed = AvailabilityFeed(client: client)
        let expectation = expectation(description: "push")
        feed.addHandler { snapshot in
            XCTAssertEqual(snapshot.listingID, 2)
            expectation.fulfill()
        }
        client.simulatePush(RawChange(listingID: 2, freeNights: [10]))
        wait(for: [expectation], timeout: 2)
    }

    func testViewModelLoads() {
        let client = makeClient()
        let viewModel = BookingViewModel(listingID: 1, cache: AvailabilityCache(client: client), feed: AvailabilityFeed(client: client))
        let expectation = expectation(description: "load")
        viewModel.load { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(viewModel.snapshot?.freeNights.count, 5)
    }
}
