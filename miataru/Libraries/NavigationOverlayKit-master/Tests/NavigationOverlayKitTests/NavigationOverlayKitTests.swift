import XCTest
import MapKit
@testable import NavigationOverlayKit

final class NavigationOverlayKitTests: XCTestCase {
    func testInstructionCreationFromRouteStep() {
        let step = MKRoute.Step()
        step.setValue("Turn left onto Market Street", forKey: "instructions")
        step.setValue(120.0, forKey: "distance")

        let instruction = NavigationInstruction.from(step: step)
        XCTAssertEqual(instruction?.symbol, .left)
        XCTAssertEqual(instruction?.text, "Turn left onto Market Street")
        XCTAssertEqual(instruction?.distance.value, 120.0, accuracy: 0.1)
    }
}
