/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * PersonLocationSnippetView.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import SwiftUI

struct PersonLocationSnippetView: View {
    let location: IntentPersonLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(location.displayName, systemImage: "location.fill")
                .font(.headline)
            Text(location.placeDescription ?? NSLocalizedString("intent_location_fallback_place", comment: "Fallback place description for the last known location"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String.localizedStringWithFormat(
                NSLocalizedString("intent_person_location_snippet_age_format", comment: "Snippet age format. Argument: age text."),
                location.ageText
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
