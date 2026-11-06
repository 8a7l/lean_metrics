# lean_metrics

Server performance metrics for Luanti (Minetest).

Read-only. No gameplay impact. No new nodes, no new entities.

## Commands

| Command | Description |
|---|---|
| `/metrics` | Main metrics: TPS, dtime, entities, memory, mods |
| `/metrics mods` | Top mods by registered node count |
| `/metrics entities` | Top mods by active entity count |
| `/metrics help` | Help |

## Privilege

`metrics` — required for all `/metrics` subcommands.
Granted to singleplayer by default.

## Settings

`lean_metrics_sample_interval` (float, default `2.0`, min `0.5`, max `60.0`) — how often (in seconds) the sampler recomputes TPS and average dtime.

## What it measures

- **TPS** — actual ticks per second, measured over the sample interval
- **Avg dtime** — average tick duration (ms)
- **Max dtime** — worst tick duration in the interval
- **Max lag** — highest lag observed since server start (built-in Luanti stat)
- **Uptime, players, Lua entities, Lua memory, mods, registered nodes/items/tools**
- **Top mods by node/entity count** — for finding bloated mods

## What it does NOT measure

- Loaded chunk count (no public Luanti API)
- Per-mod CPU time (would need a profiler)
- Per-tick breakdown (same)

Honest limits are better than fake numbers.

## How TPS is measured

One `globalstep` counts ticks (the only way to measure tick rate). A self-rescheduling `minetest.after` sampler recomputes TPS and dtime every `sample_interval` seconds. The globalstep does 2–3 arithmetic operations per tick — negligible.

## License

GPL-3.0-only. Copyright (C) 2026 8a7l.