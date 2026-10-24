import Testing
import Foundation
@testable import Sayso

struct SaysoTests {
    @Test func parsesLocalDateTime() throws {
        let d = try #require(DateText.parse("2026-10-30T12:00:00"))
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        #expect(c.year == 2026 && c.month == 10 && c.day == 30 && c.hour == 12 && c.minute == 0)
    }

    @Test func rejectsGarbageDates() {
        #expect(DateText.parse("next-ish friday") == nil)
    }

    @Test func weekdaySummaries() {
        #expect(DateText.days([.monday, .tuesday, .wednesday, .thursday, .friday]) == "Weekdays")
        #expect(DateText.days([.sunday, .saturday]) == "Weekends")
    }

    @Test func cardText() {
        let start = DateText.parse("2026-10-30T12:00:00")!
        let a = ProposedAction(payload: .calendar(.init(title: "Lunch with Sam", start: start, end: nil, location: "", notes: "")))
        #expect(a.card.hasPrefix("Calendar: Lunch with Sam, "))
        // iOS puts a narrow no-break space before AM/PM.
        #expect(a.card.replacingOccurrences(of: "\u{202F}", with: " ").hasSuffix("12:00 PM"))
        let t = ProposedAction(payload: .timer(.init(seconds: 600, label: "")))
        #expect(t.card == "Timer: 10 min")
    }

    @Test func collectorDedupesIdenticalCalls() async {
        let c = PlanCollector()
        let p = ProposedAction.Payload.directions(.init(destination: "Home"))
        #expect(await c.add(p))
        #expect(await c.add(p) == false)
        #expect(await c.drain().count == 1)
        #expect(await c.drain().isEmpty)
    }

    @Test func toolsOnlyQueueAndNeverExecute() async throws {
        let c = PlanCollector()
        let tool = StartTimerTool(collector: c)
        _ = try await tool.call(arguments: .init(durationSeconds: 90, label: "Tea"))
        let queued = await c.drain()
        #expect(queued.count == 1)
        #expect(queued[0].summary == "Tea, 1 min 30 sec")
    }

    @Test func toolRejectsUnreadableDate() async {
        let tool = CreateCalendarEventTool(collector: PlanCollector())
        await #expect(throws: ToolError.self) {
            _ = try await tool.call(arguments: .init(title: "X", start: "someday", end: nil, location: nil, notes: nil))
        }
    }

    @Test @MainActor func editingAndRemovingActions() {
        let a = ProposedAction(payload: .directions(.init(destination: "A")))
        let b = ProposedAction(payload: .directions(.init(destination: "B")))
        let plan = ActionPlan(actions: [a, b], transcript: "x")
        var edited = a
        edited.payload = .directions(.init(destination: "C"))
        plan.update(edited)
        plan.remove(b.id)
        #expect(plan.approve().actions.map(\.summary) == ["C"])
    }

    @Test func alarmRejectsBadTime() async {
        let tool = SetAlarmTool(collector: PlanCollector())
        await #expect(throws: ToolError.self) {
            _ = try await tool.call(arguments: .init(label: "", time: "25:99", repeatDays: []))
        }
    }
}
