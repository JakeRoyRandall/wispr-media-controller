--[[
	Wispr Media Controller for Hammerspoon
	Automatically pauses Spotify and Chrome/YouTube when your microphone activates.
	Resumes playback when the mic goes inactive.

	Rule: When the mic is active, audio must be off.

	https://github.com/JakeRoyRandall/wispr-media-controller
]]

require("hs.ipc")

local function log(msg)
	print("[WISPR] " .. msg)
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Hotkey that triggers your dictation tool (e.g., Wispr Flow, macOS Dictation)
-- Change these to match your setup
local TRIGGER_MODIFIERS = {"ctrl", "shift"}

-- Polling interval (seconds) for mic watcher
local POLL_INTERVAL = 0.5

-- Debounce interval (seconds) to prevent double-triggers
local DEBOUNCE_INTERVAL = 0.3

-- ============================================================================
-- STATE
-- ============================================================================

local spotifyPausedByUs = false
local chromePausedTab = nil
local micWatcher = nil

-- ============================================================================
-- MIC STATE DETECTION
-- ============================================================================

local function micIsActive()
	local dev = hs.audiodevice.defaultInputDevice()
	if dev then return dev:inUse() end
	return false
end

-- ============================================================================
-- SPOTIFY CONTROL
-- ============================================================================

local function spotifyIsPlaying()
	local ok, result = hs.osascript.applescript([[
		tell application "System Events"
			if not (exists process "Spotify") then return "false"
		end tell
		tell application "Spotify"
			if player state is playing then
				return "true"
			else
				return "false"
			end if
		end tell
	]])
	return ok and result == "true"
end

local function spotifyPause()
	log("SPOTIFY: Pausing")
	hs.osascript.applescript('tell application "Spotify" to pause')
end

local function spotifyPlay()
	log("SPOTIFY: Resuming")
	hs.osascript.applescript('tell application "Spotify" to play')
end

-- ============================================================================
-- CHROME VIDEO CONTROL
-- Scans all Chrome windows/tabs for a playing <video> element.
-- Requires: Chrome > View > Developer > Allow JavaScript from Apple Events
-- ============================================================================

local function findPlayingChromeVideo()
	local ok, result = hs.osascript.applescript([[
		tell application "System Events"
			if not (exists process "Google Chrome") then return "no_chrome"
		end tell
		tell application "Google Chrome"
			set winIndex to 0
			repeat with w in windows
				set winIndex to winIndex + 1
				set tabIndex to 0
				repeat with t in tabs of w
					set tabIndex to tabIndex + 1
					try
						set isPlaying to execute t javascript "
							var v = document.querySelector('video');
							(v && !v.paused) ? 'playing' : 'not_playing';
						"
						if isPlaying is "playing" then
							return (winIndex as string) & "," & (tabIndex as string)
						end if
					end try
				end repeat
			end repeat
			return "none"
		end tell
	]])
	if ok and result and result ~= "none" and result ~= "no_chrome" then
		return result
	end
	return nil
end

local function pauseChromeTab(tabRef)
	local parts = {}
	for part in string.gmatch(tabRef, "[^,]+") do
		table.insert(parts, tonumber(part))
	end
	log("CHROME: Pausing win=" .. parts[1] .. " tab=" .. parts[2])
	hs.osascript.applescript(string.format([[
		tell application "Google Chrome"
			try
				execute tab %d of window %d javascript "document.querySelector('video').pause();"
			end try
		end tell
	]], parts[2], parts[1]))
end

local function resumeChromeTab(tabRef)
	local parts = {}
	for part in string.gmatch(tabRef, "[^,]+") do
		table.insert(parts, tonumber(part))
	end
	log("CHROME: Resuming win=" .. parts[1] .. " tab=" .. parts[2])
	hs.osascript.applescript(string.format([[
		tell application "Google Chrome"
			try
				execute tab %d of window %d javascript "
					var v = document.querySelector('video');
					if (v && v.paused) v.play();
				"
			end try
		end tell
	]], parts[2], parts[1]))
end

-- ============================================================================
-- PAUSE / RESUME ORCHESTRATION
-- ============================================================================

local function pauseAllMedia()
	local pausedAnything = false

	if spotifyIsPlaying() then
		spotifyPause()
		spotifyPausedByUs = true
		pausedAnything = true
	end

	local tab = findPlayingChromeVideo()
	if tab then
		pauseChromeTab(tab)
		chromePausedTab = tab
		pausedAnything = true
	end

	if pausedAnything then
		hs.alert.show("\u{23F8}\u{FE0F}", 0.3)
	end

	return pausedAnything
end

local function resumeOurMedia()
	local resumedAnything = false

	if spotifyPausedByUs then
		spotifyPlay()
		spotifyPausedByUs = false
		resumedAnything = true
	end

	if chromePausedTab then
		resumeChromeTab(chromePausedTab)
		chromePausedTab = nil
		resumedAnything = true
	end

	if resumedAnything then
		hs.alert.show("\u{25B6}\u{FE0F}", 0.3)
	end

	return resumedAnything
end

-- ============================================================================
-- MIC WATCHER
-- Polls microphone state and enforces the core rule:
--   mic active  + audio playing → pause audio
--   mic inactive + we paused something → resume audio, stop polling
-- ============================================================================

local function startMicWatcher()
	if micWatcher then micWatcher:stop() end

	log("MIC WATCHER: Started")
	micWatcher = hs.timer.doEvery(POLL_INTERVAL, function()
		local micOn = micIsActive()

		if micOn then
			local spotPlaying = spotifyIsPlaying()
			local chromeTab = findPlayingChromeVideo()
			if spotPlaying or chromeTab then
				log("MIC WATCHER: Mic active but audio playing — pausing")
				pauseAllMedia()
			end
		else
			if spotifyPausedByUs or chromePausedTab then
				log("MIC WATCHER: Mic inactive — resuming media")
				resumeOurMedia()
				if micWatcher then
					micWatcher:stop()
					micWatcher = nil
					log("MIC WATCHER: Stopped")
				end
			end
		end
	end)
end

-- ============================================================================
-- HOTKEY TRIGGER
-- ============================================================================

local lastToggle = 0

local function onTrigger()
	local now = hs.timer.secondsSinceEpoch()
	if now - lastToggle < DEBOUNCE_INTERVAL then
		log("DEBOUNCED")
		return
	end
	lastToggle = now

	log("TRIGGER: mic=" .. tostring(micIsActive()))
	pauseAllMedia()
	startMicWatcher()
end

-- ============================================================================
-- KEY DETECTION
-- Listens for Ctrl+Shift modifier combo (flagsChanged event).
-- This fires when the modifier keys are pressed, before any letter key.
-- ============================================================================

local ctrlShiftDown = false
local keyWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(e)
	local f = e:getFlags()
	local down = f.ctrl and f.shift

	if down and not ctrlShiftDown then
		ctrlShiftDown = true
		local ok, err = pcall(onTrigger)
		if not ok then
			log("ERROR: " .. tostring(err))
			hs.alert.show("Error: " .. tostring(err), 2)
		end
	elseif not down and ctrlShiftDown then
		ctrlShiftDown = false
	end

	return false
end)
keyWatcher:start()

-- ============================================================================
-- RELOAD HOTKEY
-- ============================================================================

hs.hotkey.bind({"cmd", "ctrl"}, "r", function()
	hs.reload()
end)

-- ============================================================================

log("Wispr Media Controller loaded")
hs.alert.show("Wispr Media Controller", 1)
