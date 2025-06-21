//
//  PupilSettingsView.swift
//  QRCode 3D
//
//  Created by Darren Ford on 25/4/2024.
//

import SwiftUI
import QRCode

struct PupilGenerator: Identifiable {
	var id: String { generator.name }
	let generator: QRCodePupilShapeGenerator
	let image: Image
	init(_ generator: QRCodePupilShapeGenerator, _ image: CGImage) {
		self.generator = generator
		self.image = Image(image, scale: 2.0, orientation: .up, label: Text(generator.name))
	}
}

let availablePupilGenerators: [PupilGenerator] = {
	QRCodePupilShapeFactory.shared.all().map { gen in
		let image = try! QRCodePupilShapeFactory.shared.image(
			pupilGenerator: gen,
			dimension: 80,
			foregroundColor: textColor
		)
		return PupilGenerator(gen, image)
	}
}()

struct PupilSettingsView: View {

	@EnvironmentObject var document: QRCode_3DDocument
	@State var generator: QRCodePupilShapeGenerator = QRCode.PupilShape.Square()

	@State var flipped: QRCode.Flip = .none
	@State var supportsFlipped = false

	@State var hasInnerCorners = false
	@State var supportsHasInnerCorners = false

	@State var corners = QRCode.Corners.all
	@State var supportsCorners = false

	var body: some View {
		VStack {
			FlowLayout {
				ForEach(availablePupilGenerators) { item in
					Button {
						generator = item.generator
						document.qrcode.design.shape.pupil = item.generator
						document.objectWillChange.send()
						sync()
					} label: {
						item.image
					}
					.buttonStyle(.plain)
					.background(generator.name == item.generator.name ? Color.accentColor : Color.clear)
					.clipShape(RoundedRectangle(cornerSize: CGSize(width: 4, height: 4)))
				}
			}
			Divider()

			Form {
				LabeledContent("style") {
					StyleSelectorView(current: document.qrcode.design.style.actualPupilStyle) { newFill in
						document.qrcode.design.style.pupil = newFill
						document.objectWillChange.send()
					}
				}

				Picker("flip", selection: $flipped) {
					Text("none").tag(QRCode.Flip.none)
					Text("horizontally").tag(QRCode.Flip.horizontally)
					Text("vertically").tag(QRCode.Flip.vertically)
					Text("both").tag(QRCode.Flip.both)
				}
				.disabled(!supportsFlipped)
				.onChange(of: flipped) { newValue in
					_ = document.qrcode.design.shape.pupil?.setSettingValue(newValue.rawValue, forKey: QRCode.SettingsKey.flip)
					document.objectWillChange.send()
				}

				Toggle(isOn: $hasInnerCorners) {
					Text("inner corners")
				}
				.disabled(!supportsHasInnerCorners)
				.onChange(of: hasInnerCorners) { newValue in
					_ = document.qrcode.design.shape.pupil?.setSettingValue(newValue, forKey: QRCode.SettingsKey.hasInnerCorners)
					document.objectWillChange.send()
				}

				LabeledContent("corners") {
					CornerPicker(corners: $corners)
				}
				.disabled(!supportsCorners)
				.onChange(of: corners) { newValue in
					_ = document.qrcode.design.shape.pupil?.setSettingValue(newValue.rawValue, forKey: QRCode.SettingsKey.corners)
					document.objectWillChange.send()
				}
			}
			.padding(8)
		}
		.onAppear {
			generator = document.qrcode.design.shape.actualPupilShape
			sync()
		}
	}

	func sync() {
		generator = document.qrcode.design.shape.actualPupilShape

		supportsFlipped = generator.supportsSettingValue(forKey: QRCode.SettingsKey.flip)
		let fVal = generator.settingsValue(forKey: QRCode.SettingsKey.flip) ?? 0
		flipped = QRCode.Flip(rawValue: fVal) ?? .none

		supportsHasInnerCorners = generator.supportsSettingValue(forKey: QRCode.SettingsKey.hasInnerCorners)
		hasInnerCorners = generator.settingsValue(forKey: QRCode.SettingsKey.hasInnerCorners) ?? false

		supportsCorners = generator.supportsSettingValue(forKey: QRCode.SettingsKey.corners)
		let cnrs = generator.settingsValue(forKey: QRCode.SettingsKey.corners) ?? 0
		corners = QRCode.Corners(rawValue: cnrs)
	}

}

#Preview {
	PupilSettingsView().environmentObject(QRCode_3DDocument())
		.controlSize(.small)
		.frame(maxWidth: 300)
		.frame(height: 400)
}
