//
//  MouseLocation.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine
import SwiftUI

class MouseLocation: ObservableObject {
    static let shared = MouseLocation()

    private var mouseMoveEvent: MouseEventMonitor!

    @Published var mouseLocation: UnitPoint = .init(x: 0.5, y: 0.5)

    private init() {
        mouseMoveEvent = MouseEventMonitor(mask: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.main?.visibleFrame ?? .zero
            let x = (mouseLocation.x - screen.minX) / screen.width
            let y = (mouseLocation.y - screen.minY) / screen.height
            let clampedX = min(max(x, 0.0), 1.0)
            let clampedY = min(max(y, 0.0), 1.0)
            let value = UnitPoint(x: clampedX, y: clampedY)
            self.mouseLocation = value
        }
        mouseMoveEvent.start()
    }
}
