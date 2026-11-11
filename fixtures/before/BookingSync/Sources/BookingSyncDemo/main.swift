import BookingSync
import Foundation
import LegacyCalendarAPI

/// App-layer glue: everything here is UI code.
final class DemoController {
    let viewModel: BookingViewModel
    var log: [String] = []

    init(viewModel: BookingViewModel) { self.viewModel = viewModel }

    func refresh() {
        viewModel.load { [weak self] in
            self?.log.append("loaded \(self?.viewModel.snapshot?.freeNights.count ?? 0) free nights")
            print(self?.log.last ?? "")
            exit(0)
        }
    }
}

let client = CalendarClient(data: [1: [1, 2, 3, 4]])
let cache = AvailabilityCache(client: client)
let controller = DemoController(viewModel: BookingViewModel(listingID: 1, cache: cache, feed: AvailabilityFeed(client: client)))
controller.refresh()
dispatchMain()
