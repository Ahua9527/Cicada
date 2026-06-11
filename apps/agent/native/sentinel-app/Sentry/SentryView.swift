//
//  SentryView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import ColorfulX
import SwiftUI

struct SentryView: View {
    @StateObject var sentry: Sentry

    @State var globalOpacity: Double = 0
    @State var showEye = false

    var body: some View {
        HStack {
            texts
            Spacer()
            Divider().hidden()
            eye
        }
        .frame(width: 700, height: 400, alignment: .center)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                globalOpacity = 1
                showEye = true
            }
        }
        .foregroundStyle(sentry.isAlrming ? .white : .primary)
        .background(
            ZStack {
                if sentry.isAlrming {
                    ColorfulView(color: .sunset, noise: .constant(64))
                        .transition(.opacity)
                        .ignoresSafeArea()
                }
            }
        )
        .animation(.interactiveSpring(), value: sentry.isAlrming)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(globalOpacity)
        .animation(.easeInOut(duration: 1), value: globalOpacity)
    }

    var texts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "eye.fill")
                .bold()
                .font(.largeTitle)
                .opacity(0.2)
            Spacer()
            Text("Sentry Activated")
                .bold()
                .font(.largeTitle)
            Text("This Mac is connected to the internet and is monitoring your behavior.")
                .bold()
        }
        .padding(32)
    }

    var eye: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 10, height: 888)
            if showEye {
                EyeView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 2), value: showEye)
        .frame(width: 200)
        .padding(32)
    }
}

#Preview {
    let s = Sentry(configuration: .init(), onAlarmingActivaty: { _ in })
    return SentryView(sentry: s)
        .onAppear { s.isAlrming = true }
        .frame(width: 700, height: 400)
}
