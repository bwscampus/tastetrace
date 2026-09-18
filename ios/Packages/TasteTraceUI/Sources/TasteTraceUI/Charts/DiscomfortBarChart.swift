import SwiftUI
import Charts

/// One bar per day, colored by level, with a dashed baseline.
public struct DiscomfortBarChart: View {
    public struct Bar: Identifiable {
        public let id: String
        public let label: String
        public let value: Double
        public let level: String // zero | moderate | high
        public init(id: String, label: String, value: Double, level: String) {
            self.id = id; self.label = label; self.value = value; self.level = level
        }
    }

    let bars: [Bar]
    let baseline: Double

    public init(bars: [Bar], baseline: Double) {
        self.bars = bars
        self.baseline = baseline
    }

    public static func color(for level: String) -> Color {
        switch level {
        case "high": return TTColor.danger
        case "moderate": return TTColor.primary
        default: return TTColor.success
        }
    }

    public var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Day", bar.label), y: .value("Index", max(bar.value, 0.35)))
                    .foregroundStyle(Self.color(for: bar.level).gradient)
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 4) {
                        Text(bar.value == bar.value.rounded() ? "\(Int(bar.value))" : String(format: "%.1f", bar.value))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Self.color(for: bar.level))
                    }
            }
            if baseline > 0 {
                RuleMark(y: .value("Baseline", baseline))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(TTColor.textSecondary)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(String(format: "Baseline %.1f", baseline))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TTColor.textSecondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(TTColor.neutralTint, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartYScale(domain: 0...10)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Self.color(for: bars.first { $0.label == label }?.level ?? "zero"))
                    }
                }
            }
        }
        .frame(height: 200)
    }
}

/// Horizontal proportion bar with one segment per item.
public struct DistributionBar: View {
    public struct Segment: Identifiable {
        public let id: String
        public let share: Double
        public let color: Color
        public init(id: String, share: Double, color: Color) { self.id = id; self.share = share; self.color = color }
    }

    let segments: [Segment]
    public init(segments: [Segment]) { self.segments = segments }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    Capsule().fill(segment.color).frame(width: max(geo.size.width * segment.share - 2, 4))
                }
            }
        }
        .frame(height: 12)
    }
}

/// Labelled proportion bar (frequency, onset window).
public struct FrequencyBar: View {
    let fraction: Double
    let color: Color
    let gradient: Bool

    public init(fraction: Double, color: Color = TTColor.primary, gradient: Bool = false) {
        self.fraction = min(max(fraction, 0), 1)
        self.color = color
        self.gradient = gradient
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TTColor.neutralTint)
                Capsule()
                    .fill(gradient ? AnyShapeStyle(LinearGradient(colors: [TTColor.danger, TTColor.warning], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(color))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 10)
    }
}

/// Tiny bar sparkline for the Today hero.
public struct SparklineView: View {
    let values: [Double]
    let levels: [String]

    public init(values: [Double], levels: [String]) {
        self.values = values
        self.levels = levels
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(DiscomfortBarChart.color(for: levels.indices.contains(index) ? levels[index] : "zero"))
                    .frame(width: 6, height: max(4, CGFloat(value / 10) * 36))
            }
        }
        .frame(height: 36, alignment: .bottom)
    }
}
