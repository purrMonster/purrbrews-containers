# Game mode (roastery)

While a game runs, the LLMs get off the GPU. A game and a loaded model fight
over the 3080's 10 GB, and on Windows that doesn't fail: the driver spills into
system RAM and the game stutters. Lowering the model's priority doesn't help;
only freeing the VRAM does.

[`game-mode.ps1`](game-mode.ps1) checks every 5 seconds whether a game is running
and keeps [llama-swap](../llama-swap/README.md)'s active profile in step:

| | llama-swap profile | What clients get |
|---|---|---|
| A game starts | `gaming`, then every loaded model is unloaded | the CPU model, whatever they ask for |
| No game for 60 s | `normal` | the GPU models again, loaded on the next request |

The 60 seconds stop it flapping while a game restarts or a launcher hands over.
If llama-swap restarts mid-game it comes back as `normal`; the next poll puts
`gaming` back.

## What counts as a game

A running program whose path contains one of `GAME_PATHS` (Steam, Epic, Xbox,
GOG and Riot library folders by default) and none of `GAME_IGNORE` (the Epic
launcher, Steam's redistributables and SteamVR), or whose name is in
`GAME_EXES`. All three are in roastery's `.env.local`, semicolon-separated, with
`/` and `\` treated alike. Re-read every poll, so an edit applies within
seconds.

A game installed somewhere else goes in `GAME_EXES` by name (`game.exe`). That
also covers a game running elevated, whose path isn't readable from a normal
session (some anti-cheat setups do this).

## The flag

The flag is **llama-swap's active profile**. Anything that can reach llama-swap
can read it, and clients that ask for `assistant` or `fast` don't need to look
at all:

```powershell
curl.exe -s http://127.0.0.1:9292/api/profiles     # "active": "gaming" or "normal"
```

From the LAN it's `https://ollama.${DOMAIN}/api/profiles`, behind Authelia
(admins, or an `ollama_api_group` service account with Basic auth). That's the
one the control agent will read.

Two more ways to see it:

- **`state.json`** beside the script (gitignored): `gaming`, the `game`, `since`,
  and the profile llama-swap last confirmed, rewritten every poll.
- **`GAME_MODE_WEBHOOK_URL`** (optional, in `.env.local`): POSTed on every change
  with `{"gaming": true|false, "game": "...", "since": "...", "host": "<this PC's name>"}`.
  For Home Assistant, make an automation with a **Webhook** trigger, local only,
  POST, and put its URL here. The URL is a secret, so it stays in `.env.local`.

## Install

From an elevated PowerShell, in `stacks\roastery\game-mode`:

```powershell
.\game-mode.ps1 -Once     # what it sees and would do; changes nothing
.\install.ps1             # scheduled task at logon, started now
```

The task runs as you, not elevated, with **no time limit** (Windows' default of
3 days is what stopped Traefik's task on 2026-10-03). After a pull that changes
the script, run `.\install.ps1` again. `.\install.ps1 -Uninstall` removes it.

It needs Docker Desktop to start at login (*Settings → General → Start Docker
Desktop when you sign in*). Until llama-swap answers, the watcher logs one line
and keeps trying.

## Is it working?

1. `.\game-mode.ps1 -Once` with no game open: `game: none running`, `profile now: normal`.
2. Load a GPU model (a chat to `assistant`), then start a game. Within 5 s,
   `game-mode.log` shows `game started` and `profile normal -> gaming, models
   unloaded`, and `nvidia-smi` no longer lists `llama-server`.
3. Mid-game, a chat to `assistant` (or to `gemma-4-12b` by name) answers from
   `qwen3.5-4b-cpu`, and the game doesn't stutter.
4. Quit the game: a minute later the log says `back to normal`.

## Overriding it

To use the GPU models during a game anyway: `Stop-ScheduledTask
purrbrews-game-mode`, then pick `normal` on llama-swap's page (`/ui/`).
`Start-ScheduledTask purrbrews-game-mode` hands control back. While the task
runs, a profile picked by hand lasts one poll.

## Not covered

immich-ml uses the same GPU and can be busy indexing photos mid-game. Stopping
it too is a possible next step, not done (runbook, 2026-10-07).
