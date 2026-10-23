import SwiftUI

// The glass console over the river: date at top left, flow controls at top right, a hover tip,
// the timeline docked at the bottom, and the full-image viewer. Single dark theme by design.

private let muted = Color.white.opacity(0.55)
private let faint = Color.white.opacity(0.28)
private let accent = Color(red: 0x8f / 255, green: 0xc2 / 255, blue: 1)
private let ink = Color(red: 0x0a / 255, green: 0x14 / 255, blue: 0x30 / 255)
private let warn = Color(red: 1, green: 0x9a / 255, blue: 0x9a / 255)

/// Per-view hover flag. (An ObservableObject rather than @State: @State is a macro whose plugin
/// ships with Xcode, not with the Command Line Tools this project builds with.)
final class HoverState: ObservableObject { @Published var on = false }

extension View {
    func glass(_ radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

struct Overlay: View {
    let river: River
    private var ui: RiverUI { river.ui }

    var body: some View {
        ZStack {
            InfoPanel(ui: ui)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 24).padding(.top, 40)
                .allowsHitTesting(false)

            Toolbar(river: river)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 16).padding(.top, 14)

            if let tip = ui.tip {
                TipView(tip: tip)
                    .fixedSize()
                    .position(x: tip.at.x, y: tip.at.y - 36)
                    .allowsHitTesting(false)
            }

            if !ui.years.isEmpty {
                TimelineBar(river: river)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }

            if let f = ui.focus {
                PhotoViewer(focus: f, river: river)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let msg = ui.loading {
                Text(msg).font(.system(size: 14, weight: .light)).tracking(1.4).foregroundStyle(muted)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: ui.focus?.index)
        .animation(.easeOut(duration: 0.15), value: ui.tip == nil)
    }
}

private struct InfoPanel: View {
    let ui: RiverUI
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ui.year).font(.system(size: 84, weight: .ultraLight)).monospacedDigit().tracking(1.5)
                .shadow(color: accent.opacity(0.25), radius: 15)
            Text(ui.date).font(.system(size: 19, weight: .light)).monospacedDigit().padding(.top, 6)
            Text(ui.countText).font(.system(size: 13, weight: .light)).monospacedDigit().foregroundStyle(muted).padding(.top, 2)
            if let b = ui.badge {
                Text(b).font(.system(size: 11)).tracking(1.2).foregroundStyle(warn)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(warn.opacity(0.4)))
                    .padding(.top, 10)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct Pill: View {
    let title: String
    var on = false
    var minWidth: CGFloat = 0
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13)).tracking(0.3)
                .frame(minWidth: minWidth, minHeight: 32).padding(.horizontal, 14)
                .foregroundStyle(on ? ink : .white)
                .background(Capsule().fill(on ? Color.white.opacity(0.92) : Color.white.opacity(hover.on ? 0.08 : 0)))
                .shadow(color: on ? .white.opacity(0.35) : .clear, radius: 9)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

private struct Toolbar: View {
    let river: River
    var body: some View {
        let ui = river.ui
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 2) {
                Pill(title: ui.playing ? "Pause" : "Play", on: ui.playing, minWidth: 48) { river.togglePlay() }
                Pill(title: "Restart") { river.restart() }
            }
            .padding(4).glass(999)
            HStack(spacing: 2) {
                ForEach(speeds, id: \.name) { s in Pill(title: s.name, on: ui.speed == s.value) { river.setSpeed(s.value) } }
            }
            .padding(4).glass(999)
            Text("Scroll to zoom · Drag to scrub · Click a photo to open it · Space to pause")
                .font(.system(size: 11.5)).tracking(0.4).foregroundStyle(faint).padding(.trailing, 6)
        }
    }
}

private struct TipView: View {
    let tip: Tip
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tip.main).font(.system(size: 12.5)).foregroundStyle(.white)
            Text(tip.sub).font(.system(size: 11.5)).foregroundStyle(muted)
        }
        .monospacedDigit()
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(12)
    }
}

// ---------- timeline: years as wide as their photo count; hover pulls out the months ----------

private struct TimelineBar: View {
    let river: River

    var body: some View {
        let ui = river.ui
        let minYear = Double(ui.total) * 0.004
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TIMELINE")
                Spacer()
                Text(ui.timelineRight.uppercased())
            }
            .font(.system(size: 11)).tracking(1.3).foregroundStyle(faint)
            .padding(.horizontal, 6).padding(.bottom, 6)

            if ui.timelineOpen {
                Text("\(String(ui.monthsYear)) · MONTHS").font(.system(size: 11)).tracking(0.9).foregroundStyle(faint)
                    .padding(.horizontal, 6).padding(.bottom, 4)
                WeightedRow(weights: ui.months.map { Double(max($0.count, 1) + 8) }, gap: 3) { k, w in
                    let m = ui.months[k]
                    TimelineCell(label: m.name, width: w, now: false, fontSize: 11.5) { river.jumpToPhoto(m.start) }
                        .opacity(m.count == 0 ? 0.35 : 1)
                        .help("\(m.name) \(String(ui.monthsYear)): \(fmtInt(m.count)) photos")
                }
                .frame(height: 30).padding(.bottom, 8)
            }

            WeightedRow(weights: ui.years.map { max(Double($0.count), minYear) }, gap: 2,
                        playhead: ui.years.firstIndex { $0.year == ui.nowYear }, fraction: ui.nowFraction) { k, w in
                let y = ui.years[k]
                TimelineCell(label: String(y.year), width: w, now: y.year == ui.nowYear, fontSize: 12,
                             onHover: { river.showMonths(y.year); ui.timelinePinned = false }) {
                    river.showMonths(y.year)
                    ui.timelinePinned = true
                    river.jumpToPhoto(y.start)
                }
                .help("\(String(y.year)): \(fmtInt(y.count)) photos")
            }
            .frame(height: 32)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
        .glass(18)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.2)) {
                if inside { ui.timelineOpen = true } else if !ui.timelinePinned { ui.timelineOpen = false }
            }
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                ui.timelineOpen.toggle()
                ui.timelinePinned = ui.timelineOpen
            }
        }
    }
}

private struct TimelineCell: View {
    let label: String
    let width: CGFloat
    let now: Bool
    let fontSize: CGFloat
    var onHover: (() -> Void)? = nil
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Text(width < 34 ? "" : label).font(.system(size: fontSize)).monospacedDigit().tracking(0.2).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(hover.on || now ? .white : muted)
                .background(shape.fill(Color.white.opacity(hover.on ? 0.14 : 0.04)))
                .overlay(shape.strokeBorder(Color.white.opacity(now ? 0.25 : 0.05)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { h in hover.on = h; if h { onHover?() } }
    }
}

/// Cells laid out left to right with widths proportional to their weights, plus an optional playhead.
private struct WeightedRow<Cell: View>: View {
    let weights: [Double]
    let gap: CGFloat
    var playhead: Int? = nil
    var fraction: Double = 0
    @ViewBuilder let cell: (Int, CGFloat) -> Cell

    var body: some View {
        GeometryReader { geo in
            let n = weights.count
            let avail = max(0, geo.size.width - gap * CGFloat(max(0, n - 1)))
            let sum = max(1e-9, weights.reduce(0, +))
            let widths = weights.map { CGFloat($0 / sum) * avail }
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { k in cell(k, widths[k]).frame(width: widths[k]) }
                }
                if let k = playhead, k < n {
                    let x = widths[..<k].reduce(0, +) + gap * CGFloat(k) + widths[k] * fraction
                    Capsule().fill(.white).frame(width: 2, height: geo.size.height + 12)
                        .shadow(color: .white.opacity(0.8), radius: 5)
                        .offset(x: x - 1, y: -6)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// ---------- the full-image viewer ----------

private struct PhotoViewer: View {
    let focus: Focus
    let river: River

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
            VStack(spacing: 14) {
                ZStack {
                    if let img = focus.image {
                        Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                    } else if let err = focus.error {
                        Text(err).font(.system(size: 13)).foregroundStyle(muted)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 3) {
                    Text(focus.main).font(.system(size: 14)).foregroundStyle(.white)
                    Text(focus.sub).font(.system(size: 12)).foregroundStyle(muted)
                    if let p = focus.progress {
                        ProgressView(value: p).frame(width: 180).padding(.top, 4)
                        Text("Downloading from iCloud…").font(.system(size: 11)).foregroundStyle(faint)
                    }
                    Text("Click or Esc to close · ← → previous / next").font(.system(size: 11)).foregroundStyle(faint).padding(.top, 2)
                }
                .monospacedDigit()
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glass(14)
            }
            .padding(.horizontal, 48).padding(.top, 44).padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { river.closeFocus() }
    }
}
