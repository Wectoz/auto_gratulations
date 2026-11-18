# Auto Gratulations

> **Experimental / work in progress.** This is an unfinished test version, not a stable release. In-game testing is still required; bugs and client compatibility issues are expected.

<img src="icon.png" width="64" alt="Auto Gratulations icon">

Automatically congratulates group members in chat when they gain a level. Your
own level-ups are ignored.

## Installation

1. Copy this entire `auto_gratulations` folder into your WoW Forever installation's
   `Interface/AddOns` folder.
2. Restart WoW and enable **Auto Gratulations** in the character-selection AddOns menu.
3. Join a party. The addon starts enabled.

Targets WoW Forever 1.60.1 (build 70959, interface `16001`), checked against the
client UI source at
[Gethe/wow-ui-source@3d8abb1](https://github.com/Gethe/wow-ui-source/tree/3d8abb1da73acd38e412e24fb3f99454a6392346).
Run `/dump (select(4, GetBuildInfo()))` in game; if it prints another number, put
that number on the first line of [auto_gratulations.toc](auto_gratulations.toc).

## Options

Open them with `/ag`, or under **Options > AddOns > Auto Gratulations**.

| Option | Default | What it does |
|---|---|---|
| Congratulate level-ups | on | Master switch. |
| Send to | Group chat | Group chat (party, or raid chat in a raid) or a whisper to the player. |
| Which levels | Every level | Every level, every 5th, or every 10th. Max level always counts. |
| Shortest delay | 2 s | The wait before sending is random between the two delays (0-10 s). |
| Longest delay | 5 s | Set equal to the shortest delay for a fixed wait. |
| Random message order | off | Random pick instead of rotating through the list. |
| Also in raids | off | Raids are ignored unless this is on. |

The **Messages** page under it holds the message list: one message per line,
with `{name}` for the player's name and `{level}` for their new level. Changes
are saved as you type. Reaching max level uses the separate **Max level
message**; empty it to use the list instead. **Restore defaults** asks first, then brings back the built-in five and
**Preview in chat** shows the next message only to you.

Commands: `/ag` opens the options, `/ag on` and `/ag off` toggle the addon,
`/ag test` previews the next message. `/autogratulations` works too.

## Behavior and in-game checks

Levels are read when the game reports a level or group change. Joining a group,
reloading the UI, and loading screens establish a baseline without sending
anything. Unknown levels (offline or out-of-range members) are ignored. Levels
are tracked while the addon is disabled, so enabling it never congratulates an
old level-up. The game blocks addon chat during boss encounters and in some
instances; a congratulation due at that moment is skipped, not sent late.
Group members who level during the same delay share one message per level
("gz Ann and Bob on 10!"); whispers stay one per player.
Multiple users running this addon will each send their own congratulations.

`lua5.1 tests/test.lua` checks the tracking logic against a stubbed game API.
The addon has not yet been run inside the WoW Forever client. To verify in game:

1. Log in with no Lua errors; `/ag` opens the options and both pages render.
2. Join a party: no message should be sent for existing levels.
3. Have a party member level up: one congratulation appears after the delay.
4. Change each option and the message list, `/reload`, and confirm they are kept.
5. Disable the addon and observe a level-up: nothing is sent, also not after
   enabling it again.
6. Have two members level together (a shared quest turn-in): one message names both.
7. Run `/dump GetMaxPlayerLevel()`: it should print the real level cap, since
   the max level message relies on it.
8. Raid groups (with the raid option off) and your own level-ups produce no messages.

## Releasing

Commit, then build the zip for CurseForge, Wago or a GitHub release. It holds
only what the game needs, inside an `auto_gratulations` folder:

    git archive --prefix=auto_gratulations/ -o auto_gratulations-2.0.1.zip HEAD

## Feedback and contributions

Bug reports and pull requests are welcome on [GitHub](https://github.com/Wectoz/auto_gratulations/issues).
Include your WoW client version, addon version, steps to reproduce, and any Lua
error message. Remove personal information before posting logs or screenshots.

## License

The addon code is available under the [MIT License](LICENSE).
World of Warcraft names, trademarks, and game assets belong to their respective
owners. The license does not grant rights to those assets. This is an unofficial
community addon and is not affiliated with or endorsed by Blizzard Entertainment.
