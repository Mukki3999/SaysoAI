import SwiftUI

// MARK: 1. The problem

struct ProblemScene: View {
    @State private var chips = 0
    @State private var beat = 0
    @State private var steps = 0
    @State private var tail = false

    private let apps = [("Calendar", "calendar"), ("Reminders", "checklist"), ("Clock", "alarm"), ("Messages", "message"), ("Maps", "map")]
    private let offsets: [(CGFloat, CGFloat, Double)] = [(-92, -70, -8), (78, -46, 6), (-34, 8, -3), (96, 66, 9), (-86, 76, 5)]
    private let stepNames = ["Open Calendar", "Tap +", "Type the title", "Pick the day", "Pick the time", "Add the place", "Save"]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Group {
                if beat == 0 { SceneHeadline(text: "Your day lives in five different apps.") }
                else { SceneHeadline(text: "One dinner, seven steps.", delay: 0) }
            }
            .padding(.top, 96)

            if beat == 0 {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                            if i < chips {
                                Label(app.0, systemImage: app.1)
                                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(.white, in: Capsule())
                                    .rotationEffect(.degrees(offsets[i].2 + sin(t * 1.3 + Double(i)) * 3))
                                    .offset(x: offsets[i].0, y: offsets[i].1 + CGFloat(sin(t * 1.1 + Double(i) * 1.7)) * 5)
                                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 230)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(stepNames.enumerated()), id: \.offset) { i, name in
                        if i < steps {
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.black)
                                    .frame(width: 22, height: 22).background(.white, in: Circle())
                                Text(name).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                                Spacer()
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                .transition(.opacity)
            }

            Group {
                if beat == 0 { SceneCaption(text: "Calendar for plans. Reminders for to-dos. Clock for alarms. Messages. Maps.") }
                else if tail { SceneCaption(text: "…and that's before the reminder, the alarm, and the directions.") }
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (0.9, { withAnimation(.spring(duration: 0.5)) { chips = 1 } }),
            (1.2, { withAnimation(.spring(duration: 0.5)) { chips = 2 } }),
            (1.5, { withAnimation(.spring(duration: 0.5)) { chips = 3 } }),
            (1.8, { withAnimation(.spring(duration: 0.5)) { chips = 4 } }),
            (2.1, { withAnimation(.spring(duration: 0.5)) { chips = 5 } }),
            (4.6, { withAnimation(.easeInOut(duration: 0.4)) { beat = 1 } }),
            (5.3, { withAnimation(.smooth) { steps = 1 } }), (5.6, { withAnimation(.smooth) { steps = 2 } }),
            (5.9, { withAnimation(.smooth) { steps = 3 } }), (6.2, { withAnimation(.smooth) { steps = 4 } }),
            (6.5, { withAnimation(.smooth) { steps = 5 } }), (6.8, { withAnimation(.smooth) { steps = 6 } }),
            (7.1, { withAnimation(.smooth) { steps = 7 } }),
            (7.9, { withAnimation(.smooth) { tail = true } })
        ])
    }
}

// MARK: 2. Say it

struct SayItScene: View {
    @State private var beat = 0       // 0 talking, 1 thinking, 2 done
    @State private var rows = 0
    private let sentence = "Dinner with Ankit Saturday at 8 at Nobu, remind me to book a table, and wake me at 6:30"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SceneHeadline(text: "Or just say it.").padding(.top, 96)

            HStack {
                Spacer(minLength: 40)
                Typewriter(text: sentence, perChar: 0.034, delay: 0.8)
                    .font(.system(size: 17)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            ZStack {
                if beat == 0 {
                    TimelineView(.animation) { t in
                        WaveView(mode: .listening, level: 0.45 + 0.35 * sin(t.date.timeIntervalSinceReferenceDate * 3))
                    }
                    .frame(height: 64).transition(.opacity)
                } else if beat == 1 {
                    Label("Sayso is on it…", systemImage: "sparkle").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                        .symbolEffect(.pulse).transition(.opacity)
                }
            }
            .frame(height: 64)

            VStack(spacing: 8) {
                if rows > 0 { MiniRow(symbol: "calendar", kind: "Calendar", text: "Dinner with Ankit, Sat 8:00 PM").transition(.move(edge: .bottom).combined(with: .opacity)) }
                if rows > 1 { MiniRow(symbol: "checklist", kind: "Reminder", text: "Book a table").transition(.move(edge: .bottom).combined(with: .opacity)) }
                if rows > 2 { MiniRow(symbol: "alarm", kind: "Alarm", text: "6:30 AM").transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if rows > 2 { SceneCaption(text: "One sentence. Three things, set up.") }
            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (4.9, { withAnimation(.easeInOut(duration: 0.3)) { beat = 1 } }),
            (5.9, { withAnimation(.easeInOut(duration: 0.3)) { beat = 2 } }),
            (6.0, { withAnimation(.spring(duration: 0.5)) { rows = 1 } }),
            (6.5, { withAnimation(.spring(duration: 0.5)) { rows = 2 } }),
            (7.0, { withAnimation(.spring(duration: 0.5)) { rows = 3 } })
        ])
    }
}

// MARK: 3. You approve

struct ApproveScene: View {
    @State private var shown = false
    @State private var tapping = false
    @State private var done = false
    @State private var caption = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SceneHeadline(text: "You stay in charge.").padding(.top, 96)

            VStack(alignment: .leading, spacing: 0) {
                Text(done ? "DONE" : "READY TO DO").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.black.opacity(0.45))
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
                HStack(spacing: 14) {
                    Image(systemName: "calendar").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(.black, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CALENDAR").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.black.opacity(0.4))
                        Text("Dinner with Ankit, Sat 8:00 PM").font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.bottom, 14)
                HStack(spacing: 8) {
                    if done {
                        Label("Added to Calendar", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium)).foregroundStyle(.black)
                        Spacer()
                        Text("Undo").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(.black, in: Capsule())
                    } else {
                        Text("Approve").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13).background(.black, in: Capsule())
                            .scaleEffect(tapping ? 0.94 : 1)
                            .overlay { if tapping { Circle().stroke(.black.opacity(0.35), lineWidth: 2).frame(width: 74, height: 74).transition(.scale(scale: 0.3).combined(with: .opacity)) } }
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.black.opacity(0.6))
                            .frame(width: 44, height: 44).background(Color.black.opacity(0.07), in: Circle())
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 16)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .scaleEffect(shown ? 1 : 0.92).opacity(shown ? 1 : 0)

            VStack(alignment: .leading, spacing: 8) {
                if caption >= 1 { SceneCaption(text: "Nothing happens until you tap Approve.") }
                if caption >= 2 { SceneCaption(text: "Texts and emails open as drafts. You always press Send.") }
                if caption >= 3 { SceneCaption(text: "Changed your mind? Undo.") }
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (0.8, { withAnimation(.spring(duration: 0.55)) { shown = true } }),
            (1.6, { withAnimation(.smooth) { caption = 1 } }),
            (2.6, { withAnimation(.spring(duration: 0.25)) { tapping = true } }),
            (3.1, { withAnimation(.smooth) { tapping = false; done = true } }),
            (3.8, { withAnimation(.smooth) { caption = 2 } }),
            (5.2, { withAnimation(.smooth) { caption = 3 } })
        ])
    }
}

// MARK: 4. Plan and rescue

struct PlanScene: View {
    @State private var beat = 0       // 0 day, 1 planned, 2 behind
    @State private var behindChip = false
    private let slot: CGFloat = 54

    private var deckSlot: Int { beat == 0 ? 1 : beat == 1 ? 1 : 3 }
    private var emailSlot: Int { beat == 2 ? 4 : 3 }
    private var gymSlot: Int { beat == 2 ? 5 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                if beat < 2 { SceneHeadline(text: "It plans your day.") }
                else { SceneHeadline(text: "Behind? It re-plans.", delay: 0) }
            }
            .padding(.top, 96)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
                ForEach(0..<6, id: \.self) { i in
                    Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).offset(y: CGFloat(i) * slot + 16)
                }
                block("Standup", dark: false).offset(y: 0 * slot + 16)
                block("Client call", dark: false).offset(y: 2 * slot + 16)
                if beat >= 1 {
                    block("Finish deck", dark: true).offset(y: CGFloat(deckSlot) * slot + 16).transition(.move(edge: .trailing).combined(with: .opacity))
                    block("Reply to emails", dark: true).offset(y: CGFloat(emailSlot) * slot + 16).transition(.move(edge: .trailing).combined(with: .opacity))
                    if beat == 1 { block("Gym", dark: true).offset(y: CGFloat(gymSlot) * slot + 16).transition(.move(edge: .trailing).combined(with: .opacity)) }
                    else { block("Gym → tomorrow", dark: false, dashed: true).offset(y: CGFloat(gymSlot) * slot + 16).transition(.opacity) }
                }
            }
            .frame(height: 6 * slot + 32).clipped()
            .overlay(alignment: .topTrailing) {
                if behindChip {
                    Label("45 min behind", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(.black, in: Capsule())
                        .overlay(Capsule().stroke(.white, lineWidth: 2)).padding(12)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }

            Group {
                if beat == 0 { SceneCaption(text: "Tell it what must get done. It finds the gaps.") }
                else if beat == 1 { SceneCaption(text: "Tasks land around your meetings, with breaks and lunch kept free.") }
                else { SceneCaption(text: "Running late? Say so. It shifts what fits and tells you what doesn't.") }
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (2.0, { withAnimation(.spring(duration: 0.8, bounce: 0.15)) { beat = 1 } }),
            (4.6, { withAnimation(.spring(duration: 0.5)) { behindChip = true } }),
            (5.2, { withAnimation(.spring(duration: 0.9, bounce: 0.15)) { beat = 2 } })
        ])
    }

    private func block(_ title: String, dark: Bool, dashed: Bool = false) -> some View {
        Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            .foregroundStyle(dark ? .white : .black.opacity(dashed ? 0.5 : 0.75))
            .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: slot - 8)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if dark { shape.fill(.black) }
                else if dashed { shape.strokeBorder(Color.black.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                else { shape.fill(Color.black.opacity(0.09)) }
            }
            .padding(.horizontal, 12)
    }
}

// MARK: 5. Menu

struct MenuScene: View {
    @State private var scan = -1
    @State private var asked = false
    @State private var pick = false
    private let dishes = [("Burrata & Tomato", "14"), ("Crispy Calamari", "16"), ("Grilled Salmon", "28"), ("Garden Salad", "12"), ("Roasted Chicken", "24")]
    private let row: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SceneHeadline(text: "Point it at a menu.").padding(.top, 96)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(dishes.enumerated()), id: \.offset) { i, d in
                        HStack {
                            Text(d.0).font(.system(size: 16)).foregroundStyle(.black.opacity(scan >= 0 && scan != i && pick ? 0.35 : 0.85))
                            Spacer()
                            Text(d.1).font(.system(size: 16)).foregroundStyle(.black.opacity(scan >= 0 && scan != i && pick ? 0.35 : 0.85))
                        }
                        .padding(.horizontal, 18).frame(height: row)
                    }
                }
                .padding(.vertical, 10)
                if scan >= 0 {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white, lineWidth: 5)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 2.5))
                        .frame(height: row - 6).padding(.horizontal, 10)
                        .offset(y: CGFloat(scan) * row + 13)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            HStack {
                Spacer(minLength: 30)
                if asked {
                    Typewriter(text: "something light, vegetarian, under $15", perChar: 0.03)
                        .font(.system(size: 16)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .transition(.opacity)
                }
            }
            if pick {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 26, height: 26).background(.white, in: Circle())
                    Text("Garden Salad, $12. Light and fresh, and vegetarian on the menu.")
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.9))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
            if pick { SceneCaption(text: "Read on your iPhone. Always check allergies with the restaurant.") }
        }
        .padding(.horizontal, 26).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (1.0, { withAnimation(.spring(duration: 0.4)) { scan = 0 } }),
            (1.5, { withAnimation(.spring(duration: 0.4)) { scan = 1 } }),
            (2.0, { withAnimation(.spring(duration: 0.4)) { scan = 2 } }),
            (2.5, { withAnimation(.spring(duration: 0.4)) { asked = true } }),
            (4.4, { withAnimation(.spring(duration: 0.6)) { scan = 3; pick = true } })
        ])
    }
}

// MARK: 6. Private, and the way in

struct PrivacyScene: View {
    @State private var lines = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SceneHeadline(text: "Private, on your iPhone.").padding(.top, 96)
            VStack(alignment: .leading, spacing: 16) {
                if lines > 0 { point("Runs with Apple Intelligence, on the device") }
                if lines > 1 { point("No account to make") }
                if lines > 2 { point("No cloud, no tracking, no ads") }
            }
            if lines > 3 {
                SceneCaption(text: "Sayso asks for calendar, microphone and the rest only when you first use something that needs it.")
            }
            Spacer()
            Spacer().frame(height: 90)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .script([
            (1.2, { withAnimation(.smooth) { lines = 1 } }),
            (1.9, { withAnimation(.smooth) { lines = 2 } }),
            (2.6, { withAnimation(.smooth) { lines = 3 } }),
            (3.6, { withAnimation(.smooth) { lines = 4 } })
        ])
    }

    private func point(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                .frame(width: 24, height: 24).background(.white, in: Circle())
            Text(text).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}
