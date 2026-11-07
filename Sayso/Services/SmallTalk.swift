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
        if asksWhatSaysoCanDo(t) { return capabilities }
        if t.range(of: #"^(who are you|what are you|are you (an )?(ai|a bot|real)|what is sayso|who made you)$"#, options: .regularExpression) != nil {
            return "I'm Sayso, an assistant that runs on your iPhone. Tell me what you need and I'll set it up for your OK. Nothing leaves your phone."
        }
        return nil
    }

    private static let actionWords = #"\b(add|schedule|set|remind|text|message|email|call|delete|remove|cancel|move|reschedule|plan|book|create|put|send|navigate|timer|alarm|directions)\b"#

    /// "What else can we do?", "how does this work?", "what can I say?": questions about Sayso itself, with no task in them.
    static func asksWhatSaysoCanDo(_ t: String) -> Bool {
        if t.range(of: actionWords, options: .regularExpression) != nil { return false }
        let ask = #"\b(what (else )?(can|could|should) (you|we|i|sayso)( even)?( \w+)? ?(do|say|ask|try|help)|what else (can|could|do|should)|what else (we|you|i) (can|could|do)|^what else$|what do you do|how (do|does|can) (this|it|sayso|i use)( \w+)? ?(work|use)?|what are (your|the) (features|capabilities)|what can i say|tell me what (you|we|i) can|give me (some )?(ideas|examples))\b|^help( me)?$"#
        return t.range(of: ask, options: .regularExpression) != nil
    }

    /// "Why is the sky blue?", "is it going to rain?": a question with no task in it. Sayso never turns one into an action.
    static func isPlainQuestion(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasSuffix("?") else { return false }
        if t.range(of: actionWords, options: .regularExpression) != nil { return false }
        if t.range(of: #"\b(\d|tomorrow|today|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|calendar|schedule|agenda|free|busy)\b"#, options: .regularExpression) != nil { return false }
        return t.range(of: #"^(what|why|how|who|where|is|are|does|do|did|can you tell|could you tell|tell me)\b"#, options: .regularExpression) != nil
    }

    static let capabilities = """
    Here's what I can do, always with your OK first:
    • Events and reminders: “dinner with Sam Friday at 8”
    • Alarms and timers: “wake me at 7”, “timer 10 minutes”
    • Texts and emails: “text Mom I'm running late” (I'll ask which contact)
    • Your calendar: “what's on tomorrow?”, “delete my 3pm”
    • Planning: “plan my day”, “I'm running behind”
    • Directions, and dishes from a menu photo
    """
}
