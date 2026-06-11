//
//  FormView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import SwiftUI

struct FormView<Content: View, LeftBottomView: View>: View {
    let title: LocalizedStringKey

    @ViewBuilder let formBody: () -> Content
    @ViewBuilder let leftBottom: () -> LeftBottomView

    init(
        title: LocalizedStringKey,
        typeTrick: LeftBottomView = EmptyView(),
        @ViewBuilder formBody: @escaping () -> Content
    ) {
        self.title = title
        self.formBody = formBody
        leftBottom = { typeTrick }
    }

    init(
        title: LocalizedStringKey,
        @ViewBuilder leftBottom: @escaping () -> LeftBottomView,
        @ViewBuilder formBody: @escaping () -> Content
    ) {
        self.title = title
        self.formBody = formBody
        self.leftBottom = leftBottom
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
                    .bold()
                Spacer()
            }
            Divider().padding(.horizontal, -16)
            formBody()
            Divider().padding(.horizontal, -16)
            HStack {
                leftBottom()
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(.background)
    }
}
