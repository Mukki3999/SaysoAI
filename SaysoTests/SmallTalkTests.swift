import Testing
@testable import Sayso

struct SmallTalkTests {
    @Test func capabilityQuestionsAreAnswered() {
        for q in ["Can you tell me what else we can do?", "what else can you do", "What can I say?", "how does this work", "what do you do", "help", "What else?"] {
            #expect(SmallTalk.reply(q) == SmallTalk.capabilities, "\(q)")
        }
    }

    @Test func realRequestsAreNotCapabilityQuestions() {
        for q in ["set a timer for 10 minutes", "what else is on my calendar tomorrow", "can you text Ankit", "remind me what to do at 5"] {
            #expect(SmallTalk.reply(q) != SmallTalk.capabilities, "\(q)")
        }
    }
}

struct PlainQuestionTests {
    @Test func questionsWithoutATask() {
        #expect(SmallTalk.isPlainQuestion("Why is the sky blue?"))
        #expect(SmallTalk.isPlainQuestion("Can you tell me how that works?"))
    }

    @Test func tasksAndCalendarQuestionsAreNotPlain() {
        #expect(!SmallTalk.isPlainQuestion("Can you text Ankit I'm late?"))
        #expect(!SmallTalk.isPlainQuestion("What's on tomorrow?"))
        #expect(!SmallTalk.isPlainQuestion("Do I have anything at 3?"))
        #expect(!SmallTalk.isPlainQuestion("Dinner Saturday"))
    }
}
