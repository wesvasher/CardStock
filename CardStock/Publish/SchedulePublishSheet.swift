import SwiftUI

/// Asks when to publish automatically, with quick choices, a calendar and a
/// time, plus an optional description of the changes.
struct SchedulePublishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var message: String
    private let isChanging: Bool

    init(existing: ScheduledPublish?) {
        isChanging = existing != nil
        _date = State(initialValue: existing.map { max($0.date, Self.soonest) } ?? Self.suggested)
        _message = State(initialValue: existing?.message ?? "")
    }

    /// The next whole hour at least 30 minutes away.
    private static var suggested: Date {
        let cal = Calendar.current
        let later = Date.now.addingTimeInterval(30 * 60)
        return cal.nextDate(after: later, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? later
    }

    private static var soonest: Date { Date.now.addingTimeInterval(60) }

    private var isValid: Bool { date > .now }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isChanging ? "Change Scheduled Publish" : "Schedule Publish")
                    .font(.headline)
                Text("CardStock publishes everything on this Mac at the time you choose, as if you'd clicked Publish then. Posts marked Draft stay hidden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                quickPick("In 1 Hour", Date.now.addingTimeInterval(3600))
                quickPick("Tonight, 9 PM", at(hour: 21, daysFromToday: 0))
                quickPick("Tomorrow, 9 AM", at(hour: 9, daysFromToday: 1))
            }

            HStack(alignment: .top, spacing: 20) {
                DatePicker("Date", selection: $date, in: Self.soonest..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 230)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time").font(.callout.weight(.medium))
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Publishes").font(.callout.weight(.medium))
                        Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        Text(isValid ? date.formatted(.relative(presentation: .named)) : "That time has passed.")
                            .font(.caption)
                            .foregroundStyle(isValid ? Color.secondary : Color.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Describe your changes (optional)").font(.callout.weight(.medium))
                TextField("Describe your changes", text: $message, prompt: Text("New post about Japan"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }

            Label("Keep CardStock open with this site. If your Mac is asleep or CardStock is closed at that time, it publishes as soon as they're back.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isChanging ? "Update Schedule" : "Schedule") {
                    model.schedulePublish(at: date, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func quickPick(_ title: String, _ value: Date?) -> some View {
        Button(title) { if let value { date = value } }
            .controlSize(.small)
            .disabled(value.map { $0 <= .now } ?? true)
    }

    private func at(hour: Int, daysFromToday: Int) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: daysFromToday, to: .now) else { return nil }
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }
}

/// The scheduled publish shown under the Publish button: when, a live
/// countdown, and buttons to change or remove it.
struct ScheduledPublishCard: View {
    @Environment(AppModel.self) private var model
    let schedule: ScheduledPublish
    let onChange: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: schedule.failure == nil ? "clock.badge.checkmark" : "clock.badge.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(schedule.failure == nil ? Color.accentColor : Color.red)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.failure == nil ? "Publishing automatically" : "Scheduled publish didn't finish")
                        .font(.headline)
                    Text(schedule.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        .foregroundStyle(.secondary)
                    if !schedule.message.isEmpty {
                        Text("“\(schedule.message)”")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if schedule.failure == nil {
                    countdown
                }
            }

            if let failure = schedule.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if schedule.failure != nil {
                    Button("Try Again") { model.retryScheduledPublish() }
                        .disabled(model.isWorking)
                }
                Button("Change…", action: onChange)
                Spacer()
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background((schedule.failure == nil ? Color.accentColor : Color.red).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder((schedule.failure == nil ? Color.accentColor : Color.red).opacity(0.3)))
        .confirmationDialog("Remove the scheduled publish?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { model.cancelScheduledPublish() }
        } message: {
            Text("Nothing is published automatically. Your changes stay on this Mac until you publish.")
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 0) {
                if schedule.date > context.date {
                    Text(ScheduledPublish.countdown(to: schedule.date, from: context.date))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(countsDown: true))
                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Publishing…").foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.default, value: context.date)
        }
    }
}
