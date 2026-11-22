# Phase 1 record: native control feasibility

Status: **partly tested in game on 2026-11-21** (by remote control, solo, out of combat). Rows without a result are still unverified.

## Target client

| | |
| --- | --- |
| Install | `/Applications/World of Warcraft/_forever_` |
| Client version | 1.60.1, build 71037 (from `.build.info`, product `wowf`) |
| TOC interface | `16001` (same as Fireside Tales, which loads in this client) |
| UI source checked | Gethe/wow-ui-source, `forever` branch, commit `734f065` ("1.60.1 (71037)"), an exact match for the installed build |
| UI family | Mainline with "camelot" overrides, so the modern engine: taint rules, secure commands, and secret values all apply |

The spike records `GetBuildInfo()` on login, so the saved variables confirm the build from inside the client too.

## What the source shows

- The chat input is `ChatFrame1EditBox` (and siblings), built from `ChatFrameEditBoxTemplate`. All parsing lives in its scripts: slash routes, `/r`, whisper target extraction, Tab (autocomplete and whisper cycling), history (`historyLines=32`), secure commands (`hash_SecureCmdList`) and emotes.
- Blizzard anchors the edit box only in XML (under its chat frame). No Lua re-anchors it, so moving it should stick.
- With `chatStyle = classic`, every open-chat path (`ChatFrameUtil.ChooseBoxForSend`) returns `DEFAULT_CHAT_FRAME.editBox`. With `im`, the last active window's box is used and stays visible.
- The client hands chat events **secret values** in some contexts. Blizzard's own filters check `canaccessvalue(...)` and skip addon callbacks when it fails.
- Player names can include surnames (`C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator`, `FirstName SecondName` whisper parsing). Never shorten a name used for sending.
- Clicking a player link goes through `SetItemRef` → `FriendsFrame_ShowDropdown` (right-click) or `ChatFrameUtil.SendTell` (left-click). Both expect a real chat frame as the source.

## Chosen integration approach

1. **Native input, moved.** Hear Ye moves the native edit box into its own input area by changing only its anchors. It doesn't replace any script, parse anything itself, or hold its own input box. The original anchors come back on `/hearye hide`, and a disabled addon never moves it at all.
2. **Sidebar → native.** Clicking a row sets the edit box's chat type, tell or channel target, and sticky type, then opens it with `ChatFrameUtil.OpenChat`, the same path the default UI uses.
3. **Native → sidebar.** A `hooksecurefunc` on the edit box's `UpdateHeader` follows `/p`, `/w Name`, `/1` and the reply key. The sidebar switches to the matching row when one exists. This hook doesn't change Blizzard's code path.
4. **Own display, native links.** A plain `ScrollingMessageFrame` shows the selected conversation. Links in it go to `SetItemRef` with `DEFAULT_CHAT_FRAME` as the source frame, so tooltips, menus and Shift-click behave like the default chat.
5. **Never filter the default chat.** Hear Ye doesn't remove or change messages. Even when its window is hidden, the default chat still has everything underneath.
6. **Secret values.** Hear Ye skips any event whose arguments fail `canaccessvalue`. Instead it copies the line the default chat formatted for it (through a hook on `ChatFrame1:AddMessage`) without inspecting it. Group messages go to their row, and unreadable whispers go to Game.
7. **Replacing the default chat.** Turning it on (a setup choice) moves the default chat frames, tabs and side buttons under a hidden parent. They keep receiving every message. Hiding Hear Ye, turning the option off, or opening Edit Mode puts them back.

## How to test

1. Install with `./install-addon.ps1`, or with the symlink described in the README, then restart the game.
2. Optional, for taint results: type `/console taintLog 1` before testing, then check `Logs/taint.log` afterwards.
3. Use `/hearye note <what you're about to try>` before each check, so the saved log reads in order.
4. Finish with `/hearye status`, then `/reload`. That writes the log to `WTF/Account/<account>/SavedVariables/HearYe.lua`, where I can read it.

## Compatibility checklist

Result key: pass / fail / partial, plus a note.

| # | Check | How | Result |
| --- | --- | --- | --- |
| 1 | Window appears over the chat area, moves, resizes, locks | Drag the header, drag the corner grip, click Lock | |
| 2 | Enter opens the input inside Hear Ye | Press Enter | |
| 3 | Escape cancels, then movement keys work again | Type, press Escape, press W | |
| 4 | Enter sends and returns movement | Type text, press Enter, press W | |
| 5 | Sidebar row sets the destination | Click Party (in a group), type, send | |
| 6 | Slash route moves the sidebar | Type `/p ` then `/s ` | |
| 7 | `/w Name` and an incoming whisper create one row | Whisper a friend, get a reply | |
| 8 | `/r` and the reply key binding | Rebind Reply to a key that isn't R and test both | |
| 9 | Tab autocomplete and whisper cycling | `/w Fr` then Tab; in a whisper, Tab cycles recent targets | |
| 10 | History recall | Up and Down arrows (Alt+arrows if your client needs them) | |
| 11 | Ordinary commands | `/roll`, `/who`, `/invite Name`, `/dance` | |
| 12 | Addon command | `/hearye status`, and another addon's command | |
| 13 | Secure commands typed in chat | `/target Name`, `/focus` (if the client has it), `/cast` on an out-of-combat spell | |
| 14 | Item and quest link insertion | Shift-click a bag item and a quest while typing | |
| 15 | Links in Hear Ye | Click an item link (tooltip), Shift-click it (insert) | |
| 16 | Player names in Hear Ye | Left-click (whisper), right-click (menu), and the menu's Invite and Whisper | |
| 17 | Scrolling up keeps position | Scroll up, have someone talk, check "New messages" | |
| 18 | Incoming messages don't steal focus | Type in Nearby while a whisper arrives | |
| 19 | Restricted context | Repeat 2, 4, 6 and 18 in combat, and in a dungeon encounter if possible | |
| 20 | `/hearye hide` puts the input back under the default chat | Hide, press Enter | |
| 21 | Disabling the addon leaves normal chat | Disable in the AddOn list, reload | |

## Results

Tested on 1.60.1 (71037), solo, guildless, Coldridge Valley, out of combat. The client's chat style is `im`, so the native edit box stays on screen, faded, between messages.

| # | Result |
| --- | --- |
| 1 | Pass, partly: shows over the chat area. Moving, resizing and locking weren't exercised. |
| 2 | Pass: Enter opens the native box inside Hear Ye with its own "Say:" header. |
| 3 | Pass, partly: Escape closes the box. Movement keys afterwards weren't checked. |
| 4 | Pass: `/roll` and a whisper sent from the box. |
| 7 | Pass: `/w Walt Coalbeard ...` (a surname) created one "Walt Coalbeard" row in class colour, with both the outgoing and incoming lines in it. Clicking the row set the box to "Tell Walt Coalbeard:". |
| 12 | Pass: `/hearye status`, `/hearye setup`, `/hearye firstrun` typed in the moved box. |
| 16 | Partial: left-clicking a name opens a whisper to it. Right-clicking your own name showed no menu; check this with another player's name. |
| — | Replacing chat: the default chat window, tabs and side buttons hide, and system lines (`/roll`, addon messages) appear in the Game row. |
| — | `/run` and `/dump` show the client's "Allow custom scripts?" prompt. It was declined, so they weren't used. |

Fixed during testing:
- With `im` chat style, the input hint showed through the faded edit box. It now draws on top and hides while you type.
- Pressing Enter while reading Game switched the sidebar to Nearby, because opening the box re-applies its sticky type. The sidebar now only follows a destination change made while typing.
- The welcome window opened during the loading screen and was closed straight away. It now waits 3 seconds after login.

## Known limitations of the spike

These are deliberate for Phase 1, and later phases cover them:

- History is in memory only and clears on `/reload`.
- Rows aren't added or removed automatically yet. Party and Guild grey out when they're unavailable, and other rows appear when a message arrives.
- No separate drafts per conversation.
- Channel rows are keyed by the channel's full name, so General can split into a new row when you change zones.
- Battle.net rows are keyed by the session's account ID. How that behaves across relogs isn't confirmed yet.
- Selecting a row also changes the native sticky chat type, which is intended but should be confirmed as the behavior you want.
