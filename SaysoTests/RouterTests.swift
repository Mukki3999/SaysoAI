import Testing
import Foundation
import CoreGraphics
@testable import Sayso

struct RouterTests {
    @Test func plansTheDay() {
        #expect(PlannerRouter.route("Plan my day") == .planDay(mustDos: nil))
        #expect(PlannerRouter.route("can you organize my day") == .planDay(mustDos: nil))
        #expect(PlannerRouter.route("plan my day: finish the deck and go to the gym") == .planDay(mustDos: "finish the deck and go to the gym"))
    }

    @Test func rescuesTheDay() {
        #expect(PlannerRouter.route("I'm 30 minutes behind") == .rescueDay(minutesBehind: 30))
        #expect(PlannerRouter.route("I'm an hour behind") == .rescueDay(minutesBehind: 60))
        #expect(PlannerRouter.route("re-plan the rest of my day") == .rescueDay(minutesBehind: 0))
        #expect(PlannerRouter.route("I'm running behind") == .rescueDay(minutesBehind: nil))
    }

    @Test func leavesEverythingElseToTheModel() {
        #expect(PlannerRouter.route("Text Sam I'm 10 minutes behind") == nil)
        #expect(PlannerRouter.route("Set an alarm for 7") == nil)
        #expect(PlannerRouter.route("What's on tomorrow?") == nil)
        #expect(PlannerRouter.route("Dinner with Ankit Saturday at 8") == nil)
    }

    @Test func recognisesMenusButNotOtherPhotos() {
        func lines(_ t: [String]) -> [OCRLine] { t.enumerated().map { OCRLine(index: $0.offset, text: $0.element, box: .zero) } }
        let menu = lines(["Burrata 14", "Calamari 16", "Soup 9", "Pizza 18", "Rigatoni 19", "Salmon 28"])
        #expect(MenuDetector.looksLikeMenu(menu, userText: ""))
        let ticket = lines(["Flight to Austin", "Gate B12", "Boards 2:15 PM", "Seat 14A", "Sat Oct 31"])
        #expect(!MenuDetector.looksLikeMenu(ticket, userText: "Add this to my calendar"))
    }
}
