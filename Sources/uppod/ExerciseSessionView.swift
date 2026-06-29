import AppKit
import SwiftUI

private enum ExerciseColors {
    static let green = Theme.good                          // shared posture-good / primary-action color
    static let blue = Color(red: 0.18, green: 0.45, blue: 0.90)   // gauge "right/up" target (local)
    static let coral = Color(red: 0.92, green: 0.32, blue: 0.27)  // gauge "left/down" target (local)
    static let surface = Color.primary.opacity(0.055)
    static let hairline = Color.primary.opacity(0.10)
}

struct ExerciseSessionView: View {
    @ObservedObject var engine: ExerciseEngine

    var body: some View {
        Group {
            switch engine.phase {
            case .ready:   readyView
            case .active:  activeView
            case .resting: restView
            case .done:    doneView
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 34)
        .padding(.bottom, 26)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Ready

    private var readyView: some View {
        VStack(spacing: 12) {
            topBar(showTimer: false)

            VStack(spacing: 20) {
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Boyun egzersizleri", "Neck exercises"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(L10n.text(
                            "AirPods hareket sensörleriyle takip edilen kısa ve kontrollü bir seans.",
                            "A short, controlled session tracked by AirPods motion sensors."
                        ))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    coachBust(for: ExerciseLibrary.flexionExtension)
                }
                .frame(height: 190)

                exerciseList

                readyStartButton
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var exerciseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(ExerciseLibrary.all.enumerated()), id: \.element.id) { index, ex in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? .white : .secondary)
                        .frame(width: 24, height: 24)
                        .background(index == 0 ? ExerciseColors.green : Color.primary.opacity(0.08), in: Circle())
                    Text(L10n.exerciseName(id: ex.id, fallback: ex.name))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(ex.totalRepsLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                if index < ExerciseLibrary.all.count - 1 {
                    Divider().opacity(0.45)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ExerciseColors.hairline, lineWidth: 1)
        )
    }

    private var readyStartButton: some View {
        Button { engine.start() } label: {
            Label(L10n.text("Başla", "Start"), systemImage: "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(ExerciseColors.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: ExerciseColors.green.opacity(0.10), radius: 8, y: 3)
    }

    // MARK: Active

    private var activeView: some View {
        let ex = engine.currentExercise
        return VStack(spacing: 12) {
            topBar(showTimer: true)
            sessionMetaRow
            exerciseStepper

            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(ex.map { L10n.exerciseName(id: $0.id, fallback: $0.name) } ?? "")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(ex.map { L10n.exerciseInstruction(id: $0.id, fallback: $0.instruction) } ?? "")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    coachBust(for: ex)
                }
                .frame(height: 174)

                if ex?.axis == .chinTuck {
                    chinTuckCoach
                } else if let ex {
                    liveMotionGauge(ex: ex)
                }

                repetitionCounter(label: ex?.axis == .chinTuck ? L10n.text("Tutuş", "Hold") : L10n.text("Tekrar", "Rep"))
            }
            .frame(maxHeight: .infinity, alignment: .center)

            actionButtons(skipTitle: L10n.text("Atla", "Skip"), stopTitle: L10n.text("Durdur", "Stop"))
        }
    }

    private func liveMotionGauge(ex: Exercise) -> some View {
        let target = max(ex.targetDeg, 1)
        let maxAngle = max(target * 1.85, 40)

        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                gaugeLabel(value: -target, title: axisLabels(for: ex).left, color: ExerciseColors.coral)
                Spacer()
                gaugeLabel(value: 0, title: L10n.text("Nötr", "Neutral"), color: .secondary)
                Spacer()
                gaugeLabel(value: target, title: axisLabels(for: ex).right, color: ExerciseColors.blue)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let clamped = max(-maxAngle, min(maxAngle, engine.liveSignalDeg))
                let displayedValue = formatSigned(clamped)
                let markerX = xPosition(value: clamped, maxAngle: maxAngle, width: width)
                let bubbleX = min(max(markerX, 40), max(width - 40, 40))
                let leftTargetX = xPosition(value: -target, maxAngle: maxAngle, width: width)
                let rightTargetX = xPosition(value: target, maxAngle: maxAngle, width: width)
                let neutralX = xPosition(value: 0, maxAngle: maxAngle, width: width)

                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ExerciseColors.coral.opacity(0.12),
                                    Color.primary.opacity(0.035),
                                    ExerciseColors.blue.opacity(0.12)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(Capsule().stroke(ExerciseColors.hairline, lineWidth: 1))
                        .frame(height: 50)
                        .position(x: width / 2, y: 52)

                    ForEach(0..<49, id: \.self) { i in
                        let p = Double(i) / 48
                        let signal = (p * 2 - 1) * maxAngle
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(tickColor(signal: signal, target: target))
                            .frame(width: i % 12 == 0 ? 2.2 : 1.2, height: i % 12 == 0 ? 24 : 16)
                            .position(x: 24 + CGFloat(p) * max(width - 48, 1), y: 52)
                    }

                    gaugeMarker(color: ExerciseColors.coral.opacity(0.85), height: 34)
                        .position(x: leftTargetX, y: 52)
                    gaugeMarker(color: .secondary.opacity(0.72), height: 30)
                        .position(x: neutralX, y: 52)
                    gaugeMarker(color: ExerciseColors.blue.opacity(0.85), height: 34)
                        .position(x: rightTargetX, y: 52)

                    ZStack(alignment: .bottom) {
                        gaugeMarker(color: ExerciseColors.blue, height: 54)
                        Circle()
                            .fill(ExerciseColors.blue)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .frame(width: 17, height: 17)
                            .offset(y: 6)
                    }
                        .shadow(color: ExerciseColors.blue.opacity(0.22), radius: 5, y: 2)
                        .position(x: markerX, y: 52)
                        .animation(.easeOut(duration: 0.12), value: engine.liveSignalDeg)

                    Text(displayedValue)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(ExerciseColors.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .position(x: bubbleX, y: 14)
                        .animation(.easeOut(duration: 0.12), value: engine.liveSignalDeg)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
            .frame(height: 68)
        }
    }

    private var chinTuckCoach: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 9)
                Circle().trim(from: 0, to: CGFloat(engine.holdProgress))
                    .stroke(ExerciseColors.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: engine.holdProgress)
                if let image = coachBustImage(for: engine.currentExercise) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 64)
                        .opacity(0.62)
                        .scaleEffect(1.08)
                } else {
                    Circle()
                        .fill(ExerciseColors.green.opacity(0.16))
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 122, height: 122)
            Text(L10n.text("Çeneni geriye al ve sabit tut", "Draw your chin back and hold"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func repetitionCounter(label: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(engine.repCount)")
                    .font(.system(size: 86, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("/ \(engine.targetReps)")
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rest

    private var restView: some View {
        VStack(spacing: 18) {
            topBar(showTimer: true)
            sessionMetaRow
            progressTimeline
            Spacer()
            VStack(spacing: 10) {
                Text(L10n.text("Dinlenme", "Rest"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("\(Int(ceil(engine.restRemaining)))")
                    .font(.system(size: 74, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(L10n.text("sn", "sec"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                if engine.currentIndex + 1 < engine.sessionExercises.count {
                    Text("\(L10n.text("Sırada:", "Next:")) \(L10n.exerciseName(id: engine.sessionExercises[engine.currentIndex + 1].id, fallback: engine.sessionExercises[engine.currentIndex + 1].name))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actionButtons(skipTitle: L10n.text("Dinlenmeyi atla", "Skip rest"), stopTitle: L10n.text("Durdur", "Stop"))
        }
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 12) {
            topBar(showTimer: true)

            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 82, height: 82)
                        .background(ExerciseColors.green, in: Circle())
                        .shadow(color: ExerciseColors.green.opacity(0.18), radius: 14, y: 6)
                    Text(L10n.text("Seans tamamlandı", "Session complete"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(L10n.text("\(formatDuration(engine.elapsedSeconds)) içinde tamamlandı", "Completed in \(formatDuration(engine.elapsedSeconds))"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if !engine.summaryItems.isEmpty {
                    summaryList
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            sessionActionButtons(
                primaryTitle: L10n.text("Tekrar", "Again"),
                primaryImage: "arrow.clockwise",
                primaryColor: ExerciseColors.green,
                secondaryTitle: L10n.text("Kapat", "Close"),
                secondaryImage: "xmark",
                primaryAction: { engine.start() },
                secondaryAction: { NSApp.keyWindow?.close() }
            )
        }
    }

    private var summaryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("Özet", "Summary"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(completedSummaryCount) / \(engine.summaryItems.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(engine.summaryItems, id: \.id) { item in
                    HStack(spacing: 10) {
                        Image(systemName: summaryCompleted(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(summaryCompleted(item) ? ExerciseColors.green : .secondary.opacity(0.55))
                        Text(L10n.exerciseName(id: item.id, fallback: item.name))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(summaryValueText(item))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summaryCompleted(item) ? .primary : .secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 9)
                    if item.id != engine.summaryItems.last?.id {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ExerciseColors.hairline, lineWidth: 1)
        )
    }

    private var completedSummaryCount: Int {
        engine.summaryItems.filter(summaryCompleted).count
    }

    private func summaryCompleted(_ item: ExerciseResult) -> Bool {
        item.holds > 0 || item.reps > 0
    }

    private func summaryValueText(_ item: ExerciseResult) -> String {
        summaryIsHold(item)
            ? "\(item.holds) \(L10n.text("tutuş", "holds"))"
            : "\(item.reps) \(L10n.text("tekrar", "reps"))"
    }

    private func summaryIsHold(_ item: ExerciseResult) -> Bool {
        if item.holds > 0 { return true }
        guard let exercise = ExerciseLibrary.all.first(where: { $0.id == item.id }) else { return false }
        if case .guidedHold = exercise.goal { return true }
        return false
    }

    // MARK: Shared pieces

    private func topBar(showTimer: Bool) -> some View {
        ZStack {
            Text("UpPod")
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                if showTimer {
                    EmptyView()
                }
            }
        }
    }

    private var sessionMetaRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.055), in: Circle())
                Text(formatDuration(engine.elapsedSeconds))
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private var exerciseStepper: some View {
        let exercises = engine.sessionExercises
        let count = max(exercises.count, 1)
        let current = min(engine.currentIndex, max(count - 1, 0))
        return VStack(spacing: 7) {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(stepSegmentColor(index: index))
                        .frame(height: index == current ? 6 : 5)
                }
            }

            HStack(spacing: 7) {
                Text("\(current + 1) / \(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ExerciseColors.green)
                    .monospacedDigit()
                    Text(current < exercises.count ? L10n.exerciseName(id: exercises[current].id, fallback: exercises[current].name) : "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if current + 1 < exercises.count {
                    Text("\(L10n.text("Sırada:", "Next:")) \(L10n.exerciseName(id: exercises[current + 1].id, fallback: exercises[current + 1].name))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    private func stepSegmentColor(index: Int) -> Color {
        if index <= engine.currentIndex { return ExerciseColors.green }
        return Color.primary.opacity(0.10)
    }

    private func coachBust(for exercise: Exercise?) -> some View {
        Group {
            if let image = coachBustImage(for: exercise) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(coachScale(for: exercise))
                    .offset(y: coachYOffset(for: exercise))
            } else {
                Image(systemName: "figure.cooldown")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(ExerciseColors.green)
            }
        }
        .frame(width: 268, height: 188)
        .shadow(color: Color.black.opacity(0.045), radius: 10, y: 5)
    }

    private func coachBustImage(for exercise: Exercise?) -> NSImage? {
        AppImage.png(coachAssetName(for: exercise))
    }

    private func coachAssetName(for exercise: Exercise?) -> String {
        switch exercise?.id {
        case "flexion": return "coach-flexion"
        case "roll": return "coach-roll"
        case "chintuck": return "coach-chintuck"
        case "yaw": return "coach-yaw"
        default: return "coach-yaw"
        }
    }

    private func coachScale(for exercise: Exercise?) -> CGFloat {
        switch exercise?.id {
        case "flexion": return 1.13
        case "roll": return 1.10
        case "chintuck": return 1.15
        case "yaw": return 1.10
        default: return 1
        }
    }

    private func coachYOffset(for exercise: Exercise?) -> CGFloat {
        switch exercise?.id {
        case "flexion": return 2
        case "roll": return 2
        case "chintuck": return 4
        case "yaw": return 3
        default: return 0
        }
    }

    private func actionButtons(skipTitle: String, stopTitle: String) -> some View {
        sessionActionButtons(
            primaryTitle: stopTitle,
            primaryImage: "stop.fill",
            primaryColor: ExerciseColors.coral,
            secondaryTitle: skipTitle,
            secondaryImage: "forward.fill",
            primaryAction: { engine.stop() },
            secondaryAction: { engine.skip() }
        )
    }

    private func sessionActionButtons(
        primaryTitle: String,
        primaryImage: String,
        primaryColor: Color,
        secondaryTitle: String,
        secondaryImage: String,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 48) {
            Button(action: secondaryAction) {
                Label(secondaryTitle, systemImage: secondaryImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: primaryImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(primaryColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: primaryColor.opacity(0.10), radius: 8, y: 3)
        }
        .padding(.bottom, 2)
    }

    private var progressTimeline: some View {
        let count = max(engine.sessionExercises.count, 1)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(timelineColor(index: index))
                        .frame(height: 5)
                }
            }
            HStack {
                Text("\(min(engine.currentIndex + 1, count)) / \(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ExerciseColors.green)
                Text(L10n.text("Egzersiz", "Exercise"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if engine.currentIndex < engine.sessionExercises.count {
                    Text(L10n.exerciseName(id: engine.sessionExercises[engine.currentIndex].id, fallback: engine.sessionExercises[engine.currentIndex].name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func timelineColor(index: Int) -> Color {
        if index < engine.currentIndex { return ExerciseColors.green }
        if index == engine.currentIndex { return ExerciseColors.blue }
        return Color.primary.opacity(0.10)
    }

    private func gaugeLabel(value: Double, title: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value == 0 ? "0°" : formatSigned(value))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func gaugeMarker(color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 8, height: height)
    }

    private func xPosition(value: Double, maxAngle: Double, width: CGFloat) -> CGFloat {
        let pct = (value + maxAngle) / (maxAngle * 2)
        return 24 + CGFloat(pct) * max(width - 48, 1)
    }

    private func tickColor(signal: Double, target: Double) -> Color {
        if signal < -target { return ExerciseColors.coral.opacity(0.45) }
        if signal > target { return ExerciseColors.blue.opacity(0.45) }
        if abs(signal) < target * 0.18 { return Color.secondary.opacity(0.38) }
        return Color.secondary.opacity(0.20)
    }

    private func axisLabels(for ex: Exercise) -> (left: String, right: String) {
        switch ex.axis {
        case .flexion: return (L10n.text("Aşağı hedef", "Down target"), L10n.text("Yukarı hedef", "Up target"))
        case .roll: return (L10n.text("Sol hedef", "Left target"), L10n.text("Sağ hedef", "Right target"))
        case .yaw: return (L10n.text("Sol hedef", "Left target"), L10n.text("Sağ hedef", "Right target"))
        case .chinTuck: return ("", "")
        }
    }

    private func formatSigned(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded == 0 { return "0°" }
        return rounded > 0 ? "+\(rounded)°" : "\(rounded)°"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private extension Exercise {
    var totalRepsLabel: String {
        switch goal {
        case .guidedHold: return "\(totalReps) \(L10n.text("tutuş", "holds"))"
        case .reps: return "\(totalReps) \(L10n.text("tekrar", "reps"))"
        }
    }
}
