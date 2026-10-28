import Foundation
import Testing
@testable import Sayso

@Suite struct QuickParserTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14))! }   // Tuesday
    func parse(_ s: String) -> QuickParser.Result? { QuickParser.parse(s, now: now, calendar: cal) }

    func alarm(_ s: String) -> AlarmDraft? { if case .action(.alarm(let a)) = parse(s) { a } else { nil } }
    func timer(_ s: String) -> TimerDraft? { if case .action(.timer(let a)) = parse(s) { a } else { nil } }
    func reminder(_ s: String) -> ReminderDraft? { if case .action(.reminder(let a)) = parse(s) { a } else { nil } }

    @Test func timers() {
        #expect(timer("Set a timer for 10 minutes")?.seconds == 600)
        #expect(timer("timer for an hour and a half") == nil)       // two parts: the model
        #expect(timer("start a 1 hour 30 minute timer")?.seconds == 5400)
        #expect(timer("15 min timer")?.seconds == 900)
        #expect(parse("timer") == nil)
    }

    @Test func alarms() {
        #expect(alarm("Set an alarm for 7 am")?.hour == 7)
        #expect(alarm("wake me at 6:30")?.minute == 30)
        #expect(alarm("wake me at 6:30")?.hour == 6)
        #expect(alarm("alarm at 9:15 pm")?.hour == 21)
        #expect(alarm("wake me up at 7 on weekdays")?.repeatDays.count == 5)
        #expect(alarm("alarm for 7")?.hour == 7)
        #expect(alarm("alarm at 2") == nil)                         // 2 is ambiguous: ask
        #expect(parse("Put an alarm for me so I don't miss my 10am meeting") == nil)
        #expect(parse("delete my 7am alarm") == nil)
    }

    @Test func reminders() {
        let r = reminder("Remind me to call mom tomorrow at 5")
        #expect(r?.title == "Call mom")
        #expect(r.flatMap { $0.due }.map { cal.component(.hour, from: $0) } == 17)
        #expect(r.flatMap { $0.due }.map { cal.component(.day, from: $0) } == 28)
        #expect(reminder("remind me to buy milk")?.due == nil)
        #expect(reminder("remind me to take out the trash tonight at 8")?.due.map { cal.component(.hour, from: $0) } == 20)
        #expect(reminder("remind me to stretch in 20 minutes")?.due == now.addingTimeInterval(1200))
        #expect(reminder("remind me to call mom when I get home") == nil)
        #expect(reminder("remind me to buy 2 tickets")?.title == "Buy 2 tickets")
    }

    @Test func agenda() {
        if case .agenda(let d) = parse("What's on tomorrow?") { #expect(cal.component(.day, from: d) == 28) } else { Issue.record("not agenda") }
        if case .agenda = parse("am I free Friday") {} else { Issue.record("not agenda") }
        #expect(parse("help me plan what's on tomorrow") == nil)
    }

    @Test func multiPartGoesToModel() {
        #expect(parse("set an alarm for 7 and remind me to call mom") == nil)
        #expect(parse("remind me to text Sam") == nil)
        #expect(parse("Dinner with Ankit Saturday at 8") == nil)
    }
}
