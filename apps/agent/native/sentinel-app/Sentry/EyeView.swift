//
//  EyeView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import SwiftUI

struct EyeView: View {
    @State private var isRotating = false
    @State private var isPulsing = false
    @State private var pupilScale = 1.0

    var body: some View {
        ZStack {
            // 外层圆形边框
            Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 8)
                .frame(width: 200, height: 200)

            // 主要虹膜区域
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.red.opacity(0.8),
                            Color.orange,
                            Color.red.opacity(0.9),
                        ]),
                        center: .center,
                        startRadius: 30,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)

            // 放射状纹理线条
            ForEach(0 ..< 36, id: \.self) { index in
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 1, height: 80)
                    .offset(y: -40)
                    .rotationEffect(.degrees(Double(index) * 10))
            }
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isRotating)

            // 内层放射状纹理
            ForEach(0 ..< 24, id: \.self) { index in
                Rectangle()
                    .fill(Color.red.opacity(0.4))
                    .frame(width: 0.5, height: 50)
                    .offset(y: -25)
                    .rotationEffect(.degrees(Double(index) * 15))
            }

            // 中央瞳孔
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.black,
                            Color.red.opacity(0.2),
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .scaleEffect(pupilScale)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pupilScale)

            // 瞳孔中心反光点
            Circle()
                .fill(Color.red.opacity(0.6))
                .frame(width: 8, height: 8)
        }
        .clipShape(Circle())
        .onAppear {
            isRotating = true
            pupilScale = 0.8
            isPulsing = true
        }
        .frame(width: 200, height: 200)
    }
}

#Preview {
    EyeView()
        .frame(width: 250, height: 250)
}
