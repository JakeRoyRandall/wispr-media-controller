# Wispr Media Controller

A [Hammerspoon](https://www.hammerspoon.org/) script that automatically pauses your music and videos when you start dictating, and resumes them when you stop.

Built for [Wispr Flow](https://www.wispr.com/) but works with any dictation tool that activates your microphone.

## How It Works

One simple rule: **when the mic is active, audio must be off.**

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   Ctrl+Shift pressed (dictation hotkey)                         │
│   │                                                             │
│   ├─► Pause any playing media                                   │
│   │   ├─ Spotify: AppleScript API (direct, reliable)            │
│   │   └─ Chrome/YouTube: JavaScript injection into tabs         │
│   │                                                             │
│   └─► Start mic watcher (polls every 500ms)                     │
│       │                                                         │
│       ├─ Mic active + audio playing?                            │
│       │   └─► Pause it (catches any desync)                     │
│       │                                                         │
│       └─ Mic inactive + we paused something?                    │
│           ├─► Resume only what we paused                        │
│           └─► Stop polling                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The mic watcher uses macOS `audiodevice:inUse()` to detect actual hardware microphone state. This means:

- If dictation starts but the keypress handler misses, the watcher catches it
- If the keypress fires but dictation doesn't start, the watcher resumes audio immediately
- Media that was already paused before dictation is never touched

## Supported Media

| Source | Detection | Control |
|--------|-----------|---------|
| **Spotify** | AppleScript player state query | AppleScript play/pause |
| **YouTube** | JavaScript `video.paused` check across all Chrome tabs | JavaScript `video.pause()` / `video.play()` |
| **Any Chrome video** | Same as YouTube — scans all tabs for `<video>` elements | Same JavaScript injection |

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/) (free, open source)
- Google Chrome with **View > Developer > Allow JavaScript from Apple Events** enabled
- A dictation tool that uses Ctrl+Shift as its hotkey (e.g., Wispr Flow)

## Installation

1. Install Hammerspoon if you haven't:
   ```bash
   brew install --cask hammerspoon
   ```

2. Clone this repo:
   ```bash
   git clone https://github.com/jakerandall/wispr-media-controller.git
   ```

3. Copy or symlink `init.lua` to your Hammerspoon config:
   ```bash
   # Option A: Use this as your entire Hammerspoon config
   cp wispr-media-controller/init.lua ~/.hammerspoon/init.lua

   # Option B: Source it from your existing config
   echo 'dofile("path/to/wispr-media-controller/init.lua")' >> ~/.hammerspoon/init.lua
   ```

4. Enable Chrome JavaScript from Apple Events:
   - Open Chrome
   - Menu bar: **View > Developer > Allow JavaScript from Apple Events**
   - Enter your password when prompted

5. Reload Hammerspoon (Cmd+Ctrl+R or click the menu bar icon > Reload Config)

## Configuration

Edit the constants at the top of `init.lua`:

```lua
-- Polling interval (seconds) for mic watcher
local POLL_INTERVAL = 0.5

-- Debounce interval (seconds) to prevent double-triggers
local DEBOUNCE_INTERVAL = 0.3
```

The hotkey trigger is Ctrl+Shift (modifier keys only, no letter key). To change it, modify the `keyWatcher` event handler.

## How the Corner Cases Are Handled

| Scenario | What happens |
|----------|-------------|
| YouTube already paused before dictation | Not detected as playing, never touched, won't auto-start |
| Spotify not running | AppleScript checks for process first, skips entirely |
| Dictation starts but keypress missed | Mic watcher detects active mic + playing audio, pauses it |
| Keypress fires but dictation doesn't start | Mic watcher sees inactive mic, resumes audio within 500ms |
| Double keypress | First pause wins, second is a no-op (nothing playing) |
| Multiple Chrome windows/tabs | Scans all windows and tabs, pauses the first playing video found |
| Chrome not running | AppleScript checks for process first, skips Chrome control |

## Debugging

Open the Hammerspoon console (click menu bar icon > Console) to see logs:

```
[WISPR] TRIGGER: mic=true
[WISPR] SPOTIFY: Pausing
[WISPR] CHROME: Pausing win=1 tab=3
[WISPR] MIC WATCHER: Started
[WISPR] MIC WATCHER: Mic inactive — resuming media
[WISPR] SPOTIFY: Resuming
[WISPR] CHROME: Resuming win=1 tab=3
[WISPR] MIC WATCHER: Stopped
```

## Known Limitations

- **Chrome only**: Video detection uses Chrome's AppleScript API. Safari, Firefox, and Arc are not supported.
- **Multiple Chrome instances**: If another tool (e.g., Playwright) launches a separate Chrome instance, AppleScript may connect to the wrong one. The script handles this gracefully by skipping Chrome control rather than starting paused videos.
- **Spotify only for music apps**: Apple Music, Tidal, etc. are not currently supported. PRs welcome.

## License

MIT
