# Phase 2 record: availability and routing

Status: **partly tested in game on 2026-11-21** (by remote control, solo, guildless, Coldridge Valley). Rows without a result are still unverified.

## What changed

- **Rows come from the client.** Party, Raid, Instance and Guild show only while you're in one. Channels come from the ones you've joined (`GetChannelName` for each local number, plus `C_ChatInfo.GetChannelInfoFromIdentifier`). They update on group, guild, channel and zone events, with no polling and no `/who`.
- **Stable channel identity.** Zone channels are keyed by their zone channel ID, which stays the same as you travel, so General is one row everywhere. Custom channels are keyed by name. The row shows the short name ("General"), and the hint and tooltip show the full one ("General - Dun Morogh", "/1 right now"). The local number is looked up again each time you send.
- **Restricted channel lines.** The client's API docs mark a chat event's channel name, number and zone channel ID as never secret. A restricted channel line copied from the default chat therefore still lands in its own channel row. Unreadable whispers still go to Game.
- **Group sessions.** When a party, raid, instance group or guild ends, its conversation becomes a grey, read-only "Earlier party" (or "Former guild") row. The next group starts empty, and an earlier session is never a send target. Only the most recent earlier session per group is kept, and an empty session isn't kept at all.
- **Send guards.** You can't send to a read-only row or a channel you've left. The row stays while you're reading it, and the hint says why. If a destination ends while you're typing to it, the text is saved with that conversation and the box is emptied, so Enter can't send it anywhere else. It moves to a new destination only when you pick one.
- **Drafts.** Each conversation keeps its own unsent text when you switch rows from the sidebar.
- **Whispers.** Character whispers are keyed by the full name the server sends. If two short names look the same, both rows show full names. Battle.net whispers are keyed by BattleTag, not the session's account ID, and the current account name is looked up when you send. Sending a whisper to someone new opens that conversation, while incoming messages never switch your view.

## Checks

| Check | Result |
| --- | --- |
| Solo and guildless: Nearby, joined channels and Game, with no Party or Guild row | Pass: Nearby, General, LocalDefense, Game |
| General shows the zone | Pass: "General" row, tooltip "General - Dun Morogh, /1 right now" |
| Joining a channel adds a row without changing the view | Pass: `/join HearYeTest` |
| Sending uses the current channel number | Pass: the box showed `[6. HearYeTest]:` and the message arrived there |
| Drafts are kept per conversation | Pass: typed in HearYeTest, switched to Nearby (empty box), switched back, and the draft returned |
| Leaving the selected channel keeps its history and blocks sending | Pass: grey row, history kept, hint "You left HearYeTest. Pick another conversation to reply." |
| A left channel drops off the list once you move away | Pass |
| Party and Guild appear and disappear | Not tested (needs a group or guild) |
| A new party doesn't inherit the old one | Not tested |
| General follows a zone change | Not tested |
| Channel renumbering | Not tested |
| Battle.net whispers, and identity after a reload | Not tested |
| A destination ending mid-draft | Not tested |

## Known limitations

- History still lives in memory and clears on `/reload` (Phase 4).
- The Officer row appears only after the first officer message, because officer chat depends on guild rank.
- A row's tooltip can show "Unsent message saved" for a moment after the draft has been restored, until you hover again.
