# stand

A macOS menu bar app that turns the workday into an upper back / neck rehab program. Every ~50 minutes it takes over the screen with an unskippable overlay, prompts an exercise, and only dismisses when you type the exercise-specific completion phrase.

## Why it works this way

Position rotation alone reduces static strain but builds no capacity — the durable fix for interscapular/neck pain is progressive strength training of the scapular retractors (mid/lower traps, rhomboids). This app delivers that training through the day using the existing sit/stand transitions as habit anchors:

- **Every transition (micro-dose):** 10 chin tucks, alternating with shoulder/neck mobility. Cheap enough to never resent.
- **Every 3rd transition (training set):** one hard set, rotating through band pull-aparts, face pulls, wall slides, and thoracic extension. This is the progressive-overload stimulus (~2-3 sets/day).
- **Skipping is allowed but logged.** Typing `skip` dismisses the exercise and puts it on your record. Tracking beats blocking.
- **Friday afternoon:** the overlay asks for a 0-10 weekly pain rating so the trend is visible over weeks.
- **Monday:** the first training prompt nudges progression (shorten grip / add band).
- **Menu bar** shows phase, training sets completed today, and day streak.

Keep a resistance band looped over your monitor arm or desk edge, permanently visible.

## Install

```bash
./install.sh
```

Compiles and installs a launchd agent that runs at login. Reconfigure by re-running with env vars:

```bash
STAND_INTERVAL=1800 STAND_DURATION=600 STAND_TRAINING_EVERY=4 ./install.sh
```

| Env var | Default | Meaning |
|---|---|---|
| `STAND_INTERVAL` | `3000` (50 min) | Seconds of sitting before the overlay fires |
| `STAND_DURATION` | `600` (10 min) | Seconds of standing before the sit alert |
| `STAND_TRAINING_EVERY` | `3` | Every Nth transition is a training set |

`./run.sh` compiles and runs in the foreground for testing. `./uninstall.sh` removes the launch agent.

## Menu bar controls

- **Trigger Stand Now / Trigger Training Set Now** — fire an overlay immediately
- **Snooze 30/60 Minutes** — delays the next overlay, then auto-resumes (there is deliberately no indefinite pause)
- **Show Stats** — today's sets, skips, streak, and recent pain ratings

## Log

Events append to `~/.stand/log.jsonl`, one JSON object per line:

```json
{"ts":"2026-08-21T17:03:12Z","day":"2026-08-21","event":"set_completed","exercise":"band_pull_aparts","kind":"training"}
{"ts":"2026-08-21T21:10:44Z","day":"2026-08-21","event":"pain_rating","score":4}
```

Event types: `set_completed`, `set_skipped` (kinds `training`/`micro`), `pain_rating`, `pain_check_skipped`.

Streak counts consecutive logged days with at least one completed training set; days with no log activity (weekends, days off) are skipped rather than breaking it.
