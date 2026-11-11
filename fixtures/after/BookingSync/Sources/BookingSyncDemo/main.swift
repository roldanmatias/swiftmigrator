import BookingSync
import Foundation
import LegacyCalendarAPI

/// App-layer glue. R17: this target uses default MainActor isolation, so
/// `DemoController` is `@MainActor` with no annotation, and the async `load()`
/// replaces the completion handler.
final class DemoController {
    let viewModel: BookingViewModel
    var log: [String] = []

    init(viewModel: BookingViewModel) { self.viewModel = viewModel }

    func refresh() async {
        await viewModel.load()
        log.append("loaded \(viewModel.snapshot?.freeNights.count ?? 0) free nights")
        print(log.last ?? "")
    }
}

let client = CalendarClient(data: [1: [1, 2, 3, 4]])
let cache = AvailabilityCache(client: client)
let controller = DemoController(viewModel: BookingViewModel(listingID: 1, cache: cache, feed: AvailabilityFeed(client: client)))
await controller.refresh()
