/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * KnownDevice.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import Combine
import UIKit
import MapKit

@objc(KnownDevice)
class KnownDevice: NSObject, ObservableObject, NSCoding, NSSecureCoding, Identifiable {
    @Published @objc var DeviceName: String {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var DeviceID: String {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var DeviceIsInGroup: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var KnownDevicesTablePosition: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var DeviceColor: UIColor? {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var hasCurrentLocationAccess: Bool = true {
        didSet {
            objectWillChange.send()
        }
    }
    @Published @objc var hasHistoryAccess: Bool = true {
        didSet {
            objectWillChange.send()
        }
    }
    
    var id: String { DeviceID }
    
    init(name: String, deviceID: String, color: UIColor? = nil, hasCurrentLocationAccess: Bool = true, hasHistoryAccess: Bool = true) {
        self.DeviceName = name
        self.DeviceID = deviceID
        self.DeviceColor = color
        self.hasCurrentLocationAccess = hasCurrentLocationAccess
        self.hasHistoryAccess = hasHistoryAccess
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.DeviceName = aDecoder.decodeObject(forKey: "DeviceName") as? String ?? ""
        self.DeviceID = aDecoder.decodeObject(forKey: "DeviceID") as? String ?? ""
        self.DeviceIsInGroup = aDecoder.decodeBool(forKey: "DeviceIsInGroup")
        self.KnownDevicesTablePosition = aDecoder.decodeInteger(forKey: "KnownDevicesTablePosition")
        let decodedColor = aDecoder.decodeObject(forKey: "DeviceColor") as? UIColor
        self.DeviceColor = decodedColor
        // Backward compatibility: default to true/true if keys are absent
        if aDecoder.containsValue(forKey: "hasCurrentLocationAccess") {
            self.hasCurrentLocationAccess = aDecoder.decodeBool(forKey: "hasCurrentLocationAccess")
        } else {
            self.hasCurrentLocationAccess = true
        }
        if aDecoder.containsValue(forKey: "hasHistoryAccess") {
            self.hasHistoryAccess = aDecoder.decodeBool(forKey: "hasHistoryAccess")
        } else {
            self.hasHistoryAccess = true
        }
        /*print(aDecoder.decodeObject(forKey: "DeviceName") as? String ?? "")
        print(aDecoder.decodeObject(forKey: "DeviceID") as? String ?? "")
        print(aDecoder.decodeBool(forKey: "DeviceIsInGroup"))
        print(aDecoder.decodeInteger(forKey: "KnownDevicesTablePosition"))
        print(String(describing: decodedColor))*/
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(DeviceName, forKey: "DeviceName")
        aCoder.encode(DeviceID, forKey: "DeviceID")
        aCoder.encode(DeviceIsInGroup, forKey: "DeviceIsInGroup")
        aCoder.encode(KnownDevicesTablePosition, forKey: "KnownDevicesTablePosition")
        aCoder.encode(DeviceColor, forKey: "DeviceColor")
        aCoder.encode(hasCurrentLocationAccess, forKey: "hasCurrentLocationAccess")
        aCoder.encode(hasHistoryAccess, forKey: "hasHistoryAccess")
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
