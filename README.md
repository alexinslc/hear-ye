# Hear Ye

A compact chat window for World of Warcraft: Forever. It keeps party, nearby, guild, and whisper conversations in one small window with a sidebar, so new players stop missing messages. The chat controls stay the game's own.

**Status: early testing (0.3.0).** Hear Ye can replace the default chat window, and the sidebar follows your group, guild and channels. Whispers, party, raid and guild keep their last 50 lines for a day, so a reload doesn't lose them. Test results are in [docs/phase-1-record.md](docs/phase-1-record.md), [docs/phase-2-record.md](docs/phase-2-record.md), [docs/phase-3-record.md](docs/phase-3-record.md), [docs/phase-4-record.md](docs/phase-4-record.md), and the full plan is in [docs/hear-ye-build-plan.md](docs/hear-ye-build-plan.md).

## Install

Get it from CurseForge, or download the zip from the latest GitHub release and unzip it into `World of Warcraft/_forever_/Interface/AddOns`.

## Install for development

The game reads the project folder directly through a link.

macOS:

```bash
ln -s "$PWD/addon/HearYe" "/Applications/World of Warcraft/_forever_/Interface/AddOns/HearYe"
```

With PowerShell 7 on either platform, `./install-addon.ps1` does the same, and `./install-addon.ps1 -Uninstall` removes the link. Restart the game after installing.

## Remove

Delete the `HearYe` link from `Interface/AddOns`, or disable Hear Ye in the AddOn list. The default chat is never changed, so it works as normal once Hear Ye is off.

## Commands

- `/hearye`: show or hide the window
- `/hearye setup`: the quick-setup window, also on the gear in the title bar
- `/hearye chat`: switch between Hear Ye and the default chat window
- `/hearye clear`: clear saved messages for this character (asks first)
- `/hearye firstrun`: show the welcome window again after the next `/reload`
- `/hearye lock` or `/hearye unlock`
- `/hearye reset`: put the window back over the default chat
- `/hearye status`: client build, chat style, and input state
- `/hearye note <text>`: add a marker to the test log

If another addon already uses `/hearye`, Hear Ye switches to `/hearyeaddon` and says so when you log in.

## Testing

```bash
luajit tools/harness/harness.lua
```

See [tools/harness/README.md](tools/harness/README.md). Releasing is in [docs/RELEASING.md](docs/RELEASING.md).

## Layout

- `addon/HearYe/`: the addon
- `art/`: the logo and banner, with their SVG sources
- `docs/`: the build plan, the design mockups, the phase records, release steps and the CurseForge listing
- `tools/`: the test harness, the release build, and `make-textures.py` for the icon
