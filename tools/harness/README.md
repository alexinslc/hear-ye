# Test harness

`harness.lua` runs the addon outside the game. It loads the files in `HearYe.toc` order, stands in for the game's functions and events, logs in, and drives whispers, Nearby, secret values and the commands. Then it logs out and back in, the way `/reload` does, and checks that history comes back. It also checks that a load that fails partway leaves saved history alone, and that old or damaged saved files still load.

It proves the addon's logic, not that the game has the functions it stands in for, so still try changes in the game.

## Running it

It needs [LuaJIT](https://luajit.org/) or any Lua 5.1, the same version the game uses. On a Mac, `brew install luajit`. From the repository:

```sh
luajit tools/harness/harness.lua
```

Every check should pass, ending in a line like `RESULT: 58 passed, 0 failed`. A failure prints `FAIL` with the check's name. The last line lists anything the addon read from the game that the harness doesn't provide, which is fine for things the addon checks for before using, such as the extra chat windows.

To test another copy of the addon, pass its folder:

```sh
luajit tools/harness/harness.lua addon/HearYe
```
