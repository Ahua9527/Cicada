import SwiftUI

/// SleepHold 数据卡片矩阵：HStack + ForEach(cells) SleepHoldCell。
struct SleepHoldCells: View {
    @ObservedObject var model: SleepHoldModel

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s3) {
            ForEach(model.cells) { cell in
                SleepHoldCell(cell: cell)
            }
        }
    }
}

#Preview {
    SleepHoldCells(model: SleepHoldModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 600)
}