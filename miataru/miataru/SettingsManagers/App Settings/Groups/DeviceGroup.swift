/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceGroup.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import UIKit
import Combine

@objc(DeviceGroup)
class DeviceGroup: NSObject, ObservableObject, NSCoding, NSSecureCoding, Identifiable {
    // Using @Published ensures observers get change notifications without manual didSet
    @Published @objc var groupName: String
    @Published @objc var deviceIDs: Set<String> = []
    @Published @objc var groupPosition: Int = 0
    
    var id: String { groupName }
    
    init(name: String) {
        self.groupName = name
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.groupName = aDecoder.decodeObject(forKey: "groupName") as? String ?? ""
        if let deviceIDsArray = aDecoder.decodeObject(forKey: "deviceIDs") as? [String] {
            self.deviceIDs = Set(deviceIDsArray)
        }
        self.groupPosition = aDecoder.decodeInteger(forKey: "groupPosition")
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(groupName, forKey: "groupName")
        aCoder.encode(Array(deviceIDs), forKey: "deviceIDs")
        aCoder.encode(groupPosition, forKey: "groupPosition")
    }
    
    static var supportsSecureCoding: Bool {
        return true
    }
    
    func addDevice(_ deviceID: String) {
        deviceIDs.insert(deviceID)
    }
    
    func removeDevice(_ deviceID: String) {
        deviceIDs.remove(deviceID)
    }
    
    func containsDevice(_ deviceID: String) -> Bool {
        return deviceIDs.contains(deviceID)
    }
    
    func toggleDevice(_ deviceID: String) {
        if containsDevice(deviceID) {
            removeDevice(deviceID)
        } else {
            addDevice(deviceID)
        }
    }
} 
