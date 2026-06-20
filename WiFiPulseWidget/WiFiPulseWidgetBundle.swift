//
//  WiFiPulseWidgetBundle.swift
//  WiFiPulseWidget
//
//  Created by Adi Sapir on 19/06/2026.
//

import WidgetKit
import SwiftUI

@main
struct WiFiPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        WiFiPulseWidget()
        WiFiPulseWidgetControl()
    }
}
