import SwiftUI

/// 记完一组后弹出：选休息时长（该动作上次用的时长会高亮），点一下开始倒计时
struct RestPanelView: View {
    let exercise: Exercise
    let newRecords: [PRKind]
    let onStart: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.restPresets) private var presetsRaw = AppSettings.encodePresets(AppSettings.defaultPresets)
    @AppStorage(SettingsKey.defaultRest) private var defaultRest = 120
    @State private var started = false
    @State private var showCustom = false

    private var remembered: Int { exercise.lastRestSeconds ?? defaultRest }

    private var options: [Int] {
        var list = AppSettings.decodePresets(presetsRaw)
        if !list.contains(remembered) { list.insert(remembered, at: 0) }
        return list
    }

    var body: some View {
        if started {
            RestTimerView { dismiss() }
        } else {
            chooser
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 8) {
                if !newRecords.isEmpty {
                    VStack(spacing: 2) {
                        Text("🏆 新纪录！").font(.headline).foregroundStyle(Theme.gold)
                        Text(newRecords.map(\.displayName).joined(separator: " · "))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .glassEffect(.regular.tint(Theme.gold.opacity(0.3)), in: .rect(cornerRadius: 14))
                }

                Text("组间休息").font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(options, id: \.self) { seconds in
                        Button {
                            start(seconds)
                        } label: {
                            Text(Fmt.clock(seconds))
                                .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(seconds == remembered ? Theme.onBeige : .white)
                                .glassEffect(seconds == remembered ? .regular.tint(Theme.beige).interactive() : .regular.interactive(),
                                             in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showCustom = true
                    } label: {
                        Text("自定义")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                Button("不休息") { dismiss() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showCustom) {
            CustomRestView(initial: remembered) { seconds in
                showCustom = false
                start(seconds)
            }
        }
    }

    private func start(_ seconds: Int) {
        onStart(seconds)
        started = true
    }
}

/// 大号倒计时
struct RestTimerView: View {
    let onClose: () -> Void

    @EnvironmentObject private var timer: RestTimer
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        VStack(spacing: 8) {
            if timer.isFinished {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.title)
                    .foregroundStyle(Theme.warmup)
                Text("休息结束").font(.title3.weight(.semibold))
                Text("开始下一组！").foregroundStyle(.secondary)
                Button("好") {
                    timer.stop()
                    onClose()
                }
                .beigeGlassButton()
                .modifier(PrimaryActionShortcut())
            } else if let end = timer.endDate {
                let start = end.addingTimeInterval(-TimeInterval(max(timer.totalSeconds, 1)))
                Text("休息").font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isDimmed ? .secondary : Theme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                ProgressView(timerInterval: min(start, Date.now)...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Theme.beige)
                if !isDimmed {
                    HStack {
                        Button("−15秒") { timer.adjust(by: -15) }
                        Button("+15秒") { timer.adjust(by: 15) }
                    }
                    .font(.caption)
                    .buttonStyle(.glass)
                    Button("结束休息") {
                        timer.stop()
                        onClose()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("没有进行中的休息")
                Button("关闭") { onClose() }
            }
        }
    }
}

/// 用表冠选择自定义休息时长（15 秒一档）
struct CustomRestView: View {
    let onStart: (Int) -> Void
    @State private var seconds: Double
    @FocusState private var focused: Bool

    /// 对齐到 15 秒一档
    private var snapped: Int { Int((seconds / 15).rounded()) * 15 }

    init(initial: Int, onStart: @escaping (Int) -> Void) {
        self.onStart = onStart
        _seconds = State(initialValue: Double(initial))
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("自定义休息").font(.caption).foregroundStyle(.secondary)
            Text(Fmt.clock(snapped))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .focusable(true)
                .focused($focused)
                .digitalCrownRotation($seconds, from: 15, through: 900, by: 15, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
            HStack {
                Button("−") { seconds = max(15, seconds - 15) }
                Button("+") { seconds = min(900, seconds + 15) }
            }
            .buttonStyle(.glass)
            Button("开始") { onStart(snapped) }
                .beigeGlassButton()
        }
        .onAppear { focused = true }
    }
}
