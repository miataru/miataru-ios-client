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

// MARK: - Fill style support

public extension QRCode {
	@objc(QRCodeFillStyle) class FillStyle: NSObject {

		private override init() { super.init() }

		/// Simple convenience for a clear fill
		@objc public static let clear = FillStyle.Solid(.commonClear)

		/// An object to contain SVG data during rendering
		@objc public class SVGDefinition: NSObject {
			/// The string representation that goes into the SVG tag (eg. `<rect [id="xxx", fill="yyy"] />`
			let styleAttribute: String
			/// The SVG style component that exists within the `<defs>` section of the SVG (optional)
			let styleDefinition: String?
			internal init(styleAttribute: String, styleDefinition: String?) {
				self.styleAttribute = styleAttribute
				self.styleDefinition = styleDefinition
			}
		}
	}
}

/// A protocol for wrapping fill styles for image generation
@objc public protocol QRCodeFillStyleGenerator {
	/// Get the fill style generator name
	@objc static var Name: String { get }
	/// Create a fill style generator using the specified settings
	static func Create(settings: [String: Any]) throws -> (any QRCodeFillStyleGenerator)
	/// Make a copy of the style
	@objc func copyStyle() throws -> any QRCodeFillStyleGenerator
	/// Returns the current settings for the style generator
	@objc func settings() throws -> [String: Any]
	/// Fill the specified rect with the current style settings
	func fill(ctx: CGContext, rect: CGRect)
	/// Fill the specified path with the current style settings
	func fill(ctx: CGContext, rect: CGRect, path: CGPath, expectedPixelSize: CGFloat, shadow: QRCode.Shadow?)
	/// Returns an SVG fill definition object for the fill style
	func svgRepresentation(styleIdentifier: String, expectedPixelSize: CGFloat, shadow: QRCode.Shadow?) throws -> QRCode.FillStyle.SVGDefinition
}

private let FillStyleTypeName = "type"
private let FillStyleSettingsName = "settings"

public extension QRCodeFillStyleGenerator {
	var name: String { return Self.Name }

	internal func coreSettings() throws -> [String: Any] {
		var core: [String: Any] = [FillStyleTypeName: self.name]
		core[FillStyleSettingsName] = try self.settings()
		return core
	}
}

extension QRCodeFillStyleGenerator {
	/// Make an image representation of the fill style
	/// - Parameters:
	///   - width: The image width
	///   - height: The image height
	///   - isFlipped: Flip the image
	/// - Returns: The image
	public func makeImage(width: Int, height: Int, isFlipped: Bool = false) throws -> CGImage {
		let sz = CGSize(width: width, height: height)
		return try CGImage.Create(size: sz, flipped: isFlipped) { ctx in
			self.fill(ctx: ctx, rect: CGRect(origin: .zero, size: sz))
		}
	}

	/// Make an image representation of the fill style
	/// - Parameters:
	///   - dimension: The dimension of the resulting image
	///   - isFlipped: Flip the image
	/// - Returns: The image
	public func makeImage(dimension: Int, isFlipped: Bool = false) throws -> CGImage {
		try self.makeImage(width: dimension, height: dimension, isFlipped: isFlipped)
	}
}
