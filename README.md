# Wispr Media Controller

A [Hammerspoon](https://www.hammerspoon.org/) script that automatically silences your audio when you start dictating, and restores it when you stop.

Built for [Wispr Flow](https://www.wispr.com/) but works with any dictation tool that activates your microphone.

## How It Works

One simple rule: **when the mic is active, audio must be off.**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   Ctrl+Shift pressed (dictation hotkey)                         │
│   │                                                             │
│   ├─► Pause Spotify (AppleScript API — proper pause/resume)     │
│   │                                                             │
│   ├─► Mute system audio (silences Chrome/YouTube/everything)    │
│   │                                                             │
│   └─► Start mic watcher (polls every 500ms)                     │
│       │                                                         │
│       └─ Mic inactive?                                          │
│           ├─► Resume Spotify (if we paused it)                  │
│           ├─► Unmute system (if we muted it)                    │
│           └─► Stop polling                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The mic watcher uses macOS `audiodevice:inUse()` to detect actual hardware microphone state. This means:

- If dictation starts but the keypress handler misses, the watcher catches it
- If the keypress fires but dictation doesn't start, the watcher sees inactive mic and restores audio within 500ms
- Media that was already paused before dictation is never touched

## Why Two Strategies?

**Spotify** gets proper pause/resume via its AppleScript API. This stops playback and saves your position — you don't miss any of the song.

**Everything else** (Chrome, YouTube, any app) gets system-level mute/unmute. This is more reliable than trying to detect and control individual apps because:

- No AppleScript conflicts with other Chrome instances (Playwright, etc.)
- No accidentally starting paused videos (media keys are blind toggles)
- Works for any audio source without needing app-specific integrations
- Chrome videos continue playing silently — when unmuted you're right where you'd expect

For typical dictation bursts (a few seconds), the silent gap in Chrome audio is imperceptible.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/) (free, open source)
- A dictation tool that uses Ctrl+Shift as its hotkey (e.g., Wispr Flow)

## Installation

1. Install Hammerspoon if you haven't:
   ```bash
   brew install --cask hammerspoon
   ```

2. Clone this repo:
   ```bash
   git clone https://github.com/JakeRoyRandall/wispr-media-controller.git
   ```

3. Copy or symlink `init.lua` to your Hammerspoon config:
   ```bash
   # Option A: Use this as your entire Hammerspoon config
   cp wispr-media-controller/init.lua ~/.hammerspoon/init.lua

   # Option B: Source it from your existing config
   echo 'dofile("path/to/wispr-media-controller/init.lua")' >> ~/.hammerspoon/init.lua
   ```

4. Reload Hammerspoon (Cmd+Ctrl+R or click the menu bar icon > Reload Config)

## Configuration

The hotkey trigger is Ctrl+Shift (modifier keys only, no letter key). To change it, modify the `keyWatcher` event handler in `init.lua`.

The mic watcher polls every 500ms and the trigger has a 300ms debounce to prevent double-fires.

## How the Corner Cases Are Handled

| Scenario | What happens |
|----------|-------------|
| YouTube paused before dictation | System mutes, video stays paused, unmutes when done — video never starts |
| Spotify not running | AppleScript checks for process first, skips entirely |
| Dictation starts but keypress missed | Mic watcher detects active mic on next trigger |
| Keypress fires but dictation doesn't start | Mic watcher sees inactive mic, unmutes within 500ms |
| Double keypress | First mute wins, second is a no-op (already muted) |
| System already muted | Detected and skipped — won't unmute something you muted manually |
| Multiple Chrome instances (Playwright, etc.) | No conflict — system mute doesn't use AppleScript for Chrome |

## Debugging

Open the Hammerspoon console (click menu bar icon > Console) to see logs:

```
[WISPR] Ctrl+Shift DOWN
[WISPR] TRIGGER: mic=true
[WISPR] SPOTIFY: Pausing
[WISPR] SYSTEM: Muted output (MacBook Pro Speakers)
[WISPR] MIC WATCHER: Started
[WISPR] MIC WATCHER: Mic inactive — resuming
[WISPR] SPOTIFY: Resuming
[WISPR] SYSTEM: Unmuted output (MacBook Pro Speakers)
[WISPR] MIC WATCHER: Stopped
```

## Known Limitations

- **Spotify only for music apps**: Apple Music, Tidal, etc. are not currently supported. PRs welcome.
- **Chrome videos continue playing silently**: During dictation, Chrome videos are muted (not paused). For short dictation bursts this is imperceptible. For long dictation sessions, you may miss some video content.
- **System-wide mute**: All audio is muted during dictation, not just the media source. System sounds, notifications, etc. are also silenced.

## License

MIT
