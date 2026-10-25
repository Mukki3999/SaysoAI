import SwiftUI

/// Your day as two columns, before and after, on one hour scale.
struct DayTimeline: View {
    let before: [TimelineEntry]
    let after: [TimelineEntry]
    let day: Date
    let settings: PlanSettings

    private let hourHeight: CGFloat = 40
    private let axis: CGFloat = 40

    private var visible: (before: [TimelineEntry], after: [TimelineEntry]) {
        let cal = Calendar.current
        func today(_ e: TimelineEntry) -> Bool { cal.isDate(e.start, inSameDayAs: day) }
        return (before.filter(today), after.filter(today))
    }

    private func minutes(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private var hours: ClosedRange<Int> {
        let all = visible.before + visible.after
        let first = min(settings.workStart / 60, Int((all.map { minutes($0.start) }.min() ?? 1440) / 60))
        let last = max((settings.workEnd + 59) / 60, Int(((all.map { minutes($0.end) }.max() ?? 0) + 59) / 60))
        return max(first, 0)...min(last, 24)
    }

    var body: some View {
        let range = hours
        let columns = visible
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Color.clear.frame(width: axis)
                header("Before"); header("After")
            }
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    ForEach(range.lowerBound...range.upperBound, id: \.self) { h in
                        Text(label(h)).font(.system(size: 10)).foregroundStyle(.black.opacity(0.4))
                            .offset(y: CGFloat(h - range.lowerBound) * hourHeight - 6)
                    }
                }
                .frame(width: axis, alignment: .leading)
                column(columns.before, range: range)
                column(columns.after, range: range)
            }
            .frame(height: CGFloat(range.count) * hourHeight + 4, alignment: .top)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8)
            .foregroundStyle(.black.opacity(0.45)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 || hour == 24 ? "AM" : "PM")"
    }

    private func column(_ entries: [TimelineEntry], range: ClosedRange<Int>) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(range.lowerBound...range.upperBound, id: \.self) { h in
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
                    .offset(y: CGFloat(h - range.lowerBound) * hourHeight)
            }
            ForEach(entries) { e in
                let top = (minutes(e.start) / 60 - Double(range.lowerBound)) * hourHeight
                let height = max((minutes(e.end) - minutes(e.start)) / 60 * hourHeight - 2, 16)
                block(e).frame(height: height).offset(y: top + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func block(_ e: TimelineEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 3) {
            if e.style == .committed { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
            Text(e.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(e.style == .proposed || e.style == .committed ? .white : .black.opacity(e.style == .old ? 0.5 : 0.75))
        .background {
            switch e.style {
            case .event: shape.fill(Color.black.opacity(0.09))
            case .proposed, .committed: shape.fill(Color.black)
            case .kept: shape.fill(Color.black.opacity(0.09)).overlay(shape.stroke(Color.black.opacity(0.5), lineWidth: 1))
            case .old: shape.strokeBorder(Color.black.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
    }
}
