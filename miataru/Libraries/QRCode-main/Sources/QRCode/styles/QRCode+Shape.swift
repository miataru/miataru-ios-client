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

// MARK: - The shape

public extension QRCode {
	/// Represents the shape when generating the qr code
	@objc(QRCodeShape) final class Shape: NSObject, @unchecked Sendable {
		/// Create a new shape using
		/// - Parameters:
		///   - onPixels: The onPixels shape
		///   - offPixels: The offPixels shape
		///   - negatedOnPixelsOnly: If true, only draw the off pixels in the resulting QR code
		///   - extendOffPixelsIntoEmptyQRCodeComponents: If true, extends off-pixels into the blank areas of the QR code
		///   - mirrorEyePathsAroundQRCodeCenter: If true, flips the eye paths to mirror arround the center of the QR code
		///   - eye: The eye shape
		///   - pupil: The pupil shape
		@objc public init(
			onPixels: any QRCodePixelShapeGenerator = QRCode.PixelShape.Square(),
			offPixels: (any QRCodePixelShapeGenerator)? = nil,
			negatedOnPixelsOnly: Bool = false,
			extendOffPixelsIntoEmptyQRCodeComponents: Bool = false,
			mirrorEyePathsAroundQRCodeCenter: Bool = true,
			eye: any QRCodeEyeShapeGenerator = QRCode.EyeShape.Square(),
			pupil: (any QRCodePupilShapeGenerator)? = nil
		) {
			self.onPixels = onPixels
			self.offPixels = offPixels
			self.negatedOnPixelsOnly = negatedOnPixelsOnly
			self.extendOffPixelsIntoEmptyQRCodeComponents = extendOffPixelsIntoEmptyQRCodeComponents
			self.mirrorEyePathsAroundQRCodeCenter = mirrorEyePathsAroundQRCodeCenter
			self.eye = eye
			self.pupil = pupil
		}

		/// Convenience initializer for objc
		@objc public static func create() -> Shape { return Shape() }

		/// The shape of the 'on' pixels. Defaults to simple square 'pixels'
		@objc public var onPixels: any QRCodePixelShapeGenerator = QRCode.PixelShape.Square()

		/// The shape for drawing the non-drawn sections of the qr code.
		@objc public var offPixels: (any QRCodePixelShapeGenerator)?

		/// If set, the QR code draws the cells that AREN'T set within the QR code using the
		/// `onPixel` generator and style. All other styles (offPixels, eye, pupil) are ignored.
		///
		/// A negative path shape is filled using the 'onPixels' style
		@objc public var negatedOnPixelsOnly: Bool = false

		/// If true, draws 'offPixels' in the empty areas of the code
		@objc public var extendOffPixelsIntoEmptyQRCodeComponents: Bool = false

		/// If true, flips the eye paths to mirror arround the center of the QR code
		@objc public var mirrorEyePathsAroundQRCodeCenter: Bool = true

		/// The style of eyes to display
		///
		/// Defaults to a simple square eye
		@objc public var eye: any QRCodeEyeShapeGenerator = QRCode.EyeShape.Square() {
			didSet {
				// Reset the pupil shape to match the eye shape
				pupil = nil
			}
		}

		/// The shape of the pupil. If nil, uses the default pupil shape as defined by the eye
		@objc public var pupil: (any QRCodePupilShapeGenerator)? = nil

		/// Make a copy of the content shape
		@objc public func copyShape() -> Shape {
			let c = Shape()
			c.onPixels = self.onPixels.copyShape()
			c.offPixels = self.offPixels?.copyShape()
			c.eye = self.eye.copyShape()
			c.pupil = self.pupil?.copyShape()
			c.negatedOnPixelsOnly = self.negatedOnPixelsOnly
			c.extendOffPixelsIntoEmptyQRCodeComponents = self.extendOffPixelsIntoEmptyQRCodeComponents
			return c
		}
	}
}

public extension QRCode.Shape {
	/// Returns the actual shape that will be used when drawing.
	///
	/// If the pupil shape is `nil`, falls back to the eye shape
	@objc var actualPupilShape: any QRCodePupilShapeGenerator {
		self.pupil ?? self.eye.defaultPupil()
	}
}

// MARK: - Load/Save

public extension QRCode.Shape {

	@objc func settings() -> [String: Any] {
		var result: [String: Any] = [:]

		// The 'on' pixel shape settings
		result["onPixels"] = onPixels.coreSettings()

		// The 'off' pixels shape settings if they are defined
		if let offPixels = offPixels {
			result["offPixels"] = offPixels.coreSettings()
		}

		// The 'eye' pixel shape settings
		result["eye"] = eye.coreSettings()

		if let pupil = pupil {
			result["pupil"] = pupil.coreSettings()
		}

		result["negatedOnPixelsOnly"] = negatedOnPixelsOnly

		// Extend setting
		result["extendOffPixelsIntoEmptyQRCodeComponents"] = extendOffPixelsIntoEmptyQRCodeComponents

		// Eye mirror setting
		result["mirrorEyePathsAroundQRCodeCenter"] = mirrorEyePathsAroundQRCodeCenter

		return result
	}

	@objc static func Create(settings: [String: Any]) -> QRCode.Shape? {
		let result = QRCode.Shape()

		// The on-pixels

		// Backwards compatibility. Upgrade from old data type
		if let data = settings["data"] as? [String: Any],
			let shape = try? QRCodePixelShapeFactory.shared.create(settings: data)
		{
			result.onPixels = shape
		}
		else if let data = settings["onPixels"] as? [String: Any],
				  let shape = try? QRCodePixelShapeFactory.shared.create(settings: data)
		{
			result.onPixels = shape
		}

		// The eye

		if let eye = settings["eye"] as? [String: Any],
			let shape = try? QRCodeEyeShapeFactory.shared.create(settings: eye)
		{
			result.eye = shape
		}

		// The off-pixels

		// Load from the old version if it is available
		if let data = settings["dataInverted"] as? [String: Any],
			let shape = try? QRCodePixelShapeFactory.shared.create(settings: data)
		{
			result.offPixels = shape
		}
		else if let data = settings["offPixels"] as? [String: Any],
				  let shape = try? QRCodePixelShapeFactory.shared.create(settings: data)
		{
			result.offPixels = shape
		}

		if let data = settings["pupil"] as? [String: Any],
			let pupil = try? QRCodePupilShapeFactory.shared.create(settings: data)
		{
			result.pupil = pupil
		}

		if let negatedOnPixelsOnly = settings["negatedOnPixelsOnly"] as? Bool {
			result.negatedOnPixelsOnly = negatedOnPixelsOnly
		}

		if let extendOffPixelsIntoEmptyQRCodeComponents = settings["extendOffPixelsIntoEmptyQRCodeComponents"] as? Bool {
			result.extendOffPixelsIntoEmptyQRCodeComponents = extendOffPixelsIntoEmptyQRCodeComponents
		}

		if let mirrorEyePathsAroundQRCodeCenter = settings["mirrorEyePathsAroundQRCodeCenter"] as? Bool {
			result.mirrorEyePathsAroundQRCodeCenter = mirrorEyePathsAroundQRCodeCenter
		}

		return result
	}
}
