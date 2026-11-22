-- Hear Ye: shared namespace, saved variables, and the spike log.
local addonName, ns = ...
_G.HearYe = ns

ns.name = addonName
ns.SCHEMA = 3

-- Plain values; each is checked by type on load, so a damaged or old saved
-- file falls back to the default instead of breaking the window.
local defaults = {
	shown = true,
	locked = false,
	adoptInput = true,
	replaceChat = false, -- chosen in the quick setup
	setupDone = false,
	width = 500,
	height = 320,
	position = nil, -- { point, relativePoint, x, y } relative to UIParent
	fontSize = 0, -- 0: the game's chat font size
	opacity = 0.5,
	fadeBackground = true, -- hide the background when the mouse is away, like the default chat
	groupSound = "none", -- a sound for new party, raid and guild messages
}

-- Proposed bounds for saved history; not yet tuned in play.
local HISTORY_DEFAULTS = { days = 7, perConversation = 500, total = 5000 }

local function Clamp(value, low, high, fallback)
	value = tonumber(value)
	if not value or value ~= value then
		return fallback
	end
	return math.min(high, math.max(low, value))
end

-- Older saved files, oldest first.
local MIGRATIONS = {
	[1] = function(db)
		-- Schema 1 (Phases 1-3) had no saved history or settings.
		db.characters = {}
	end,
	[2] = function(db)
		-- The old default was nearly solid; move it to the new, lighter one
		-- unless it had been changed.
		if db.opacity == 0.92 then
			db.opacity = 0.5
		end
	end,
}

-- WoW can hand addons "secret" values in restricted contexts. Anything that
-- is not accessible must not be compared, indexed, or concatenated.
local canaccessvalue = _G.canaccessvalue
function ns.CanAccess(...)
	if not canaccessvalue then
		return true
	end
	return canaccessvalue(...)
end

local function ApplyDefaults(db)
	local schema = tonumber(db.schema) or 1
	while schema < ns.SCHEMA do
		if MIGRATIONS[schema] then
			MIGRATIONS[schema](db)
		end
		schema = schema + 1
	end
	db.schema = ns.SCHEMA

	for key, value in pairs(defaults) do
		if db[key] == nil or type(db[key]) ~= type(value) then
			db[key] = value
		end
	end
	if db.position ~= nil and (type(db.position) ~= "table" or type(db.position[1]) ~= "string" or tonumber(db.position[3]) == nil or tonumber(db.position[4]) == nil) then
		db.position = nil
	end
	db.width = Clamp(db.width, 360, 1200, defaults.width)
	db.height = Clamp(db.height, 200, 800, defaults.height)
	db.fontSize = Clamp(db.fontSize, 0, 24, 0)
	db.opacity = Clamp(db.opacity, 0, 1, defaults.opacity)

	db.characters = type(db.characters) == "table" and db.characters or {}
	db.history = type(db.history) == "table" and db.history or {}
	for key, value in pairs(HISTORY_DEFAULTS) do
		db.history[key] = Clamp(db.history[key], 1, value * 4, value)
	end
	if type(db.spike) ~= "table" then
		db.spike = {}
	end
	local spike = db.spike
	spike.log = type(spike.log) == "table" and spike.log or {}
	spike.restricted = type(spike.restricted) == "table" and spike.restricted or {}
end

local LOG_LIMIT = 300

-- The log lands in WTF/.../SavedVariables/HearYe.lua on /reload or logout,
-- so test results can be read back outside the game.
function ns:Log(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	if not ok then
		line = tostring(fmt)
	end
	local stamp = date("%Y-%m-%d %H:%M:%S")
	if not self.db then
		return
	end
	local log = self.db.spike.log
	log[#log + 1] = stamp .. " " .. line
	while #log > LOG_LIMIT do
		table.remove(log, 1)
	end
end

local PREFIX = "|cffd9b36cHear Ye|r: "

-- Our window covers the default chat, so status text goes to both.
function ns:Print(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	if not ok then
		text = tostring(fmt)
	end
	-- The default chat line is copied into Hear Ye's Game row; also show it
	-- where the player is looking.
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
	local C = self.Conversations
	if self.Messages and self.Messages.ShowNotice and C and C.selectedKey ~= "game" then
		self.Messages:ShowNotice(PREFIX .. text)
	end
end

function ns:RecordClient()
	local version, build, buildDate, interface = GetBuildInfo()
	local spike = self.db.spike
	spike.client = {
		version = version,
		build = build,
		buildDate = buildDate,
		interface = interface,
		chatStyle = GetCVar("chatStyle"),
		whisperMode = GetCVar("whisperMode"),
		hasCanAccessValue = _G.canaccessvalue ~= nil,
		hasSecretCheck = _G.issecretvalue ~= nil,
		hasChatFrameUtil = _G.ChatFrameUtil ~= nil,
		hasGetPlayerLink = _G.GetPlayerLink ~= nil,
		recordedAt = date("%Y-%m-%d %H:%M:%S"),
	}
	self:Log("client %s (%s) interface %s, chatStyle=%s", tostring(version), tostring(build), tostring(interface), tostring(spike.client.chatStyle))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		HearYeDB = type(HearYeDB) == "table" and HearYeDB or {}
		ApplyDefaults(HearYeDB)
		ns.db = HearYeDB
		events:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		ns:RecordClient()
		ns.Shell:Create()
		ns.Input:Init()
		ns.Messages:Init()
		ns.ChatReplace:Init()
		ns.Slash:Register()
		ns.Shell:SetShown(ns.db.shown)
		ns.Setup:Init()
		ns:Log("login complete")
	elseif event == "PLAYER_LOGOUT" then
		-- Also fires on /reload, right before saved variables are written.
		if ns.Conversations and ns.db then
			local ok, err = pcall(ns.Conversations.Save, ns.Conversations)
			if not ok then
				ns:Log("saving history failed: %s", tostring(err))
			end
		end
	end
end)
