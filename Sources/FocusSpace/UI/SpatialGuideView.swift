import SwiftUI

struct SpatialGuideView: View {
    let finish: () -> Void
    let dismiss: () -> Void
    @State private var step = SpatialGuideStep.depth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Focus Space")
                        .font(.title2.weight(.semibold))
                    Text("Four ideas make the universe feel natural.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    Text("\(step.rawValue + 1) of \(SpatialGuideStep.allCases.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Close", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .focusHelp("Close spatial guide", shortcut: "Esc")
                }
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SpatialGuideStep.allCases) { candidate in
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)) {
                                step = candidate
                            }
                        } label: {
                            Label(candidate.title, systemImage: icon(for: candidate))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(step == candidate ? Color.accentColor.opacity(0.16) : .clear, in: .rect(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .focusHelp("Show the \(candidate.title.lowercased()) guide")
                    }
                    Spacer()
                    Text("You can reopen this guide from the ? button at any time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(width: 220)
                .background(.black.opacity(0.12))

                VStack(spacing: 20) {
                    guideScene
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 8) {
                        Text(step.title)
                            .font(.title3.weight(.semibold))
                        Text(step.explanation)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 440)
                    }
                    HStack {
                        Button("Back") { move(by: -1) }
                            .disabled(step == .depth)
                            .focusHelp("Go to the previous guide page")
                        Spacer()
                        if step == .gravity {
                            Button("Enter Focus Space", action: finish)
                                .keyboardShortcut(.defaultAction)
                                .focusHelp("Close the guide and begin arranging your space")
                        } else {
                            Button("Next") { move(by: 1) }
                                .keyboardShortcut(.defaultAction)
                                .focusHelp("Go to the next guide page")
                        }
                    }
                }
                .padding(28)
            }
        }
        .frame(width: 780, height: 560)
        .background(WorkspaceBackground())
        .preferredColorScheme(.dark)
        .onExitCommand(perform: dismiss)
    }

    @ViewBuilder
    private var guideScene: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { ring in
                Ellipse()
                    .stroke(.blue.opacity(0.08 + Double(ring) * 0.025), lineWidth: 1)
                    .frame(width: 190 + CGFloat(ring) * 70, height: 85 + CGFloat(ring) * 35)
            }
            switch step {
            case .depth:
                GuideCard("NOW", colour: .blue, scale: 1.12)
                    .offset(y: 58)
                GuideCard("THIS SPRINT", colour: .purple, scale: 0.88)
                    .offset(x: -92, y: -12)
                    .opacity(0.72)
                GuideCard("SOMEDAY", colour: .gray, scale: 0.65)
                    .offset(x: 105, y: -70)
                    .opacity(0.38)
            case .hierarchy:
                GuideLink().frame(height: 115)
                GuideCard("PROJECT", colour: .blue, scale: 1).offset(y: -62)
                GuideCard("DESIGN", colour: .purple, scale: 0.82).offset(x: -95, y: 55)
                GuideCard("BUILD", colour: .green, scale: 0.82).offset(x: 95, y: 55)
            case .branchMovement:
                GuideLink().frame(height: 105).offset(x: -68)
                GuideCard("BRANCH", colour: .purple, scale: 1).offset(x: -68, y: -56)
                GuideCard("CHILD", colour: .green, scale: 0.78).offset(x: -132, y: 52)
                GuideCard("CHILD", colour: .green, scale: 0.78).offset(x: -5, y: 52)
                Image(systemName: "arrow.up.to.line.compact")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.cyan)
                    .offset(x: 126)
            case .gravity:
                GuideCard("REVIEW", colour: .green, scale: 0.95)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                    .offset(x: -120, y: -70)
                Image(systemName: "arrow.down.forward")
                    .font(.system(size: 35, weight: .light))
                    .foregroundStyle(.cyan)
                    .offset(x: -72, y: -36)
                Text("You remain in control")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .offset(y: 86)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84), value: step)
    }

    private func move(by delta: Int) {
        guard let next = SpatialGuideStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)) { step = next }
    }

    private func icon(for step: SpatialGuideStep) -> String {
        switch step {
        case .depth: "square.3.layers.3d"
        case .hierarchy: "point.3.connected.trianglepath.dotted"
        case .branchMovement: "arrow.triangle.branch"
        case .gravity: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
        }
    }
}

private struct GuideCard: View {
    let title: String
    let colour: Color
    let scale: Double

    init(_ title: String, colour: Color, scale: Double) {
        self.title = title
        self.colour = colour
        self.scale = scale
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(
                LinearGradient(colors: [colour.opacity(0.72), colour.opacity(0.28)], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 12)
            )
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(colour.opacity(0.85)) }
            .shadow(color: colour.opacity(0.28), radius: 12)
            .scaleEffect(scale)
    }
}

private struct GuideLink: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width * 0.28, y: size.height))
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height))
            context.stroke(path, with: .color(.blue.opacity(0.45)), lineWidth: 1.2)
        }
    }
}
