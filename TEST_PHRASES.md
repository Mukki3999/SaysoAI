# Manual test phrases (real device, Apple Intelligence on)

Set up first: a few events today and tomorrow, one repeating event (e.g. weekly "Team sync"), two events with "Sam" in the title.

## Edit / cancel
- Simple edit: "Move my dentist appointment to 5 PM" -> before/after card, Approve, check Calendar, tap Undo.
- Ambiguous: "Move my meeting with Sam to 4" (two Sam events) -> Sayso asks which one; answer "the one at 2" -> single diff card.
- Recurring: "Cancel Team sync tomorrow" -> card shows "This event only / This and future"; Approve stays disabled until you pick.
- Bulk cancel: "Cancel everything after 5 today" -> one Cancel card per event, X on a card leaves it out, Approve all.
- Rename: "Rename my 3 PM to Strategy sync" -> title diff.
- Nothing found: "Cancel my yoga class" (none exists) -> "nothing found" answer, no sheet.

## Plan my day (button, or "Plan my day")
- Simple: "Finish the report for 2 hours, call mom for 15 minutes, gym for an hour" -> focus question -> morning -> timeline, per-block Approve / Move / Drop, Approve all, check the "Sayso Plan" calendar, Undo all.
- Packed day: fill 9-5 with meetings, then plan 3 one-hour tasks -> they land in "Doesn't fit" with Tomorrow / Shorten / Drop.
- Impossible deadline: "Prepare the deck, 3 hours, due at 11" at 9:30 AM -> reported whole in "Doesn't fit", Shorten offers what is left.
- Move conflict: Move a block onto a meeting -> red message, Move disabled.
- Day off: plan on a Saturday/Sunday -> "Today is one of your days off", Plan anyway.
- One-shot: "Plan my day: finish slides by 3, reply to emails" -> skips the first question.

## Rescue my day
- After a plan is approved: "I'm 45 minutes behind" (or Running behind? -> 45 minutes) -> moved/shortened blocks with old time struck, Approve all, Undo.
- "Re-plan the rest of my day" -> asks how far behind -> tap 30 min.
- Non-Sayso events never move: confirm meetings are untouched.
- No plan yet: say it with no plan -> "There's no Sayso plan for today yet".

## Permission denied
- Settings > Sayso > Calendars > None, then "Move my dentist to 5" -> error card with Open Settings.
- Same for Plan my day (button) -> error card with Open Settings.
- Planner Settings > "Allow full calendar access" when not yet asked.

## Without Apple Intelligence
- Turn Apple Intelligence off: unsupported screen shows "Plan my day manually" -> form -> same plan sheet.

## App Intents
- Shortcuts app > Sayso > "Plan my day" / "Rescue my day" (minutes parameter) -> app opens and starts the flow.

---

# Menu Helper manual tests (home screen > Menu)

For each photo: check the highlight lands on the right dish when you tap a card, and every result shows "Based on menu text, not allergy-safe. Check with the restaurant."

| Case | Photo / say | Expect |
|---|---|---|
| Clean printed menu | Photo of a normal printed menu. "Something light, vegetarian, under $20, not too spicy" | Chips appear (Vegetarian, Under $20, Not spicy, Light). Three picks, each a real dish with price and a one-line reason. No meat or fish dishes. |
| Handwritten / chalkboard | Photo of a chalkboard menu | Dishes found, or the clear "couldn't find any dishes" message. Never invented dishes. Straight-on, even light helps. |
| Dim photo | Photo in a dark restaurant | Fewer or messier dishes, still nothing invented. Retake prompt if nothing readable. |
| No prices | Menu with no prices. "Under $15" | Picks appear and a note says "This menu shows no prices, so the budget wasn't applied." |
| Vegetarian | "Vegetarian" | No meat/fish dishes. Dishes labelled (V) rank well. |
| Under $15 | "Under $15" | Every pick is $15 or less. |
| Follow-up change | After a result: "Make it vegan", then "What about dessert?" | Chips update (Vegan, then Dessert) and keep the rest. Results refresh. Tapping a chip's x removes it. |
| Impossible request | "Vegan, under $5, no mushrooms" | "No match" card explaining why (for example "Nothing is under $5. The cheapest match is $9."). No picks. |
| Two-column menu | Menu printed in two columns | Dishes read column by column, prices stay with their dish. |
| Apple Intelligence off | Any photo | Searchable list with Diet and Price chips. Tap a row to highlight it on the photo. |
| Mic | Tap the mic, say a preference, pause | Stops on its own and updates the picks. |
