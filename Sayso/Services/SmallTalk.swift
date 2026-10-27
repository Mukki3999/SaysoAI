import Foundation

/// Greetings and thanks get an instant answer. The model would take many seconds to say hello.
enum SmallTalk {
    static func reply(_ text: String) -> String? {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?,'’"))
        let greetings: Set<String> = ["hi", "hello", "hey", "hey there", "hi there", "hello there", "yo", "sup", "good morning", "good afternoon", "good evening", "hey sayso", "hi sayso", "hello sayso"]
        if greetings.contains(t) {
            let options = [
                "Hey! Tell me what's coming up and I'll set it up. Events, alarms, reminders, texts, or a plan for your day.",
                "Hi! Try “dinner with Sam Friday at 8”, “plan tomorrow”, or “cancel my 3pm”.",
                "Hello! What's on your mind? I can schedule, remind, wake you up, or clear things off your calendar."
            ]
            return options[abs(t.hashValue) % options.count]
        }
        if ["thanks", "thank you", "thx", "ty", "thanks a lot", "thank you so much", "cheers"].contains(t) { return "Anytime." }
        if ["ok", "okay", "cool", "nice", "great", "got it", "perfect"].contains(t) { return "👍 Just say the word when you need something." }
        if ["what can you do", "help", "what do you do", "what can i say"].contains(t) {
            return "I can add events and reminders, set alarms and timers, draft texts and emails, give directions, plan or re-plan your day, delete or move things on your calendar, and pick dishes from a menu photo. Everything waits for your OK first."
        }
        return nil
    }
}
