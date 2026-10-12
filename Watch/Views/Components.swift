import SwiftUI

/// 用表冠调节数值的输入框：点一下选中，然后转表冠，每格跳到下一档
struct CrownField<Field: Hashable>: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    var focus: FocusState<Field?>.Binding
    let field: Field

    /// 表冠的原始值：转动过程中会经过两档之间的小数，只在内部使用
    @State private var crownValue: Double = 0

    private var isFocused: Bool { focus.wrappedValue == field }

    /// 对齐到最近的一档（以 range 下限为起点，按 step 分档）
    private func snap(_ raw: Double) -> Double {
        let steps = ((raw - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + steps * step
        return (min(max(snapped, range.lowerBound), range.upperBound) * 1000).rounded() / 1000
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(isFocused ? Theme.accent : .secondary)
                .lineLimit(1)
            Text(format(value))
                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .glassEffect(isFocused ? .regular.tint(Theme.beige.opacity(0.35)) : .regular, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isFocused ? Theme.accent : .clear, lineWidth: 1.5))
        .focusable(true)
        .focusEffectDisabled()
        .focused(focus, equals: field)
        .digitalCrownRotation($crownValue, from: range.lowerBound, through: range.upperBound, by: step,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { crownValue = value }
        // 显示和记录的都是对齐后的档位，不会出现 20.99 这种中间值
        .onChange(of: crownValue) { _, raw in
            let snapped = snap(raw)
            if snapped != value { value = snapped }
        }
        // 外部改了数值（例如预填、编辑）时，让表冠从新数值开始转
        .onChange(of: value) { _, newValue in
            if snap(crownValue) != newValue { crownValue = newValue }
        }
        .onTapGesture { focus.wrappedValue = field }
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snap(value + step)
            case .decrement: value = snap(value - step)
            @unknown default: break
            }
        }
    }
}

extension View {
    /// 米色玻璃主按钮
    func beigeGlassButton() -> some View {
        buttonStyle(.glassProminent).tint(Theme.beige).foregroundStyle(Theme.onBeige)
    }

    /// 手表页面顶部淡淡的米色光晕
    func warmContainerBackground() -> some View {
        containerBackground(Theme.beige.opacity(0.22).gradient, for: .navigation)
    }
}

/// 支持双指互点（Double Tap）触发主按钮
struct PrimaryActionShortcut: ViewModifier {
    func body(content: Content) -> some View {
        content.handGestureShortcut(.primaryAction)
    }
}

/// 休息倒计时的小条，点开看大号倒计时
struct RestMiniRow: View {
    @EnvironmentObject private var timer: RestTimer
    @State private var showTimer = false

    var body: some View {
        if timer.isRunning || timer.isFinished {
            Button {
                showTimer = true
            } label: {
                HStack {
                    Image(systemName: timer.isFinished ? "bell.fill" : "timer")
                    if timer.isFinished {
                        Text("休息结束")
                    } else if let end = timer.endDate {
                        Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(timer.isFinished ? "知道了" : "休息中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(timer.isFinished ? Theme.warmup : Theme.accent)
            }
            .sheet(isPresented: $showTimer) {
                RestTimerView { showTimer = false }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
