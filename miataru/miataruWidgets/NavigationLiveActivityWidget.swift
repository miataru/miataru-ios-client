/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationLiveActivityWidget.swift
 * miataruWidgets
 */

import ActivityKit
import SwiftUI
import WidgetKit

struct NavigationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationLiveActivityAttributes.self) { context in
            NavigationLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.attributes.navigationURL(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NavigationLiveActivityPrimaryIcon(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NavigationLiveActivityETAView(arrivalDate: context.state.estimatedArrivalDate)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.deviceDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLiveActivityContextDetail(state: context.state)
                        HStack(spacing: 10) {
                            Text(NavigationLiveActivityFormatting.distance(context.state.distanceMeters))
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Spacer(minLength: 4)
                            NavigationLiveActivityArrivalView(date: context.state.estimatedArrivalDate)
                            NavigationLiveActivityFreshnessIndicator(
                                state: context.state,
                                activityIsStale: context.isStale
                            )
                        }
                    }
                }
            } compactLeading: {
                NavigationLiveActivityPrimaryIcon(state: context.state)
            } compactTrailing: {
                Text(NavigationLiveActivityFormatting.distance(
                    context.state.isFocusedNavigation
                        ? context.state.maneuverDistanceMeters ?? context.state.distanceMeters
                        : context.state.distanceMeters
                ))
                    .font(.caption.weight(.semibold).monospacedDigit())
            } minimal: {
                NavigationLiveActivityPrimaryIcon(state: context.state)
            }
            .widgetURL(context.attributes.navigationURL(for: context.state))
            .keylineTint(.accentColor)
        }
    }
}

private struct NavigationLiveActivityLockScreenView: View {
    let context: ActivityViewContext<NavigationLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLiveActivityPrimaryIcon(state: context.state)
                Text(context.attributes.deviceDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                NavigationLiveActivityFreshnessIndicator(
                    state: context.state,
                    activityIsStale: context.isStale,
                    showsText: true
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(NavigationLiveActivityFormatting.distance(context.state.distanceMeters))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                NavigationLiveActivityETAView(arrivalDate: context.state.estimatedArrivalDate)
                    .font(.headline.monospacedDigit())
                Text("·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                NavigationLiveActivityArrivalView(date: context.state.estimatedArrivalDate)
                    .font(.headline.monospacedDigit())
            }

            NavigationLiveActivityContextDetail(state: context.state)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

private struct NavigationLiveActivityPrimaryIcon: View {
    let state: NavigationLiveActivityAttributes.ContentState

    var body: some View {
        NavigationLiveActivityTransportIcon(
            symbolName: state.isFocusedNavigation
                ? state.maneuverSymbolName ?? state.transportSymbolName
                : state.transportSymbolName
        )
    }
}

private struct NavigationLiveActivityContextDetail: View {
    let state: NavigationLiveActivityAttributes.ContentState

    var body: some View {
        if state.isFocusedNavigation,
           let instruction = state.maneuverInstruction,
           let symbolName = state.maneuverSymbolName {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                if let distanceMeters = state.maneuverDistanceMeters {
                    Text(NavigationLiveActivityFormatting.distance(distanceMeters))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }
                Text(instruction)
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        } else if !state.isFocusedNavigation,
                  let location = state.remoteLocationDescription {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct NavigationLiveActivityTransportIcon: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.headline)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

private struct NavigationLiveActivityETAView: View {
    let arrivalDate: Date

    var body: some View {
        Text(timerInterval: Date.now...max(arrivalDate, Date.now), countsDown: true)
            .lineLimit(1)
            .accessibilityLabel(Text("live_activity_eta", tableName: "Localizable"))
    }
}

private struct NavigationLiveActivityArrivalView: View {
    let date: Date

    var body: some View {
        Text(date, style: .time)
            .lineLimit(1)
            .accessibilityLabel(Text("live_activity_arrival", tableName: "Localizable"))
    }
}

private struct NavigationLiveActivityFreshnessIndicator: View {
    let state: NavigationLiveActivityAttributes.ContentState
    let activityIsStale: Bool
    var showsText = false

    private var localizationKey: LocalizedStringKey? {
        if activityIsStale || state.remoteLocationIsStale {
            return "live_activity_update_delayed"
        }
        if state.ownLocationIsStale {
            return "live_activity_own_location_stale"
        }
        return nil
    }

    var body: some View {
        if let localizationKey {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                if showsText {
                    Text(localizationKey, tableName: "Localizable")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.orange)
            .accessibilityLabel(Text(localizationKey, tableName: "Localizable"))
        }
    }
}

private enum NavigationLiveActivityFormatting {
    static func distance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = meters < 1_000 ? 0 : 1
        return formatter.string(from: Measurement(value: max(0, meters), unit: UnitLength.meters))
    }
}
