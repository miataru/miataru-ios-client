import Foundation

struct RouteStepDTO: Codable, Identifiable {
    let id = UUID()
    let instruction: String
    let distanceMeters: Double
    let notice: String?
    let streetName: String?
    let transportType: String
    let expectedTravelTime: Double?
    let polylinePointCount: Int

    enum CodingKeys: String, CodingKey {
        case instruction
        case distanceMeters
        case notice
        case streetName
        case transportType
        case expectedTravelTime
        case polylinePointCount
    }
}

struct RouteLanguageResult: Codable {
    let languageCode: String
    let languageSuspect: Bool
    let steps: [RouteStepDTO]
}

typealias ExportBundle = [String: RouteLanguageResult]
