--[[
	Wispr Media Controller
	Rule: When microphone is active, audio must be off.
	Uses mic hardware state polling — no toggle, no guessing.
	https://github.com/JakeRoyRandall/wispr-media-controller
]]

require("hs.ipc")

local function log(msg)
	print("[WISPR] " .. msg)
end

-- State: what WE changed
local spotifyPausedByUs = false
local systemMutedByUs = false

-- Polling timer
local micWatcher = nil

-- ============================================================================
-- MIC STATE (macOS audiodevice hardware query)
-- ============================================================================
local function micIsActive()
	local dev = hs.audiodevice.defaultInputDevice()
	return dev and dev:inUse() or false
end

-- ============================================================================
-- SPOTIFY CONTROL (AppleScript — Spotify has its own scripting bridge)
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
-- SYSTEM MUTE (for Chrome/YouTube — avoids media key toggle problem)
-- Muting silences audio without changing play/pause state.
-- This means we never accidentally START a paused video.
-- ============================================================================
local function muteSystem()
	local dev = hs.audiodevice.defaultOutputDevice()
	if not dev then return end
	-- Only mute if not already muted (respect user's mute state)
	if not dev:muted() then
		dev:setMuted(true)
		systemMutedByUs = true
		log("SYSTEM: Muted output (" .. dev:name() .. ")")
	else
		log("SYSTEM: Already muted, skipping")
	end
end

local function unmuteSystem()
	if not systemMutedByUs then return end
	local dev = hs.audiodevice.defaultOutputDevice()
	if dev then
		dev:setMuted(false)
		log("SYSTEM: Unmuted output (" .. dev:name() .. ")")
	end
	systemMutedByUs = false
end

-- ============================================================================
-- PAUSE ALL MEDIA
-- ============================================================================
local function pauseAllMedia()
	local didAnything = false

	-- Spotify: proper pause via API (stops playback, saves position)
	if spotifyIsPlaying() then
		spotifyPause()
		spotifyPausedByUs = true
		didAnything = true
	end

	-- Everything else (Chrome/YouTube/etc): mute system output
	-- This silences audio without toggling play/pause state
	muteSystem()
	if systemMutedByUs then didAnything = true end

	if didAnything then
		hs.alert.show("\u{23F8}\u{FE0F}", 0.3)
	end

	return didAnything
end

-- ============================================================================
-- RESUME MEDIA WE CHANGED
-- ============================================================================
local function resumeOurMedia()
	local didAnything = false

	if spotifyPausedByUs then
		spotifyPlay()
		spotifyPausedByUs = false
		didAnything = true
	end

	if systemMutedByUs then
		unmuteSystem()
		didAnything = true
	end

	if didAnything then
		hs.alert.show("\u{25B6}\u{FE0F}", 0.3)
	end

	return didAnything
end

-- ============================================================================
-- MIC WATCHER: enforces "mic active = no audio"
-- ============================================================================
local function startMicWatcher()
	if micWatcher then micWatcher:stop() end

	log("MIC WATCHER: Started")
	micWatcher = hs.timer.doEvery(0.5, function()
		local micOn = micIsActive()

		if not micOn then
			-- Mic went inactive: resume what we changed, stop watching
			if spotifyPausedByUs or systemMutedByUs then
				log("MIC WATCHER: Mic inactive — resuming")
				resumeOurMedia()
			end
			if micWatcher then
				micWatcher:stop()
				micWatcher = nil
				log("MIC WATCHER: Stopped")
			end
		end
	end)
end

-- ============================================================================
-- TRIGGER
-- ============================================================================
local lastToggle = 0

local function onTrigger()
	local now = hs.timer.secondsSinceEpoch()
	if now - lastToggle < 0.3 then return end
	lastToggle = now

	log("TRIGGER: mic=" .. tostring(micIsActive()))
	pauseAllMedia()
	startMicWatcher()
end

-- ============================================================================
-- CTRL+SHIFT DETECTION
-- ============================================================================
local ctrlShiftDown = false
local keyWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(e)
	local f = e:getFlags()
	local down = f.ctrl and f.shift

	if down and not ctrlShiftDown then
		ctrlShiftDown = true
		log("Ctrl+Shift DOWN")
		local ok, err = pcall(onTrigger)
		if not ok then
			log("ERROR: " .. tostring(err))
		end
	elseif not down and ctrlShiftDown then
		ctrlShiftDown = false
	end

	return false
end)
keyWatcher:start()

hs.hotkey.bind({"cmd", "ctrl"}, "r", function() hs.reload() end)

log("Wispr Media Controller loaded")
hs.alert.show("Wispr Media Controller", 1)
