# Hear Ye build plan and AI handoff

Build a compact chat addon for **World of Warcraft: Forever** that helps a new player notice and follow conversations. Use a Slack-like sidebar and one conversation pane while preserving familiar WoW chat controls. **The user has selected Hear Ye as the final addon name.**

The design has been explored in an interactive HTML mockup. **No WoW addon has been implemented or tested in game.** Treat the mockup as a visual and interaction reference, not production code or proof of API compatibility.

## Naming requirements

- Public addon name and in-game title: **Hear Ye**. Preserve the two words and capitalization.
- Use **Hear Ye** throughout the interface, README, installation instructions, and any future CurseForge project title. The naming decision is settled; do not substitute an earlier candidate or invent a new working name.
- Technical addon identifier and installation folder: `HearYe`; TOC file: `HearYe/HearYe.toc`; TOC display title: `Hear Ye`.
- Use the `HearYe` prefix for addon-owned globals and `HearYeDB` for the main saved-variable table, unless repository conventions require a clearly documented adjustment.
- Preferred settings command: `/hearye`. Check for a conflict in the target environment before finalizing its registration.
- If a CurseForge project is created later, try the slug `hear-ye`. Public search found no exact listing, but slug availability has not been confirmed or reserved.

## Read these companion files

- `hear-ye-demo.html`: standalone browser preview of the selected design. Its controls below the chat simulate location, party membership, guild membership, and joined public channels. These controls are not part of the proposed addon UI.
- `hear-ye-reference.fragment.html`: editable mockup source for inspecting layout and sample interactions.

The written requirements below govern implementation where the mockup is incomplete. Start with the native-control feasibility phase before building the full interface.

## User problem and product direction

The user's friend is new to Forever and misses party messages, nearby /say messages, and whispers in the default scrolling chat. A clearer conversation structure and visible unread indicators are the primary goals.

The user rejected Krakenchat's UI, ZChat's appearance, iChat Pro Max's confusing presentation, and Chattynator's limited change to the experience. **Whisper Messenger is the closest reference**, but the user wants something smaller and simpler. Do not reproduce any of the rejected interfaces.

The selected mockup is **Unified sidebar**. Keep channels and whisper contacts together in a narrow left pane, with the selected conversation on the right. Do not return to the alternate layout with channels across the top without a new reason or user direction.

## Agreed requirements

### Compact visual design

- Start around **500 by 320 pixels**, with a **136-pixel sidebar**, at the reference display scale. These are starting dimensions, not a guaranteed match to every WoW UI scale.
- Position the addon over the normal chat area. Allow moving, resizing, and locking it. Validate the actual footprint in the user's client rather than assuming browser pixels equal WoW UI units.
- Use compact flat message rows, restrained borders, a dark readable surface, and minimal chrome. Preserve readable text as the window gets smaller.
- Whisper rows show a short display name, class color, a separate small level number, and an unread badge when needed.
- Preserve the full character name for tooltips, disambiguation, and sending. Abbreviated names must never become recipient identifiers.
- Use a neutral fallback when class or level is unknown. A dash is suitable for an unknown level. Never invent a level or imply that a cached level is necessarily current.
- Expose the active reply destination clearly in the input area. Class colors must not be the only way to understand identity: provide a textual class description on hover and where accessible.

### Channels appear automatically

The sidebar reflects real availability and membership. It is not a channel-creation interface.

| Destination | Required behavior |
| --- | --- |
| Nearby | Provide the local conversation feed, including /say. If yell or emotes are combined into this feed, preserve their message type and explicit sending mode. |
| Party | Show only while in a relevant party. |
| Guild | Show only while in a guild. |
| General | Show when actually joined and available; display the current zone context. |
| Trade | Show when actually joined and available. Do not implement availability by checking a hardcoded list of cities. |
| Whispers | Create a row when a conversation starts, including outgoing whispers. Preserve character and Battle.net recipient distinctions. |

For native-control parity, also account for Raid, Instance, Officer, and other standard built-in channels when the client exposes them and the player can use them. Keep unavailable or unauthorized destinations out of the normal list. Native commands can retain their normal behavior without adding custom channel creation or management controls to the addon.

Remove the old **+ Channels** interaction entirely. Users should not have to add Party, Guild, General, or Trade manually. Stable channel identity must survive local channel-number changes; resolve the current number when sending `/1`, `/2`, and similar commands.

If a selected destination becomes unavailable, remove its active sidebar row, keep its displayed history readable, and prevent sending to that destination. Preserve an unfinished draft. Allow an explicit switch to a valid destination; never silently redirect the draft. The mockup disables its input in this case; the real implementation must reconcile that design with native command access.

### Conversations and attention

- Selecting a sidebar row displays its history and establishes an explicit reply destination.
- Incoming messages update the relevant unread indicator without switching the selected conversation, opening a competing window, or taking keyboard focus.
- Define read state from actual viewing. A selected conversation scrolled into older messages should not silently consume new messages as read.
- Keep drafts separate by destination. Switching between two people must not carry one person's draft into the other's input.
- Keep the active party's history separate from an unrelated party joined later. Archived party sessions must not become send targets for a new group.
- Preserve sensible history across `/reload` and relogging. Bound saved history and provide a clear way to clear it.
- Keep busy public-channel activity from visually overwhelming private and group conversations. Start with unobtrusive public-channel unread styling and stronger whisper/group badges; notification thresholds are proposed defaults to validate.
- Optional message sounds should use built-in choices with previews. Additional sound-manager addons should not be required for basic notifications.

## Native chat control compatibility

The user explicitly requires controls that are **almost identical to built-in chat**. Preserve muscle memory and configured keybindings. Do not replace WoW's command system with an incomplete custom parser.

| Area | Acceptance requirement |
| --- | --- |
| Enter and Escape | Match the client's normal input activation, send, cancel, autocomplete, and focus behavior as closely as possible. Do not trap movement keys after typing. |
| Reply | Respect the configured native reply binding and `/r`; do not hardcode the letter R. |
| Chat routes | Preserve `/s`, `/y`, `/p`, `/g`, `/w`, numbered channels, and other applicable native routes. Selecting a row and choosing the same destination by command must agree. |
| Tab | Preserve native autocomplete and whisper-recipient cycling. Do not assign Tab to Slack-style sidebar navigation. |
| Editing | Preserve native history recall, cursor movement, text selection, modifier keys, and configured arrow-key behavior. Verify the actual client defaults. |
| Commands | Preserve ordinary commands such as `/roll`, `/who`, `/invite`, emotes, and addon slash commands. Restricted commands must use a supported native path rather than become ordinary chat text. |
| Names | Preserve click and modifier behavior and native player context menus, including applicable whisper, invite, friend, ignore, and report actions. |
| Links | Preserve supported item, spell, quest, achievement, and player links, tooltips, clicks, and Shift-click insertion where available on Forever. |
| Scrolling | Preserve expected chat scrolling and modifiers. Reading older messages must not jump to the bottom on every incoming message. |
| Window behavior | Support familiar moving, sizing, locking, font-size, and background controls while keeping configuration small. |

These are implementation requirements, not claims that the HTML preview implements them. Document any unavoidable differences precisely rather than declaring full parity after checking only Enter and `/p`.

## Technical approach to investigate

### Verify the target client first

Read repository instructions before editing. Locate the actual Forever install and record the client version and interface number from the running client or current installation. Verify relevant API names, frame templates, and restriction behavior against that build. Do not assume Classic Era or Retail compatibility, force an obsolete TOC version, or treat an old addon listing as conclusive evidence.

Use the client's existing input, slash-command, hyperlink, and player-menu behavior wherever feasible. Investigate whether a native chat edit box and native chat frames can be adapted to this layout without fighting their secure lifecycle. If a separate display is necessary, keep native input and protected interactions intact. Choose the smallest arrangement that passes the compatibility checks.

Avoid committing to a complete event-driven replacement until the native-control spike establishes how input, links, and restricted messages will work.

### Keep responsibilities separate

Use small modules for availability discovery, conversation identity and storage, native input integration, rendering, unread state, and settings. The precise file names are implementation choices.

Conversation identity should distinguish character whispers, Battle.net whispers, guilds, group sessions, local context, and public channels. Do not key contacts by shortened display names, friend-list positions, or transient identifiers assumed to survive relogging. Resolve and validate the actual recipient before sending.

Discover party and guild membership and joined public channels from current client state. Reconcile after relevant membership, channel, login, and zone events. Verify the exact events in the target build. Avoid constant polling and automatic `/who` traffic merely to fill missing level labels.

Store messages, drafts, and unread information separately from rendered rows. Preserve native link payloads rather than stripping everything to plain text. Handle unknown identities and unavailable metadata without blocking message delivery.

Use bounded saved variables with a schema version and migrations. Proposed starting defaults are per-character history, up to 500 messages per conversation, a total cap, and seven-day retention; tune these after basic usability and performance checks. These numerical defaults have not been approved by the user.

### Restricted contexts and recovery

Test the actual Forever restrictions during combat, encounters, and other relevant protected contexts. Do not assume every Retail restriction applies identically. Do not inspect, compare, search, or serialize values the client marks inaccessible.

Keep a reliable native fallback. Do not suppress the original message display until the custom path can safely present it. If the addon cannot display or send a message in a context, make the native route available and clearly communicate the state. Avoid duplicate messages during normal operation and gaps during fallback transitions.

Do not defer a send and later transmit it to a destination that has changed. Recover cleanly after combat, zone changes, group changes, and reloads. Restore usable native chat when the addon is disabled.

Build original addon code. Use other addons as product references; verify the specific source license before reusing third-party implementation code.

## Build phases

### Phase 1 Native control feasibility

Build the smallest installable Forever addon that can position a minimal custom shell over the chat area and exercise a supported native input path. Validate Enter, Escape, reply binding, slash routes, an addon slash command, Tab, history, links, and native menus. Test in an ordinary session and a restricted context.

Deliver a short record of the tested client build, chosen integration approach, failures, and remaining limitations. If essential native behavior cannot coexist with the design, propose the smallest adjustment before building the full display.

### Phase 2 Availability and routing

Implement the automatic channel list and stable conversation identifiers. Cover solo, party, guildless, guilded, zone transitions, public-channel joins/leaves, and channel renumbering. Validate full Forever character names and Battle.net recipients. Preserve unavailable drafts and guard every send destination.

### Phase 3 Compact conversation UI

Implement the selected Unified sidebar design, flat message history, class/level fallbacks, unread indicators, and separate drafts. Wire both native routes and sidebar selection into the same destination state. Keep sample messages and preview-state controls out of the shipped addon.

### Phase 4 Persistence and polish

Add bounded history, small settings, position and size persistence, optional notification sounds, long-name disambiguation, and robust scrolling. Verify practical readability over the game at the user's resolution and UI scale.

### Phase 5 Compatibility and packaging

Run the acceptance checks below. Deliver source, an installable addon ZIP with the correct folder structure, installation and rollback instructions, the tested build, and known limitations. Do not describe untested behaviors as working.

## Acceptance checks

1. A new solo, guildless character sees Nearby and whichever supported public channels are actually joined, with no Party or Guild row.
2. Party and Guild rows appear and disappear as membership changes, without manual configuration or focus changes.
3. General follows joined zone context. Trade follows actual availability. Local channel-number changes do not misroute messages.
4. Leaving a selected party or channel preserves its visible history and draft while blocking sends there. Selecting a valid route works explicitly.
5. An unrelated new party has a new session and never inherits the old party as its recipient.
6. Two whisper recipients with similar or abbreviated names remain distinct. Full surnames and current Battle.net identities route correctly after reload or friend-list changes.
7. Incoming party, local, character-whisper, and Battle.net messages remain noticeable while another conversation is open. They never steal focus or redirect typing.
8. Unknown level or class information does not hide a contact, crash the UI, or display fabricated data.
9. Native keyboard, command, name-menu, and hyperlink behaviors pass the compatibility matrix, including nondefault reply bindings.
10. During a client-restricted context, messages retain a working native display/send path. Normal behavior resumes afterward without replaying messages or stale sends.
11. Scrolling up keeps the reader's position. New activity is indicated, and returning to recent messages is easy.
12. `/reload` and relogging preserve intended history, drafts, settings, and position. Corrupt or old settings recover safely.
13. The compact UI remains legible with long names, long messages, non-English characters, several unread contacts, and all applicable channels visible.
14. Public-channel bursts do not cause excessive frame work, unbounded storage, or repeated full-history redraws.
15. Disabling the addon restores usable default chat.

Use automated tests where they help verify routing, identity resolution, availability transitions, history bounds, and migrations. Native UI behavior, protected contexts, and real message delivery require in-game checks; mocked tests and browser screenshots cannot establish those results.

## Research references

Reference material was reviewed during design on November 20, 2026. Recheck the exact client build and pin source revisions during implementation.

- [Forever native chat input source](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua): parsing, input lifecycle, autocomplete, history, and whisper cycling.
- [Forever native chat frame source](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrame.lua): native hyperlink dispatch and message/channel registration.
- [Whisper Messenger](https://www.curseforge.com/wow/addons/whisper-messenger): closest product reference; not the chosen design to clone.
- [Whisper Messenger comments](https://www.curseforge.com/wow/addons/whisper-messenger/comments): a limited reviewed sample identified input-focus friction, notification audibility, shortcut discoverability, and requests for simpler access to common actions. This was not a review of every comment.
- [Whisper Messenger compact mode release notes](https://www.curseforge.com/wow/addons/whisper-messenger/files/9549537): an existing compact alternative, useful when comparing footprint and behavior.
- [ChatExtension](https://www.curseforge.com/wow/addons/chatextension): author-documented sources for cached player levels and the need for unknown-level handling.

## First instruction to the implementing AI

Read this plan and the companion mockup. Inspect the target environment and repository instructions. Implement **Phase 1 Native control feasibility** first, report what was actually verified, and then continue through the phases when the evidence supports the approach. Preserve the selected compact design, automatic channel discovery, full recipient identity, and familiar WoW controls throughout.
