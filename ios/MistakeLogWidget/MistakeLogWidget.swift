import SwiftUI
import UIKit
import WidgetKit

private let appGroup = "group.com.example.mistakeLogApp"

struct MistakeEntry: TimelineEntry {
    let date: Date
    let className: String
    let description: String
    let tags: String
    let photoPath: String?
}

struct MistakeProvider: TimelineProvider {
    func placeholder(in context: Context) -> MistakeEntry {
        MistakeEntry(
            date: Date(),
            className: "Precalculus",
            description: "Review a mistake from your log.",
            tags: "conceptual",
            photoPath: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MistakeEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MistakeEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let entries = (0..<8).map { offset in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: now)!)
            return entry(for: date)
        }
        let nextUpdate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    private func entry(for date: Date) -> MistakeEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let cycle = defaults?.string(forKey: "mistake_cycle") ?? "[]"
        let anchorString = defaults?.string(forKey: "mistake_cycle_anchor") ?? ""
        guard
            let data = cycle.data(using: .utf8),
            let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]],
            !items.isEmpty
        else {
            return MistakeEntry(
                date: date,
                className: "Mistake Log",
                description: "Add an unreviewed mistake to see your daily review.",
                tags: "",
                photoPath: nil
            )
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let anchor = formatter.date(from: anchorString) ?? date
        let dayOffset = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: anchor),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        let index = ((dayOffset % items.count) + items.count) % items.count
        let item = items[index]
        return MistakeEntry(
            date: date,
            className: item["className"] ?? "Mistake Log",
            description: item["description"] ?? "Review today's mistake.",
            tags: item["tags"] ?? "",
            photoPath: item["photoPath"]
        )
    }
}

struct MistakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MistakeEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    if let image = photo {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    textContent(compact: true)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let image = photo {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 94)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    textContent(compact: false)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var photo: Image? {
        guard let path = entry.photoPath, let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        return Image(uiImage: image)
    }

    @ViewBuilder
    private func textContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.className.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(entry.description)
                .font(.system(size: compact ? 14 : 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(compact ? 3 : 6)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            if !entry.tags.isEmpty {
                Text(entry.tags)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("DAILY REVIEW")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

@main
struct MistakeLogWidget: Widget {
    let kind = "MistakeLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MistakeProvider()) { entry in
            MistakeWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Mistake")
        .description("Review one shuffled, unreviewed mistake each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
