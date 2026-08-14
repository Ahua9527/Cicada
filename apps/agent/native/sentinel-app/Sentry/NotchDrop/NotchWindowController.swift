//
//  NotchWindowController.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine

class NotchWindowController: NSWindowController {
    var vm: NotchViewModel?
    weak var screen: NSScreen?

    var openAfterCreate: Bool = false

    private var cancellables: Set<AnyCancellable> = []
    /// 收起后的延迟缩窗任务;延迟期内状态再次变化则取消。
    private var shrinkWorkItem: DispatchWorkItem?

    /// 收起弹簧(`vm.animation` 0.5s + 0.25 回弹)播完再缩窗,避免面板被窗口边界裁切。
    private static let shrinkDelay: TimeInterval = 0.7

    // MARK: - 窗口几何

    /// 刘海窗口只包住当前交互区,不用全屏宽 frame 横贯屏幕顶部——旧实现是
    /// 1512×200 的透明无边框窗口(AppKit 按窗口 frame 路由鼠标事件,透明区域同样
    /// 吞点击),会把其下方所有窗口的顶部一条变成死区(控制中心侧栏上方几行点不动
    /// 即此因)。窗口透明无边框,frame 瞬变不可见;SwiftUI 内容在窗口内顶部居中,
    /// 两种 frame 下可视内容落在与旧全宽窗口完全相同的屏幕区域。
    /// (AppKit 坐标:origin 左下,y 向上;刘海窗口永远贴屏幕顶边。)

    /// 关闭/Peek 态:包住刘海本体 + 拖放探测区(dropDetectorRange)。
    static func compactFrame(screenFrame: CGRect, notchRect: CGRect, dropRange: CGFloat) -> CGRect {
        let size = CGSize(width: notchRect.width + dropRange, height: notchRect.height + dropRange)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// 打开态:包住 600×160 面板 + 32 圆角 + 16 阴影。
    static func openedFrame(screenFrame: CGRect, openedSize: CGSize) -> CGRect {
        let size = CGSize(width: openedSize.width + 100, height: 200)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    init(window: NSWindow, screen: NSScreen) {
        self.screen = screen

        super.init(window: window)

        var notchSize = screen.notchSize

        let vm = NotchViewModel(inset: notchSize == .zero ? 0 : -4)
        self.vm = vm
        contentViewController = NotchViewController(vm)

        if notchSize == .zero {
            notchSize = .init(width: 150, height: 28)
        }
        vm.deviceNotchRect = CGRect(
            x: screen.frame.origin.x + (screen.frame.width - notchSize.width) / 2,
            y: screen.frame.origin.y + screen.frame.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        window.setFrame(
            Self.compactFrame(
                screenFrame: screen.frame,
                notchRect: vm.deviceNotchRect,
                dropRange: vm.dropDetectorRange
            ),
            display: false
        )
        window.makeKeyAndOrderFront(nil)

        // 窗口跟随面板状态收放:打开立即放大(容纳面板与阴影,且保证进行中的
        // 拖放/点击落进窗口);关闭延迟缩小(等收起动画播完,期间重新打开则取消)。
        vm.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak vm] status in
                guard let self, let vm, let window = self.window, let screen = self.screen else { return }
                shrinkWorkItem?.cancel()
                shrinkWorkItem = nil
                switch status {
                case .opened:
                    let frame = Self.openedFrame(screenFrame: screen.frame, openedSize: vm.notchOpenedSize)
                    if window.frame != frame { window.setFrame(frame, display: false) }
                case .popping:
                    let frame = Self.compactFrame(
                        screenFrame: screen.frame,
                        notchRect: vm.deviceNotchRect,
                        dropRange: vm.dropDetectorRange
                    )
                    if window.frame != frame { window.setFrame(frame, display: false) }
                case .closed:
                    let item = DispatchWorkItem { [weak self, weak vm] in
                        guard let self, let vm, let window = self.window, let screen = self.screen else { return }
                        let frame = Self.compactFrame(
                            screenFrame: screen.frame,
                            notchRect: vm.deviceNotchRect,
                            dropRange: vm.dropDetectorRange
                        )
                        if window.frame != frame { window.setFrame(frame, display: false) }
                    }
                    shrinkWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: item)
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak vm] in
            vm?.screenRect = screen.frame
            if self.openAfterCreate { vm?.notchOpen(.boot) }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    convenience init(screen: NSScreen) {
        let window = NotchWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.init(window: window, screen: screen)
    }

    deinit {
        destroy()
    }

    func destroy() {
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil
        cancellables.removeAll()
        vm?.destroy()
        vm = nil
        window?.close()
        contentViewController = nil
        window = nil
    }
}
