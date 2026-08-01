//
//  DeadlineWidgetBundle.swift
//  DeadlineWidget
//
//  Created by Сергей Родоманюк on 05.02.2026.
//

import WidgetKit
import SwiftUI

@main
struct DeadlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeadlineWidget()
        CriticalCountdownWidget()
        DeadlineLiveActivityWidget()
    }
}
