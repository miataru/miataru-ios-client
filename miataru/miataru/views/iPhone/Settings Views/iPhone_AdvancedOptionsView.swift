/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_AdvancedOptionsView.swift
 * miataru
 *
 * Created by Codex on 14.03.26.
 */

import SwiftUI

struct iPhone_AdvancedOptionsView: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Form {
            if settings.trackAndReportLocation {
                Section(header: Text("activity_type_accuracy_settings_title")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("activity_type_tracking_accuracy_title")
                            .font(.headline)
                        Picker("", selection: $settings.locationActivityType) {
                            Text("activity_type_other").tag(0)
                            Text("activity_type_fitness").tag(2)
                            Text("activity_type_automotive").tag(1)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("activity_type_accuracy_explanation")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("location_sensitivity_title")
                            .font(.headline)
                        Picker("", selection: $settings.locationSensitivityLevel) {
                            Text("location_tracking_update_sensitivity_very_sensitive_short").tag(1)
                            Text("location_tracking_update_sensitivity_default_short").tag(2)
                            Text("location_tracking_update_sensitivity_balanced_short").tag(3)
                            Text("location_tracking_update_sensitivity_battery_saver_short").tag(4)
                            Text("location_tracking_update_sensitivity_minimal_short").tag(5)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("location_sensitivity_explanation")
                }

                Section(header: Text("background_location_updates_section_title")) {
                    Toggle("frequent_background_location_updates_title", isOn: $settings.frequentBackgroundLocationUpdatesEnabled)
                        .accessibilityIdentifier("settings_frequent_background_location_updates_toggle")
                    SettingsDescriptionText("frequent_background_location_updates_explanation")

                    if settings.frequentBackgroundLocationUpdatesEnabled {
                        SettingsWarningText("frequent_background_location_updates_battery_warning")

                        Picker("background_location_distance_filter_title", selection: $settings.frequentBackgroundLocationDistanceFilter) {
                            Text("100m").tag(100)
                            Text("50m").tag(50)
                            Text("25m").tag(25)
                        }

                        Picker("frequent_background_location_updates_duration_title", selection: $settings.frequentBackgroundLocationUpdateDuration) {
                            Text("1hour").tag(FrequentBackgroundLocationUpdateDuration.oneHour.rawValue)
                            Text("4hours").tag(FrequentBackgroundLocationUpdateDuration.fourHours.rawValue)
                            Text("12hours").tag(FrequentBackgroundLocationUpdateDuration.twelveHours.rawValue)
                            Text("24hours").tag(FrequentBackgroundLocationUpdateDuration.twentyFourHours.rawValue)
                            Text("frequent_background_location_updates_duration_unlimited").tag(FrequentBackgroundLocationUpdateDuration.unlimited.rawValue)
                        }
                    }
                }
            }

            Section(header: Text("app_behaviour")) {
                Toggle("pulsating_map_markers", isOn: $settings.pulsingMapMarkers)
                    .accessibilityIdentifier("settings_pulsing_map_markers_toggle")
                SettingsDescriptionText("explanation_pulsating_map_markers")

                Toggle("indicate_location_accuracy", isOn: $settings.indicateAccuracyOnMap)
                SettingsDescriptionText("explanation_indicate_location_accuracy")

                Toggle("show_offscreen_arrows_for_other_devices", isOn: $settings.showOffscreenArrowsForOtherDevices)
                SettingsDescriptionText("explanation_show_offscreen_arrows_for_other_devices")

                Toggle("auto_refresh_device_list", isOn: $settings.autoRefreshDeviceList)
                SettingsDescriptionText("explanation_auto_refresh_device_list")

                Toggle("show_current_speed_on_map", isOn: $settings.showCurrentSpeedOnMap)
                SettingsDescriptionText("explanation_show_current_speed_on_map")

                Picker("location_update_outbox_retention_title", selection: $settings.locationUpdateOutboxRetentionMode) {
                    Text("location_update_outbox_retention_24h").tag(LocationUpdateOutboxRetentionMode.twentyFourHours.rawValue)
                    Text("location_update_outbox_retention_7d").tag(LocationUpdateOutboxRetentionMode.sevenDays.rawValue)
                    Text("location_update_outbox_retention_30d").tag(LocationUpdateOutboxRetentionMode.thirtyDays.rawValue)
                    Text("location_update_outbox_retention_unlimited").tag(LocationUpdateOutboxRetentionMode.unlimited.rawValue)
                }

                Picker("location_update_outbox_max_items_title", selection: $settings.locationUpdateOutboxMaxItems) {
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text("2500").tag(2500)
                    Text("5000").tag(5000)
                    Text("10000").tag(10_000)
                }
                SettingsDescriptionText("explanation_location_update_outbox_policy")
            }

            Section(header: Text("map_configuration")) {
                Picker("map_update_interval", selection: $settings.mapUpdateInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                SettingsDescriptionText("explanation_map_update_interval")

                Picker("outside_map_update_interval", selection: $settings.outsideMapUpdateInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                SettingsDescriptionText("explanation_outside_map_update_interval")

                Toggle("zoom_to_fit_for_groups", isOn: $settings.groupsZoomToFit)
                SettingsDescriptionText("explanation_zoom_to_fit_for_groups")

                Picker("reverse_geocoding_threshold", selection: $settings.reverseGeocodingThresholdMeters) {
                    Text("reverse_geocode_every_update").tag(0)
                    Text("100m").tag(100)
                    Text("1000m").tag(1000)
                    Text("10km").tag(10_000)
                }
                SettingsDescriptionText("explanation_reverse_geocoding_threshold")
            }

            Section(header: Text("navigation")) {
                Toggle("navigation_auto_route_update", isOn: $settings.automaticRouteUpdateDuringNavigation)
                SettingsDescriptionText("explanation_navigation_auto_route_update")

                Toggle("show_route_progress", isOn: $settings.showRouteProgress)
                SettingsDescriptionText("explanation_show_route_progress")
            }
        }
        .navigationTitle("advanced_options")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen_settings_advanced_options")
    }
}

#Preview {
    iPhone_AdvancedOptionsView()
}
