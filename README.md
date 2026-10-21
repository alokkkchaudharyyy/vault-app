# Vault

<img src="assets/logo.svg" alt="Vault logo" width="96">

> **Credits:** Vault was created by [Atharv Tiwari](https://github.com/Atharv-tw)
> ([Atharv-tw/vault-app](https://github.com/Atharv-tw/vault-app)) and is used
> here with his permission under the [MIT License](LICENSE). This copy is
> developed further by [alokkkchaudharyyy](https://github.com/alokkkchaudharyyy).

A private second brain that your agents share. You talk or write to a diary
whenever something happens; every night your agent files it into a memory of
plain Markdown notes (who you are, your goals, projects, people, what you
learned and decided) and plans your next day around how you actually live.
Claude Code, Codex and any MCP agent read the same memory and the same plan,
so none of them starts from zero, and each one makes the next more personal.

It runs from a command line (`myvault`), an Android app with home-screen
widgets, a Linux desktop app, a GNOME top-bar widget and an MCP server.
Everything works offline. Your notes live in your own git repository, your
data syncs through your own Supabase project, and no paid AI API is needed.

**[Website](https://atharv-tw.github.io/vault-app/)** · [Quick start](#quick-start) · [How it works](#how-it-works) · [Commands](#commands) · [With agents](#with-agents) · [The apps](#the-apps) · [Build from source](docs/building.md)

## Quick start

**1. Install.** On 64-bit Linux, one line. No sudo, nothing to build.

```bash
curl -fsSL https://raw.githubusercontent.com/Atharv-tw/vault-app/main/scripts/install.sh | sh -s -- --app
```

That installs the `myvault` command and the desktop app (leave off
`-s -- --app` for the command alone), then starts the setup. For the phone,
download `vault-android-arm64.apk` from the
[latest release](https://github.com/Atharv-tw/vault-app/releases/latest).

**2. Answer five short questions.** `myvault init` asks, one at a time, and
Enter takes the default:

| Step | What it sets up |
| --- | --- |
| Your notes | A folder of Markdown notes, `~/Vault`, that opens in Obsidian. It starts with its own rules. |
| About you | Your name, your goals, when you wake and sleep. Your agents read this first. |
| Your agents | Connects Claude Code or Codex: the tool server and the skills, so they share your memory and plan. |
| GitHub | Optional: keeps your notes in a private repository, which a nightly routine in the cloud needs. |
| Sync | Optional: your own free Supabase project, so the phone app has your diary, plan and pages. |

`myvault init --yes` takes every default without asking. Run `myvault init`
again any time to change an answer, and `myvault doctor` to see what is set
up and what is left.

**3. Use it.**

```bash
myvault capture I have to send the draft to Priya by Friday   # anything, any time
myvault today                                                 # your day
myvault search draft                                          # notes, diary and tasks
myvault morning                                               # the page your agent wrote overnight
myvault routine                                               # set up the nightly routine
```

Or just talk to your agent: "what is on today?", "I woke at ten, re-plan my
day", "what did I decide about Helios?", "save this as a note".

## How it works

1. **Capture.** You write or say anything into the diary, from the phone
   (with offline speech), the laptop or the terminal. You never sort it.
2. **Memory.** Your agent files each entry into your vault: the day, the
   people you mention, your projects, what you learned, your decisions and
   ideas. Your exact words stay in `raw/`, which only the filing agent
   reads; every other agent reads the filed notes. Corrections you make
   become lines in `Rules.md`, so a mistake fixed once stays fixed.
3. **Plan.** Every commitment you mention becomes a task linked to the entry
   it came from. A nightly routine plans tomorrow from when you really wake,
   what really fits (75% of the time you have) and the routines you protect,
   and writes a **morning page**: the day, the facts, its guesses, what waits
   for your yes, and open questions. On Saturday night it writes a weekly
   page: what you decided and forgot, projects that stalled, how your
   routines went. Hard rules (deadlines never move silently, protected
   routines stay, nothing is lost to a cap) are checked by code, not trusted
   to the model.
4. **Shared by your agents.** Every agent you connect reads the same vault
   through the same tools. A code folder can be linked to a project, so an
   agent working there logs what it finished into that project's notes.
5. **It keeps itself healthy.** `myvault notes lint` checks the vault for
   broken links, notes missing from the index, stale pages and the like; the
   weekly run fixes what is safe and asks you about the rest.

The vault follows the [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
pattern: raw sources that never change, a wiki the agents keep current, and a
schema (the vault's `README.md`, with `CLAUDE.md` and `AGENTS.md` pointing to
it) that every agent follows.

## Commands

`myvault --help` lists them all, and `--json` on any command gives
machine-readable output. `todo`, the command's name before it became Vault,
still works.

| Your memory | |
| --- | --- |
| `myvault capture TEXT` | Put anything in the diary (alias `c`). |
| `myvault diary` | Recent entries, with what became of each. |
| `myvault search WORDS` | Your notes, diary and tasks, best match first (alias `s`). |
| `myvault note new TITLE` · `note show` · `note list` | Answers worth keeping, in `notes/`. |
| `myvault project list` · `new` · `log` · `link` | Projects, their work log, and code folders tied to them. |
| `myvault goals` · `goals add TEXT` | The goals in `Me.md`. |
| `myvault morning` · `myvault week` | The pages written overnight. |
| `myvault notes init` · `use` · `status` · `lint` · `save` · `publish` | The vault itself. |

| Your days | |
| --- | --- |
| `myvault today` · `list` · `show ID` | What is on, planned or backlogged. |
| `myvault add TITLE -d DATE -t HH:MM-HH:MM --due DATE --protect day` | A task, with its deadline kept apart from the day it is planned for. |
| `myvault edit` · `done` · `undo` · `rm` | Change, tick or remove. Moving a protected task or a deadline needs `--reason`. |
| `myvault habit` · `focus` · `usage` | Habits, focus sessions, screen time. |
| `myvault stats` · `check-plan` | What your days really look like; whether a plan holds. |

| Setup | |
| --- | --- |
| `myvault init` · `doctor` · `routine` | Set up, check, and the nightly routine's steps and prompt. |
| `myvault server` · `login` · `sync` · `schema` | Sync through your Supabase project. |
| `myvault mcp` | The tool server for agents. |

## With agents

`myvault mcp` is a tool server (MCP over stdio). `myvault init` registers it
with Claude Code and Codex and installs the skills. By hand:

```bash
claude mcp add --scope user myvault -- myvault mcp
codex mcp add myvault -- myvault mcp
```

Or, inside Claude Code, as a plugin: `/plugin marketplace add Atharv-tw/vault-app`,
then `/plugin install vault@vault-app` (use this or `myvault init`, not both).

- **Memory tools:** `search`, `read_note`, `add_note`, `list_projects`,
  `log_project_work`, `list_goals`, `morning_page`, `save_notes`,
  `vault_status`, `vault_lint`.
- **Day tools:** `today`, `list_tasks`, `add_task`, `update_task`,
  `set_task_done`, `delete_task`, `add_habit`, `set_habit_done`,
  `focus_start`, `focus_stop`, `stats`, `check_plan`, `screen_time`,
  `list_diary`, `add_diary_entry`, `set_diary_outcome`, `mark_diary_filed`.
- **Skills:** [vault-context](plugin/skills/vault-context/SKILL.md) (read
  only what a task needs, save answers worth keeping, log project work),
  [daily-briefing](plugin/skills/daily-briefing/SKILL.md) (re-plan the day)
  and [file-diary](plugin/skills/file-diary/SKILL.md) (file the diary into
  the vault).
- **Code folders:** `myvault project link Helios ~/code/helios` drops a
  local note there, kept out of git, that tells an agent working in it to log
  finished work to the Helios project.
- **ChatGPT and other chat apps** need a tool server on the internet; this
  one runs on your machine, so they are not supported.

## The nightly routine

A Claude Code session in the cloud runs every night just after midnight,
with your laptop off. It reads the day's diary, captures every commitment as
a task with its deadline, closes out the day, plans tomorrow, files the diary
into your vault, writes the morning page (and on Saturday the weekly page),
pushes the vault and syncs, so the phone has the page when you wake.
`myvault routine` prints the steps and a ready prompt to paste at
[claude.ai/code/routines](https://claude.ai/code/routines). It needs sync on
and your notes in a private GitHub repository. The full instructions the
agent follows are in [docs/briefing-agent.md](docs/briefing-agent.md).

## The apps

The Android and Linux app opens on your brain. Four tabs, with a **+** in the
middle of the bar that opens the diary box from anywhere:

- **Brain:** this morning's page, your goals, this week, your projects (tap
  for the overview). The phone cannot read the vault, so the laptop publishes
  these on every `myvault sync`.
- **To-do:** an activity grid, what is on now, and today's timeline of tasks
  and habits; the arrows walk to other days.
- **Diary:** write or speak anything. Speech is written down on the device
  by an open-source Whisper model: no key, no account, nothing you say leaves
  the phone. Each entry shows what Vault did with it once processed. Days that
  are over fold into one line each.
- **Profile:** what your notes say about you (`Me.md`), habits with streaks
  (including groups such as `5 meals / Breakfast`), screen time, sync, the
  calendar and voice.

Also: reminders when a task starts (a full-screen reminder when the phone is
locked, a banner when it is in use, each with *Doing it* and *Snooze*), a
two-way calendar on Android, home-screen widgets (today's list, a quick diary
entry that starts listening), a focus timer, and screen time on both devices.

**GNOME top-bar widget:** today's progress, the running task and the focus
countdown, and it records the laptop's screen time. Download
`vault-gnome-extension.zip` from the
[latest release](https://github.com/Atharv-tw/vault-app/releases/latest), then
`gnome-extensions install vault-gnome-extension.zip`, log out and back in, and
`gnome-extensions enable myvault@atharv.local`.

## Your vault

```
myvault notes init                     # creates ~/Vault with its rules and starter notes
myvault notes init --github my-vault   # and keeps it in a new private GitHub repository
myvault notes use PATH                 # point this device at a vault that exists
myvault notes status                   # where it is, and how much waits to be filed
myvault notes lint                     # check its health
```

| Note | What it holds |
| --- | --- |
| `README.md` | The schema: what goes where, who reads what, how notes change. Edit it and the filing follows. |
| `INDEX.md`, `log.md` | A map of every note, and one line per change. |
| `Me.md`, `Rules.md`, `Voice.md` | You and your goals; every correction you have made; how you write. |
| `raw/` | Your diary word for word. Only the filing agent reads it. |
| `days/`, `people/`, `projects/<Project>/`, `learning/`, `notes/` | The filed memory: each day, each person, each project (overview, log, info), what you learned, answers worth keeping. |
| `Decisions.md`, `Ideas.md` | Decisions with their reasons; ideas worth keeping. |
| `morning/`, `weekly/` | The pages written overnight. |

What you wrote never changes. Logs and lists only grow. Summaries such as a
project's overview are kept current, with a trace where a claim changed, and
git keeps every earlier version.

## Privacy

- Your diary, tasks and plan live in a file on each device and sync through
  a Supabase project that you own; row-level security keeps each user's rows
  apart. Without sync, everything works on one device.
- Your notes are a folder of Markdown files in your own git repository.
- Speech is written down on the device. No paid AI API is called by Vault;
  your agents run on your own Claude or Codex account.
- Agents never copy anything from the vault into a repository, a post or an
  outside service unless you ask for that piece, and none of them reads
  `raw/` except the filing agent.

## Sync (optional)

`myvault init` walks through it. By hand:

1. Create a [Supabase](https://supabase.com) project.
2. Open its SQL editor, paste the output of `myvault schema`, and run it. It is
   safe to run again after an update, and adds what a newer version needs.
3. Under Authentication, add a user (email and password) for yourself. Turn
   off public sign-ups if you do not want anyone else creating accounts in
   your project.
4. On the laptop: `myvault server https://YOUR-PROJECT.supabase.co sb_publishable_YOUR_KEY`,
   then `myvault login`.
5. In the app: tap the cloud icon, enter the same project URL and key, and
   sign in.

The publishable key is meant to ship in client apps; row-level security in
the schema is what keeps each user's rows private.

## Known limits

- Calendar sync runs on the phone only, so a laptop edit reaches the calendar after the phone next syncs (every 15 minutes in the background).
- Home-screen widgets need Android 12 or newer.
- On Samsung phones the banner shown while the phone is in use is a one-line pill unless *Settings > Notifications > Notification pop-up style* is set to *Detailed*.
- Reminders respect the phone's ringer mode: vibration on vibrate, nothing on mute or Do Not Disturb.
- Sync resolves conflicts per row, not per field: if two devices edit the same task while offline, the later edit replaces the earlier one.
- The phone shows what the laptop publishes of the vault, not the vault itself; reading every note on a phone needs Obsidian plus a git app.

## Build from source

See [docs/building.md](docs/building.md), which also covers the GNOME widget
and how releases are made.

## License

MIT. See [LICENSE](LICENSE).
