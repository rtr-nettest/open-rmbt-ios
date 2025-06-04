@ObservationIgnored private var currentArea: Fence? { fences.last }

private func start() async {
    guard !isStarted else { return }
    isStarted = true
    fences.removeAll()
    locations.removeAll()

    backgroundActivity = CLBackgroundActivitySession()

    await iterate(updates())
}

private func stop() async {
    isStarted = false
    locationAccuracy = "N/A"
    latestTechnology = "N/A"

    if !fences.isEmpty {
        // save last location unexited location area into the persistence layer
        if let lastArea = fences.last, lastArea.dateExited == nil {
            try? persistenceService.save(lastArea)
        }

        do {
            try await sendResultsService.send(fences: fences)
        } catch {
            // TODO: display error
        }
    }
}
