//
//  AppIntent.swift
//  WiFiPulseWidget
//
//  Created by Adi Sapir on 19/06/2026.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Speed Display" }
    static var description: IntentDescription { "Choose how WiFiPulse displays network throughput." }

    @Parameter(title: "Unit", default: .bytes)
    var unit: WidgetSpeedUnit
}

enum WidgetSpeedUnit: String, AppEnum {
    case bytes
    case bits

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Speed Unit")
    static var caseDisplayRepresentations: [WidgetSpeedUnit: DisplayRepresentation] = [
        .bytes: "Bytes per second",
        .bits: "Bits per second"
    ]
}
