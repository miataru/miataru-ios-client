@testable import QRCode

import XCTest

final class QRCodeSVGTests: XCTestCase {

	let outputFolder = try! testResultsContainer.subfolder(with: "QRCodeSVGTests")

	func testBasicSVG() throws {
		let doc = try QRCode.Document(
			utf8String: "This is a test This is a test This is a test This is a test",
			errorCorrection: .high,
			engine: __testEngine
		)

		do {
			let image = try resourceImage(for: "colored-fill", extension: "jpg")

			doc.design.foregroundColor(CGColor.RGBA(1, 0, 0, 1))
			doc.logoTemplate = QRCode.LogoTemplate(
				image: image,
				path: CGPath(ellipseIn: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3), transform: nil)
			)
			let svg = try doc.svg(dimension: 800)
			XCTAssertGreaterThan(svg.count, 0)

			try outputFolder.write(svg, to: "basicSVG1-mask-no-image.svg")
		}

		do {
			doc.design.foregroundColor(CGColor.RGBA(0, 0.3, 0, 1))
			let svg = try doc.svg(dimension: 512)
			XCTAssertGreaterThan(svg.count, 0)
			try outputFolder.write(svg, to: "basicSVG2-mask-no-image.svg")
		}
	}

	func testExportSVGWithSolidFill() throws {
		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)
		code.design.shape.onPixels = QRCode.PixelShape.CurvePixel(cornerRadiusFraction: 0.8)

		do {
			// Flat color
			code.design.style.onPixels = QRCode.FillStyle.Solid(CGColor.sRGBA(1, 0, 1, 1))

			let svg1 = try code.svg(dimension: 600)

			XCTAssertTrue(svg1.contains("fill=\"#ff00ff\""))
			try outputFolder.write(svg1, to: "solidFillGeneration.svg")

			let image = try code.platformImage(dimension: 300, dpi: 144)
			let data = try image.representation.png()
			try outputFolder.write(data, to: "solidFillGeneration.png")
		}
	}

	func testExportSVGWithLinearFill() throws {
		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)

		// Draw without a background
		code.design.style.background = nil

		code.design.shape.eye = QRCode.EyeShape.RoundedPointingIn()
		code.design.style.eye = QRCode.FillStyle.LinearGradient(
			try DSFGradient(
				pins: [
					DSFGradient.Pin(CGColor.sRGBA(0.6, 0.6, 0, 1), 0),
					DSFGradient.Pin(CGColor.sRGBA(0.0, 0.4, 0, 1), 1),
				]
			),
			startPoint: CGPoint(x: 0, y: 1),
			endPoint: CGPoint(x: 1, y: 1)
		)

		// linear color
		code.design.style.onPixels = QRCode.FillStyle.LinearGradient(
			try DSFGradient(
				pins: [
					DSFGradient.Pin(CGColor.sRGBA(1, 0, 0, 1), 0),
					DSFGradient.Pin(CGColor.sRGBA(0, 0, 1, 1), 1),
				]
			)
		)
		let svg1 = try code.svg(dimension: 600)
		try outputFolder.write(svg1, to: "svgExportLinearFill.svg")

		let image = try code.platformImage(dimension: 300, dpi: 144)
		let data = try image.representation.png()
		try outputFolder.write(data, to: "svgExportLinearFill.png")
	}

	func testExportSVGWithRadialFill() throws {
		let code = try QRCode.Document(
			utf8String: "https://www.apple.com/au/mac-studio/",
			errorCorrection: .high,
			engine: __testEngine
		)
		code.design.shape.onPixels = QRCode.PixelShape.CurvePixel(cornerRadiusFraction: 0.8)

		code.design.shape.eye = QRCode.EyeShape.Circle()
		code.design.shape.pupil = QRCode.PupilShape.BarsHorizontal()

		code.design.style.background = QRCode.FillStyle.Solid(1, 1.0, 0.8)
		code.design.style.eyeBackground = CGColor.commonWhite

		// radial fill
		let c = QRCode.FillStyle.RadialGradient(
			try DSFGradient(
				pins: [
					DSFGradient.Pin(CGColor.sRGBA(1, 0, 0, 1), 0),
					DSFGradient.Pin(CGColor.sRGBA(0, 1, 0, 1), 0.5),
					DSFGradient.Pin(CGColor.sRGBA(0, 0, 1, 1), 1.0),
				]
			),
			centerPoint: CGPoint(x: 0.5, y: 0.5)
		)

		code.design.style.onPixels = c
		let svg1 = try code.svg(dimension: 600)
		try outputFolder.write(svg1, to: "svgExportRadialFill.svg")

		let image = try code.platformImage(dimension: 300, dpi: 144)
		let data = try image.representation.png()
		try outputFolder.write(data, to: "svgExportRadialFill.png")
	}

	func testExportSVGWithBackgroundPixelColors() throws {

		let d = try QRCode.Document(engine: QRCodeEngineExternal())
		d.utf8String = "https://www.swift.org"

		d.design.backgroundColor(CGColor.sRGBA(0, 0.6, 0, 1))

		d.design.style.eye = QRCode.FillStyle.Solid(gray: 1)
		d.design.style.eyeBackground = CGColor.gray(0, 0.2)

		d.design.shape.onPixels = QRCode.PixelShape.Square(insetFraction: 0.7)
		d.design.style.onPixels = QRCode.FillStyle.Solid(gray: 1)
		d.design.style.onPixelsBackground = CGColor.sRGBA(1, 1, 1, 0.2)

		d.design.shape.offPixels = QRCode.PixelShape.Square(insetFraction: 0.7)
		d.design.style.offPixels = QRCode.FillStyle.Solid(gray: 0)
		d.design.style.offPixelsBackground = CGColor.sRGBA(0, 0, 0, 0.2)

		let svg1 = try d.svg(dimension: 600)
		try outputFolder.write(svg1, to: "svgExportPixelBackgroundColors.svg")
	}

	func testSVGFormatter() throws {
		// SVG Formatting should _always_ use '.' as the decimal separator
		XCTAssertEqual(_SVGF(0.33), "0.33")
		XCTAssertEqual(_SVGF(1), "1")
		XCTAssertEqual(_SVGF(1.4), "1.4")
		XCTAssertEqual(_SVGF(1024.56), "1024.56")
		XCTAssertEqual(_SVGF(123456789.789), "123456789.789")
	}

	func testExportSVGWithImage() throws {
		let fillImage = try resourceImage(for: "lego", extension: "jpeg")

		let d = try QRCode.Document(engine: __testEngine)
		try d.setText("https://www.apple.com/au/mac-studio/")
		d.design.backgroundColor(.commonBlack)
		d.design.shape.onPixels = QRCode.PixelShape.Razor()

		let qs = [0, 2, 4, 6]

		do {
			try qs.forEach { index in
				d.design.style.onPixels = .image(fillImage)
				d.design.additionalQuietZonePixels = UInt(index)
				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-All-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-All-q\(index).pdf")
			}
		}

		do {
			try qs.forEach { index in
				d.design.additionalQuietZonePixels = UInt(index)
				d.design.style.setForegroundStyle(QRCode.FillStyle.Solid(.commonWhite))
				d.design.style.eye = QRCode.FillStyle.Image(fillImage)
				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-Eye-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-Eye-q\(index).pdf")
			}
		}

		do {
			try qs.forEach { index in
				d.design.additionalQuietZonePixels = UInt(index)

				d.design.style.setForegroundStyle(QRCode.FillStyle.Solid(.commonWhite))
				d.design.style.eye = QRCode.FillStyle.Image(fillImage)
				d.design.style.pupil = QRCode.FillStyle.Solid(.commonWhite)

				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-EyeOuter-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-EyeOuter-q\(index).pdf")
			}
		}

		do {
			try qs.forEach { index in
				d.design.additionalQuietZonePixels = UInt(index)
				d.design.style.setForegroundStyle(QRCode.FillStyle.Solid(.commonWhite))
				d.design.style.pupil = QRCode.FillStyle.Image(fillImage)
				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-Pupil-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-Pupil-q\(index).pdf")
			}
		}

		do {
			try qs.forEach { index in
				d.design.additionalQuietZonePixels = UInt(index)
				d.design.style.setForegroundStyle(QRCode.FillStyle.Solid(.commonWhite))
				d.design.style.background = QRCode.FillStyle.Image(fillImage)
				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-Background-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-Background-q\(index).pdf")
			}
		}

		do {
			let backgroundImage = try resourceImage(for: "photo-logo", extension: "jpg")

			try qs.forEach { index in
				d.design.additionalQuietZonePixels = UInt(index)
				d.design.style.setForegroundStyle(QRCode.FillStyle.Image(fillImage))
				d.design.style.background = QRCode.FillStyle.Image(backgroundImage)
				let data = try d.svgData(dimension: 400)
				try outputFolder.write(data, to: "testExportSVGWithImage-Mixed-q\(index).svg")
				let data2 = try d.pdfData(dimension: 400)
				try outputFolder.write(data2, to: "testExportSVGWithImage-Mixed-q\(index).pdf")
			}
		}
	}

	#if os(macOS)
	func testIssue19ExportSVGIssue() throws {
		
		// You can test this by changing the text locale to French
		
		// See [Issue 19](https://github.com/dagronf/QRCode/issues/19)
		
		let d = try QRCode.Document(utf8String: "Test")
		d.errorCorrection = .low
		d.design.shape.eye = QRCode.EyeShape.RoundedOuter()
		d.design.shape.onPixels = QRCode.PixelShape.Circle()
		let str = try d.svg(dimension: 989)
		
		//		try str.write(
		//			to: URL(fileURLWithPath: "/tmp/qrcode19.svg"),
		//			atomically: true,
		//			encoding: .utf8
		//		)
		
		let existing = try resourceString(for: "Issue19Generated", extension: "svg")
		XCTAssertEqual(str, existing)
	}
	#endif

	func testBlockMaskPixelsForImageSVGIssue() throws {
		// This bug relates to SVG export, when the design has on-pixels negated
		// the pixel masking option for a logotemplate doesn't work
		let logo = QRCode.LogoTemplate(
			image: try resourceImage(for: "instagram-icon", extension: "png"),
			path: CGPath(rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30), transform: nil),
			inset: 8,
			masksQRCodePixels: true
		)

		let doc = try QRCode.build
			.content.text("This is a test of SVG exporting with broken mask pixels")
			.foregroundColor(CGColor(red: 0, green: 0, blue: 0.7, alpha: 1))
			.onPixels.shape(QRCode.PixelShape.Circle(insetFraction: 0.3))
			.isNegated(true)
			.logo(logo)
			.document

		let data = try doc.svgData(dimension: 400)
		try outputFolder.write(data, to: "broken-svg-masking.svg")
	}
}
