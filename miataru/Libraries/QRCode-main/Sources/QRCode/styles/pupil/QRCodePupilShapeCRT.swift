//
//  Copyright © 2025 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial
//  portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
//  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import CoreGraphics
import Foundation

extension QRCode.PupilShape {
	/// A pinch leaf pupil design
	@objc(QRCodePupilShapeCRT) public class CRT: NSObject, QRCodePupilShapeGenerator {
		/// Generator name
		@objc public static var Name: String { "crt" }
		/// Generator title
		@objc public static var Title: String { "CRT" }
		/// Create a hexagon leaf pupil shape, using the specified settings
		@objc public static func Create(_ settings: [String : Any]?) -> any QRCodePupilShapeGenerator { CRT() }

		/// Make a copy of the object
		@objc public func copyShape() -> any QRCodePupilShapeGenerator { CRT() }
		/// Reset the pupil shape generator back to defaults
		@objc public func reset() { }

		@objc public func settings() -> [String: Any] { [:] }
		@objc public func supportsSettingValue(forKey key: String) -> Bool { false }
		@objc public func setSettingValue(_: Any?, forKey _: String) -> Bool { false }

		/// The pupil centered in the 90x90 square
		@objc public func pupilPath() -> CGPath { pupilPath__ }
	}
}

public extension QRCodePupilShapeGenerator where Self == QRCode.PupilShape.CRT {
	/// Create a crt pupil shape generator with curved insets
	/// - Returns: A pupil shape generator
	@inlinable static func crt() -> QRCodePupilShapeGenerator { QRCode.PupilShape.CRT() }
}

// MARK: - Paths

private let pupilPath__: CGPath =
	CGPath.make { crt_pupilPath in
		crt_pupilPath.move(to: CGPoint(x: 30, y: 45))
		crt_pupilPath.curve(to: CGPoint(x: 31.29, y: 31.29), controlPoint1: CGPoint(x: 30, y: 37.5), controlPoint2: CGPoint(x: 31.29, y: 31.29))
		crt_pupilPath.curve(to: CGPoint(x: 45, y: 30), controlPoint1: CGPoint(x: 31.29, y: 31.29), controlPoint2: CGPoint(x: 37.5, y: 30))
		crt_pupilPath.curve(to: CGPoint(x: 58.71, y: 31.29), controlPoint1: CGPoint(x: 52.5, y: 30), controlPoint2: CGPoint(x: 58.71, y: 31.29))
		crt_pupilPath.curve(to: CGPoint(x: 60, y: 45), controlPoint1: CGPoint(x: 58.71, y: 31.29), controlPoint2: CGPoint(x: 60, y: 37.5))
		crt_pupilPath.curve(to: CGPoint(x: 58.71, y: 58.71), controlPoint1: CGPoint(x: 60, y: 52.5), controlPoint2: CGPoint(x: 58.71, y: 58.71))
		crt_pupilPath.curve(to: CGPoint(x: 45, y: 60), controlPoint1: CGPoint(x: 58.71, y: 58.71), controlPoint2: CGPoint(x: 52.5, y: 60))
		crt_pupilPath.curve(to: CGPoint(x: 31.29, y: 58.71), controlPoint1: CGPoint(x: 37.5, y: 60), controlPoint2: CGPoint(x: 31.29, y: 58.71))
		crt_pupilPath.curve(to: CGPoint(x: 30, y: 45), controlPoint1: CGPoint(x: 31.29, y: 58.71), controlPoint2: CGPoint(x: 30, y: 52.5))
		crt_pupilPath.close()
	}
