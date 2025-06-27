//
//  Copyright © 2024 Darren Ford. All rights reserved.
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

#if canImport(CoreGraphics)

import Foundation
import CoreGraphics

/// Draw into a single-page PDF document
/// - Parameters:
///   - size: The drawing size
///   - pdfResolution: The resolution of the pdf output
///   - drawBlock: The drawing block
/// - Returns: The pdf data for the drawing, or nil if an error occurred.
internal func UsingSinglePagePDFContext(
	size: CGSize,
	pdfResolution: CGFloat = 72.0,
	_ drawBlock: (CGContext, CGRect) throws -> Void
) throws -> Data {
	let pageWidth = size.width * (72.0 / pdfResolution)
	let pageHeight = size.height * (72.0 / pdfResolution)
	var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

	guard
		let data = CFDataCreateMutable(nil, 0),
		let pdfConsumer = CGDataConsumer(data: data),
		let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)
	else {
		throw ImageReadWriteError.cannotCreatePDFContext
	}

	// Start a new page of the required size
	pdfContext.beginPage(mediaBox: &mediaBox)

	// Perform the context drawing
	do {
		try drawBlock(pdfContext, mediaBox)
	}
	catch {
		throw error
	}

	// And end the page
	pdfContext.endPDFPage()

	// Close the pdf to make sure all data is written to the consumer
	pdfContext.closePDF()

	return data as Data
}

#endif
