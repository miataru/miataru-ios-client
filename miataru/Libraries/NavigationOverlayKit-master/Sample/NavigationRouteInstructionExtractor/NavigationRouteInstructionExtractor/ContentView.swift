import SwiftUI
import Combine
import UniformTypeIdentifiers
import NavigationOverlayKit
import UIKit

@MainActor
final class ViewModel: ObservableObject {
    @Published var logs: [String] = []
    @Published var languages: [String] = ViewModel.defaultLanguages
    @Published var results: ExportBundle = [:]
    @Published var statuses: [String: Status] = [:]
    @Published var exportFileURL: URL?
    @Published var isRunning: Bool = false

    enum Status: Equatable {
        case pending
        case running
        case ok
        case warn
        case fail(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending), (.running, .running), (.ok, .ok), (.warn, .warn):
                return true
            case let (.fail(left), .fail(right)):
                return left == right
            default:
                return false
            }
        }

        var isTerminal: Bool {
            switch self {
            case .pending, .running:
                return false
            case .ok, .warn, .fail:
                return true
            }
        }
    }

    private static let maxLogEntries = 500
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let service = DirectionsService()

    static let defaultLanguages: [String] = [
        "ar", "bg", "ca", "cs", "da", "de", "el", "en", "en-GB", "en-US", "es", "es-MX", "et", "fi", "fr",
        "fr-CA", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "lt", "lv", "nb", "nl", "pl", "pt",
        "pt-BR", "ro", "ru", "sk", "sl", "sr", "sv", "th", "tr", "uk", "vi", "zh", "zh-Hans", "zh-Hant"
    ]

    func appendLog(_ message: String) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        exportFileURL = nil
        results.removeAll()
        statuses = Dictionary(uniqueKeysWithValues: languages.map { ($0, .pending) })
        logs.removeAll(keepingCapacity: false)

        appendLog("Starting fetch for \(languages.count) languages…")

        let previousLanguages = Locale.preferredLanguages
        do {
            try await service.prepareGeocodedItems(preferredLocale: Locale(identifier: previousLanguages.first ?? "en"))
        } catch {
            appendLog("Geocoding warning: \(error.localizedDescription)")
        }

        for language in languages {
            statuses[language] = .running
            appendLog("Language \(language): Switching locale…")
            LocaleSwitcher.setAppleLanguages([language])
            await LocaleSwitcher.waitForPropagation()
            appendLog("Language \(language): Starting directions…")

            var attempt = 0
            var lastError: Error?
            while attempt < 2 {
                attempt += 1
                do {
                    let result = try await service.fetchRoute(for: language)
                    results[language] = result
                    statuses[language] = result.languageSuspect ? .warn : .ok
                    appendLog("Language \(language): \(result.steps.count) steps (suspicious: \(result.languageSuspect ? "yes" : "no"))")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    appendLog("Language \(language) attempt \(attempt) failed: \(error.localizedDescription)")
                    if attempt < 2 {
                        appendLog("Language \(language): retrying in 1s…")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }

            if let lastError {
                statuses[language] = .fail(lastError.localizedDescription)
            }
        }

        LocaleSwitcher.setAppleLanguages(previousLanguages)
        await LocaleSwitcher.waitForPropagation()
        appendLog("AppleLanguages reset (\(previousLanguages.first ?? "System default"))")

        isRunning = false
    }

    func exportJSON() {
        guard !results.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)

            let fileName = "RouteInstructions-\(Int(Date().timeIntervalSince1970)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName, conformingTo: .json)
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            appendLog("JSON exported: \(fileName)")
        } catch {
            appendLog("Export failed: \(error.localizedDescription)")
        }
    }

    var statusRows: [(String, Status)] {
        languages.map { ($0, statuses[$0] ?? .pending) }
    }

    var completedCount: Int {
        statusRows.reduce(0) { partialResult, row in
            partialResult + (row.1.isTerminal ? 1 : 0)
        }
    }

    var progressValue: Double {
        guard !languages.isEmpty else { return 0 }
        return Double(completedCount) / Double(languages.count)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ViewModel()
    @StateObject private var overlayViewModel = NavigationOverlayViewModel()
    @State private var demoIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                overlayDemoSection
                controlSection
                progressSection
                statusSection
                logSection
            }
            .padding()
            .navigationTitle("Route Instruction Exporter")
            .toolbar {
                if let url = viewModel.exportFileURL {
                    ShareLink(item: url, preview: SharePreview("RouteInstructions.json", icon: Image(systemName: "map"))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                setDemoInstruction()
            }
            .onReceive(overlayViewModel.$symbol.compactMap { $0 }) { symbol in
                triggerHaptic(for: symbol)
            }
        }
    }

    private var overlayDemoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NavigationOverlayKit Demo")
                .font(.headline)

            NavigationOverlayView(viewModel: overlayViewModel, alignment: .top)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: advanceDemoInstruction) {
                Label("Next Instruction (Haptic)", systemImage: "waveform.path")
            }
            .buttonStyle(.bordered)
        }
    }

    private func advanceDemoInstruction() {
        demoIndex = (demoIndex + 1) % demoSymbols.count
        setDemoInstruction()
    }

    private func setDemoInstruction() {
        let symbol = demoSymbols[demoIndex]
        let instruction = NavigationInstruction(
            text: demoInstructionText(for: symbol),
            distance: Measurement(value: 120, unit: UnitLength.meters),
            symbol: symbol
        )
        overlayViewModel.update(with: instruction)
    }

    private var demoSymbols: [NavigationInstruction.Symbol] {
        [.start, .straight, .slightRight, .right, .sharpRight, .slightLeft, .left, .sharpLeft, .uTurn, .arrive]
    }

    private func demoInstructionText(for symbol: NavigationInstruction.Symbol) -> String {
        switch symbol {
        case .start:
            return "Start route"
        case .straight:
            return "Continue straight"
        case .slightRight:
            return "Slight right"
        case .right:
            return "Turn right"
        case .sharpRight:
            return "Sharp right"
        case .slightLeft:
            return "Slight left"
        case .left:
            return "Turn left"
        case .sharpLeft:
            return "Sharp left"
        case .uTurn:
            return "Make a U-turn"
        case .arrive:
            return "Arrive at destination"
        case .cross:
            return "Cross the street"
        case .tunnel:
            return "Enter tunnel"
        case .bridge:
            return "Cross bridge"
        case .stairs:
            return "Use stairs"
        case .escalator:
            return "Take escalator"
        }
    }

    private func triggerHaptic(for symbol: NavigationInstruction.Symbol) {
        let generator: UIImpactFeedbackGenerator
        switch symbol {
        case .uTurn, .arrive:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        case .left, .right, .sharpLeft, .sharpRight:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .slightLeft, .slightRight:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .start, .straight, .cross, .tunnel, .bridge, .stairs, .escalator:
            generator = UIImpactFeedbackGenerator(style: .soft)
        }
        generator.impactOccurred()
    }

    private var controlSection: some View {
        HStack {
            Button(action: { Task { await viewModel.runAll() } }) {
                Label("Fetch All Languages", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning)

            Spacer()

            Button(action: viewModel.exportJSON) {
                Label("Export JSON", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.results.isEmpty)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: viewModel.progressValue, total: 1.0)
                .progressViewStyle(.linear)
            Text("Progress: \(viewModel.completedCount) / \(viewModel.languages.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.languages, id: \.self) { language in
                    StatusRowView(
                        language: language,
                        status: viewModel.statuses[language] ?? .pending
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 280)
    }

    private var logSection: some View {
        GroupBox("Log") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 140, maxHeight: 220)
        }
    }
}

private struct StatusRowView: View {
    let language: String
    let status: ViewModel.Status

    var body: some View {
        HStack {
            Text(language)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(status.icon)
            Text(status.message)
                .foregroundColor(status.tint)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

private extension ViewModel.Status {
    var icon: String {
        switch self {
        case .pending: return "⏳"
        case .running: return "🔄"
        case .ok: return "✅"
        case .warn: return "⚠️"
        case .fail: return "❌"
        }
    }

    var message: String {
        switch self {
        case .pending:
            return "Waiting…"
        case .running:
            return "running"
        case .ok:
            return "done"
        case .warn:
            return "done (check language)"
        case let .fail(message):
            return "Error: \(message)"
        }
    }

    var tint: Color {
        switch self {
        case .pending, .running:
            return .secondary
        case .ok:
            return .green
        case .warn:
            return .orange
        case .fail:
            return .red
        }
    }
}
