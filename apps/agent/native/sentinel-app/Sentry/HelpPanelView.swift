//
//  HelpPanelView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import Foundation
import SwiftUI

struct HelpPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("**Sentry** adds a feature that detects and responds to potential theft or unauthorized access when you leave your Mac.")
            Text("Once set up, Sentry will **automatically activate** when you **lock** your device.")
            Divider().padding(.horizontal, -10)
            Text("When a selected trigger occurs, Sentry will either play a sound or send you a notification.")
            Text("Available triggers include:")
                .bold()
            Text("1. Closing your Mac's lid.")
            Text("2. Disconnecting from the internet.")
            Text("3. Disconnecting the power adapter.")
            Divider().padding(.horizontal, -10)
            Text("Location based detection is not available, you should setup **Find My Mac** instead.")
            Text("Additionally, you can set up **Camera Recording**. When using camera recordings, please respect others' privacy.")
            Divider().padding(.horizontal, -10)
            Text("Sentry will not prevent your Mac from being stolen or damaged, but it can help you locate your Mac or identify the troublemaker.")
        }
        .frame(width: 400)
        .padding(10)
    }
}
