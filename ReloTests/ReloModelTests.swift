import XCTest
@testable import Relo

@MainActor
final class ReloModelStopwatchPauseTests: XCTestCase {
  func testPauseCapturesElapsedTimeEvenBeforeTheNextDisplaySecondTick() throws {
    let model = ReloModel()
    model.startStopwatch()

    Thread.sleep(forTimeInterval: 0.4)
    model.pause()

    // `elapsed` is normally only refreshed once per whole displayed second, so
    // without a recompute on pause it would still read ~0 here.
    XCTAssertGreaterThan(model.elapsed, 0.3)
    XCTAssertLessThan(model.elapsed, 0.9)
  }

  func testRepeatedPauseResumeCyclesDoNotLoseElapsedTime() throws {
    let model = ReloModel()
    model.startStopwatch()

    for _ in 0..<3 {
      Thread.sleep(forTimeInterval: 0.3)
      model.pause()
      let pausedElapsed = model.elapsed
      Thread.sleep(forTimeInterval: 0.05)
      // Elapsed must not advance while paused.
      XCTAssertEqual(model.elapsed, pausedElapsed)
      model.resume()
    }

    // Three 0.3s runs should sum to roughly 0.9s, not be truncated away by
    // sub-second staleness at each pause boundary.
    XCTAssertGreaterThan(model.elapsed, 0.75)
  }
}
