# Phase 3 record: compact conversation UI

Status: **partly tested in game on 2026-11-21** (by remote control, solo, Coldridge Pass).

## What changed

- **Sidebar.** Rows sit under "Channels" and "Whispers", as in the mockup. Each row has a small round dot: the chat type's colour for channels (your own chat colours), the class colour for people, and grey when the class isn't known or the row is read-only.
- **Unread badges.** A count sits on a small round badge: red for whispers and groups, dark grey for public channels so busy chat stays low-key. Game never counts as unread.
- **Levels.** Whisper rows show a small grey level, or "-" when it's unknown. Levels come only from what the client already has: a unit you can see (`UnitTokenFromGUID`), your friends list, your guild roster, or Battle.net. Hear Ye never sends `/who`. The tooltip says "Last known" and names the source. Class comes from the message's GUID or the same sources, and the tooltip always spells it out in words.
- **Conversation header.** It shows the name, plus context such as "Private - Level 1 - Paladin", "Dun Morogh /1", "3 players", your guild's name, or "Ended - history only". People get their full name here.
- **Flat rows.** Each line reads `time  [Name]: text`. Your own lines say `[You]`. "Says", "whispers" and "To" are dropped, while yells, emotes, leaders and raid warnings keep the game's wording. The time is a short grey one, unless you've turned on the game's own timestamps.
- **States.** An empty conversation says "No messages yet.", and an ended empty one says "Nothing was said here." A "New messages" divider marks where unread lines start when you open a conversation that you've read before.

## Checks

| Check | Result |
| --- | --- |
| Section headers, dots in chat-type and class colours | Pass |
| Whisper row level and header context | Pass: "Walt Coalbeard", level 1, "Private - Level 1 - Paladin" (from `UnitTokenFromGUID` on yourself) |
| `[You]` on your own lines, short grey time | Pass |
| Channel header shows zone and number | Pass: "General  Dun Morogh /1" |
| Flat channel row with class-coloured name and indented wrap | Pass |
| Unread badge can't be confused with a level | Fixed during testing: both showed as a plain "1". The count is now on a round badge. The grey channel badge was confirmed. |
| "No messages yet." | Pass |
| "New messages" divider | Not tested (needs unread lines arriving in a conversation you'd already read) |
| Unknown class or level shows "-" and grey | Not tested (needs a whisper from someone outside your group, friends and guild) |
| Long names, several unread contacts, non-English text | Not tested |

## Notes from testing

- Escape when the chat box is already closed opens the game menu, as it does in the default UI. Hear Ye doesn't change this.
- At the default 500 by 320 size, the window's right edge slightly overlaps your character frame. Resize Hear Ye, or move the frame in Edit Mode.
- Lines copied from the default chat (Game, and restricted messages) keep the default chat's format, so they have no short grey time. Their text may be secret, so Hear Ye can't add one.
