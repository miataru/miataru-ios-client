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

#if !os(watchOS)

import CoreGraphics
import CoreImage
import Foundation

/// A QR Code engine that uses Core Image filters to generate a QR Code
internal class QRCodeEngineCoreImage: QRCodeEngine {

	/// The generator name
	@objc public var name: String { "coreimage" }

	private let context = CIContext()
	private let filter = CIFilter(name: "CIQRCodeGenerator")!

	@objc func generate(text: String, errorCorrection: QRCode.ErrorCorrection) throws -> BoolMatrix {
		guard let data = text.data(using: .utf8) else {
			throw QRCodeError.unableToConvertTextToRequestedEncoding
		}
		return try self.generate(data: data, errorCorrection: errorCorrection)
	}

	@objc func generate(data: Data, errorCorrection: QRCode.ErrorCorrection) throws -> BoolMatrix {
		self.filter.setValue(data, forKey: "inputMessage")
		self.filter.setValue(errorCorrection.ECLevel, forKey: "inputCorrectionLevel")

		guard
			let outputImage = filter.outputImage,
			let qrImage = context.createCGImage(outputImage, from: outputImage.extent)
		else {
			throw QRCodeError.cannotGenerateImage
		}

		let w = qrImage.width
		let h = qrImage.height
		let colorspace = CGColorSpaceCreateDeviceGray()

		var rawData = [UInt8](repeating: 0, count: w * h)
		try rawData.withUnsafeMutableBytes { rawBufferPointer in
			let rawPtr = rawBufferPointer.baseAddress!
			guard let context = CGContext(
				data: rawPtr,
				width: w,
				height: h,
				bitsPerComponent: 8,
				bytesPerRow: w,
				space: colorspace,
				bitmapInfo: 0
			)
			else {
				throw QRCodeError.cannotGenerateImage
			}
			context.draw(qrImage, in: CGRect(x: 0, y: 0, width: w, height: h))
		}

		return BoolMatrix(dimension: w, flattened: rawData.map { $0 == 0 ? true : false })
	}
}

#endif
