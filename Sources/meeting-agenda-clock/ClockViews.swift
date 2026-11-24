import MeetingAgendaClockCore
import SwiftUI

extension EnvironmentValues {
    /// A moment to draw instead of the real time. Set by `--render-previews`, so a rendering
    /// shows a chosen moment and never waits on a timeline.
    @Entry var frozenNow: Date?
    /// True while `--render-previews` draws a view offscreen. A sidebar list's selection draws
    /// as a black block in a window that was never on screen, so previews draw a stand-in
    /// highlight for the selected row instead.
    @Entry var isRenderingPreview = false
}

extension View {
    /// The stand-in selection highlight `--render-previews` draws. See `isRenderingPreview`.
    func previewSelection(_ selected: Bool, rendering: Bool) -> some View {
        listRowBackground(
            rendering && selected
                ? RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor)).padding(.horizontal, 10)
                : nil)
    }
}

/// Redraws its content with the current time, a few times a second. Only the drawing repeats:
/// what is drawn is computed from the run and the time each time.
struct Ticking<Content: View>: View {
    var paused = false
    @ViewBuilder let content: (Date) -> Content
    @Environment(\.frozenNow) private var frozenNow

    var body: some View {
        if let frozenNow {
            content(frozenNow)
        } else {
            TimelineView(.animation(minimumInterval: 0.25, paused: paused)) { context in
                content(context.date)
            }
        }
    }
}

enum ClockColors {
    /// The overtime color: a warm orange-red that reads on dark and light.
    static let overtime = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let running = Color.green
}

/// The segmented section bar: one segment per section, widths in proportion to each section's
/// time, filled up to now. The clock window, the running pane, and the edge line all use it.
struct SegmentBar: View {
    let state: ClockState
    var height: CGFloat = 8
    var gap: CGFloat = 6
    var trackOpacity: Double = 0.18
    var fill: Color = .accentColor
    var track: Color = .primary
    var cornerRadius: CGFloat?

    var body: some View {
        Canvas { context, size in
            let frames = Self.frames(for: state, width: size.width, gap: gap)
            let radius = cornerRadius ?? min(height / 2, 4)
            let color = state.isOvertime ? ClockColors.overtime : fill
            for (section, frame) in zip(state.sections, frames) where frame.width > 0 {
                let rect = CGRect(x: frame.minX, y: 0, width: frame.width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(track.opacity(trackOpacity)))
                let filled = CGRect(x: rect.minX, y: 0, width: rect.width * section.filled, height: size.height)
                if filled.width > 0 {
                    context.fill(Path(roundedRect: filled, cornerRadius: radius), with: .color(color))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Sections")
        .accessibilityValue(state.currentSectionName ?? "")
    }

    /// Each section's horizontal span in a bar `width` wide. Sections with no time get none and
    /// no gap.
    static func frames(for state: ClockState, width: CGFloat, gap: CGFloat) -> [ClosedRange<CGFloat>] {
        let total = state.sections.reduce(0) { $0 + $1.scheduledSeconds }
        let shown = state.sections.filter { $0.scheduledSeconds > 0 }.count
        let usable = max(0, width - gap * CGFloat(max(0, shown - 1)))
        var x: CGFloat = 0
        return state.sections.map { section in
            guard total > 0, section.scheduledSeconds > 0 else { return x...x }
            let w = usable * section.scheduledSeconds / total
            defer { x += w + gap }
            return x...(x + w)
        }
    }
}

private extension ClosedRange<CGFloat> {
    var minX: CGFloat { lowerBound }
    var width: CGFloat { upperBound - lowerBound }
}

/// The bar with each section's name under its segment.
struct LabeledSegmentBar: View {
    let state: ClockState
    var height: CGFloat = 10
    var labelFont: Font = .callout
    var fill: Color = .accentColor

    var body: some View {
        VStack(spacing: 8) {
            SegmentBar(state: state, height: height, fill: fill)
            GeometryReader { geometry in
                let frames = SegmentBar.frames(for: state, width: geometry.size.width, gap: 6)
                ForEach(Array(zip(state.sections, frames)), id: \.0.id) { section, frame in
                    if frame.upperBound - frame.lowerBound > 0 {
                        Text(section.name)
                            .font(labelFont)
                            .fontWeight(.regular)
                            .foregroundStyle(section.status == .current ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: frame.upperBound - frame.lowerBound, alignment: .leading)
                            .offset(x: frame.lowerBound)
                    }
                }
            }
            .frame(height: 20)
        }
    }
}

/// The live clock: the big time, what it means, the current section, and the bar. One view for
/// both the running pane and the clock window, which differ only in size and background.
struct LiveClockView: View {
    enum Style {
        /// In the Agendas window.
        case pane
        /// The dark clock window, read from across a room. The digits scale with the window.
        case room
    }

    let state: ClockState
    var style: Style = .pane

    var body: some View {
        switch style {
        case .pane:
            content(digitSize: 96)
        case .room:
            GeometryReader { geometry in
                let size = min(geometry.size.width / 3.4, geometry.size.height / 2.1)
                content(digitSize: max(48, size))
                    .padding(.horizontal, max(24, geometry.size.width * 0.05))
                    .padding(.vertical, max(20, geometry.size.height * 0.06))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private var timeColor: Color {
        if state.isOvertime { return ClockColors.overtime }
        if state.isPaused { return .secondary }
        return style == .room ? .white : .primary
    }

    @ViewBuilder private func content(digitSize: CGFloat) -> some View {
        VStack(spacing: style == .room ? digitSize * 0.12 : 10) {
            if style == .room { Spacer(minLength: 0) }
            Text(state.primaryText)
                // Monospaced digits keep the number from jittering as it changes.
                .font(.system(size: digitSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .contentTransition(.identity)
            Text(subtitle)
                .font(.system(size: style == .room ? max(18, digitSize * 0.16) : 17, weight: .regular))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let name = state.currentSectionName, !state.isOvertime {
                Text("\(name) · \(TimeFormat.countdown(state.sectionRemaining)) left in section")
                    .font(.system(size: style == .room ? max(16, digitSize * 0.13) : 15, weight: .regular))
                    .foregroundStyle(style == .room ? .secondary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if style == .room { Spacer(minLength: 0) }
            LabeledSegmentBar(
                state: state,
                height: style == .room ? max(10, digitSize * 0.07) : 10,
                labelFont: style == .room ? .system(size: max(14, digitSize * 0.1)) : .callout)
                .padding(.top, style == .room ? 0 : 12)
        }
    }

    private var subtitle: String {
        let ends = TimeFormat.clockTime(state.endsAt)
        if state.isOvertime { return "over · ended \(ends)" }
        if state.isPaused { return "paused · ends \(ends) if resumed now" }
        return "remaining · ends \(ends)"
    }
}
