//
//  KnownDevice.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//  Copyright © 2025 Miataru. All rights reserved.
//

import Foundation
import Combine
import UIKit
import MapKit

@objc(KnownDevice)
class KnownDevice: NSObject, ObservableObject, NSCoding, NSSecureCoding, Identifiable {
    @Published @objc var DeviceName: String
    @Published @objc var DeviceID: String
    @Published @objc var DeviceIsInGroup: Bool = false
    @Published @objc var KnownDevicesTablePosition: Int = 0
    @Published @objc var DeviceColor: UIColor?
    
    var id: String { DeviceID }
    
    init(name: String, deviceID: String, color: UIColor? = nil) {
        self.DeviceName = name
        self.DeviceID = deviceID
        self.DeviceColor = color
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.DeviceName = aDecoder.decodeObject(forKey: "DeviceName") as? String ?? ""
        self.DeviceID = aDecoder.decodeObject(forKey: "DeviceID") as? String ?? ""
        self.DeviceIsInGroup = aDecoder.decodeBool(forKey: "DeviceIsInGroup")
        self.KnownDevicesTablePosition = aDecoder.decodeInteger(forKey: "KnownDevicesTablePosition")
        let decodedColor = aDecoder.decodeObject(forKey: "DeviceColor") as? UIColor
        self.DeviceColor = decodedColor
        print(aDecoder.decodeObject(forKey: "DeviceName") as? String ?? "")
        print(aDecoder.decodeObject(forKey: "DeviceID") as? String ?? "")
        print(aDecoder.decodeBool(forKey: "DeviceIsInGroup"))
        print(aDecoder.decodeInteger(forKey: "KnownDevicesTablePosition"))
        print(String(describing: decodedColor))
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(DeviceName, forKey: "DeviceName")
        aCoder.encode(DeviceID, forKey: "DeviceID")
        aCoder.encode(DeviceIsInGroup, forKey: "DeviceIsInGroup")
        aCoder.encode(KnownDevicesTablePosition, forKey: "KnownDevicesTablePosition")
        aCoder.encode(DeviceColor, forKey: "DeviceColor")
        //print("Speichern ist temporär deaktiviert - muss repariert werden!!!")

    }

    static var supportsSecureCoding: Bool {
        return true
    }

    static func DeviceWithName(_ inName: String, deviceID inDeviceID: String) -> KnownDevice {
        return KnownDevice(name: inName, deviceID: inDeviceID)
    }

    //func setUpdateTime(_ NewUpdateDateTime: Date) {
    //    self.LastUpdate = NewUpdateDateTime
    //}
}
