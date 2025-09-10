/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * AppDirectories.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation

/// Helper methods for dealing with filesystem locations specific to the app.
///
/// Currently this type exposes a convenience method for creating paths inside the
/// app's "Application Support" directory.  Centralizing the logic ensures that
/// every component writes to the same location and the directory gets created when needed.
enum AppDirectories {
    /// Returns a file URL inside the application's Application Support folder, creating the folder if needed.
    /// - Parameter fileName: The name of the file.
    /// - Returns: The full URL to the file within the application's support directory.
    static func applicationSupportFile(named fileName: String) -> URL {
        let fileManager = FileManager.default

        // Base location for all Application Support files.
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        // Use the bundle identifier to create an app-specific subdirectory so our
        // files don't collide with those from other apps.
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)

        // Create the directory if it doesn't already exist.
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        // Append the desired file name to obtain the final file URL.
        return appDirectory.appendingPathComponent(fileName)
    }
}
