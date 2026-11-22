# Phase 4 record: persistence and polish

Status: **partly tested in game on 2026-11-21** (by remote control, solo).

## What changed

- **Saved history.** Saved per character, keyed by the character's GUID, in `HearYeDB.characters`. It's written on logout and `/reload`. The selected conversation, unread counts, drafts, class, level and Battle.net BattleTags are kept too.
- **Bounds (proposed defaults, not yet tuned).** Up to 500 lines per conversation, 5000 in total (the oldest go first), kept for 7 days. These are in `HearYeDB.history`.
- **What isn't saved.** Lines copied from the default chat that were secret are never saved. Saved player links lose their chat line ID, so a stale ID can't point a report at the wrong message. Battle.net links, whose IDs only last a session, are saved as plain text.
- **Groups after a reload.** A restored party, raid or instance group is kept only if someone from it is still in your group. Otherwise it becomes "Earlier party" and the new group starts fresh. A restored guild is ended only once guild data has loaded, 3 seconds after login, so it isn't dropped early.
- **Where typing goes after login.** The game resets the box to Say, so Hear Ye points it back at the restored conversation.
- **Settings (gear → Settings, or `/hearye setup`):**
  - Text size, with − and + steppers. Stepping back to the game's size returns it to "Game default".
  - Background opacity, in 10% steps.
  - A sound for party, raid and guild messages, using the game's own dropdown with a Play preview. The choices are None, Whisper chime, Map ping, Ready check and Raid warning, all built in. It doesn't play while you're already reading that conversation at the bottom, and plays at most once every 3 seconds. Whispers keep the game's own whisper sound.
  - Clear history, with a confirmation. `/hearye clear` does the same.
- **Day dividers.** Older saved lines get a "Saturday, November 21" divider, then "Today".
- **Scrolling keys.** Your Chat Page Up, Page Down, Scroll Up, Scroll Down and Chat Bottom bindings scroll Hear Ye while it's standing in for the default chat.
- **Recovery.** Saved settings are checked by type and range on load, so damaged or old values fall back to defaults. The schema went from 1 to 2, with a migration.

## Checks

| Check | Result |
| --- | --- |
| A whisper survives `/reload` with its class, level and selection | Pass |
| Unread counts survive `/reload` | Pass: a real incoming whisper kept its 2 unread |
| After `/reload`, Enter opens the restored conversation | Fixed during testing (it opened Say). Now opens "Tell Walt Coalbeard:". |
| Settings window: text size, opacity, sound dropdown, Play, Clear history | Pass: shown. Text size applied and returned to Game default. All five sounds are listed in this client. |
| Text size change redraws the lines on screen | Fixed during testing |
| Unknown level shows "-", and the unread badge is red | Pass (a real whisper from another player) |
| Saved under the character | Fixed during testing. It was "Walt-", because the realm name is empty here and the unit name leaves out the surname, so two Walts would have shared history. It's now the GUID. |
| Class colour from a whisper survives reload | Fixed after testing (the class file wasn't saved). Not re-checked. |
| Relogging, a different party after relog, a guild after relog | Not tested |
| Day dividers, the 7-day trim, the 5000-line cap | Not tested |
| Scrolling keybindings | Not tested |
| Clear history confirmation | Not tested (not clicked, so your history stayed) |
| Damaged saved file recovers | Not tested |

## Notes

- History saved under the old "Walt-" key wasn't carried over, because it was only test whispers. The entry stays in the saved file and does nothing.
- A row's name now uses the full width when it has no badge.

## Refinement: transparency (2026-11-21)

- **One opacity setting for the whole background.** It covers the frame, the border, both marble panels and the header rule. Text, names, badges and the input box keep full opacity. The range is 0–100% in steps of 10, and the default is now 50% (it was 92%). A schema 3 migration moves the old default to 50% only if it hadn't been changed.
- **Fade like the default chat.** A setting, on by default. The background shows while the mouse is over Hear Ye or you're typing, and fades out 1.5 seconds after you move away, leaving only the text.
- **Lowest drawing layer.** Hear Ye now draws on the BACKGROUND strata, so your character frame and other unit frames always draw over it.
- **Checked in game:** faded to nothing with the mouse away and back to 50% on hover. The character frame shows over Hear Ye in both states.

### Bugs found while doing this

- The fade handler was referenced before it was defined. That stopped Hear Ye partway through loading, and the default chat came back.
- **That broken load wiped saved history.** History never loaded in that session, and the reload then saved the empty state over it. The test whispers and two real whispers from another player were lost, and the game's `.bak` copy was one save too old to have them. A guard now saves history only if it finished loading in that session.
- The fade didn't start until a first value was set. Fixed.
- `/hearye status` now reports the background setting and its current state.
