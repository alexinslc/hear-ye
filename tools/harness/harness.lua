-- Headless smoke test for Hear Ye: stubs the WoW API, loads the addon the way
-- the client does (TOC order), and drives its flows, including a /reload.
-- It proves the addon's Lua logic, NOT that the stubbed APIs exist in the client.
--
-- Run it with LuaJIT or any Lua 5.1:
--   luajit tools/harness/harness.lua [addon folder]
-- The addon folder defaults to addon/HearYe next to this tools folder.
local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ADDON_DIR = (arg and arg[1]) or (scriptDir .. "/../../addon/HearYe")
local ADDON = "HearYe"
local realG = _G
local stdPrint = print

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		stdPrint("  FAIL " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
	end
end

local function section(name, fn)
	stdPrint(name)
	local ok, err = pcall(fn)
	check(name .. " runs without errors", ok, err)
end

local function tocFiles()
	local files = {}
	local toc = assert(io.open(ADDON_DIR .. "/" .. ADDON .. ".toc"), "no TOC in " .. ADDON_DIR)
	for line in toc:lines() do
		line = line:gsub("\r$", "")
		if line:match("%.lua$") and not line:match("^#") then
			files[#files + 1] = line
		end
	end
	toc:close()
	return files
end

local unknownGlobals = {}

-------------------------------------------------------------------------------
-- One game session: a fresh set of stubs, the addon loaded, and its events.
-- Pass the saved table from an earlier session to stand in for a /reload.
-------------------------------------------------------------------------------

local function Boot(savedDB, opts)
	opts = opts or {}
	local S = {
		chat = {}, -- lines the default chat received
		timers = {},
		callbacks = {},
		eventFrames = {},
		now = 1800000000,
		inGroup = false,
		inGuild = false,
	}

	-- Frames: modelled methods do what the addon reads back; any other
	-- capitalized method or template child is a callable stub object, so
	-- frame:SetBackdrop(...) and check.Text:SetText(...) both work.
	local methods = {}
	local function newObject(parent)
		local o = setmetatable({ _scripts = {}, _events = {}, _parent = parent, _w = 0, _h = 0, _lines = {} }, methods)
		return o
	end
	methods.__call = function() return nil end
	methods.__index = function(self, key)
		local m = rawget(methods, key)
		if m then
			return m
		end
		if type(key) == "string" and key:find("^%u") then
			local child = newObject(self)
			rawset(self, key, child)
			return child
		end
		return nil
	end
	function methods:SetScript(what, fn) self._scripts[what] = fn end
	function methods:GetScript(what) return self._scripts[what] end
	function methods:HookScript(what, fn)
		local old = self._scripts[what]
		self._scripts[what] = function(...)
			if old then old(...) end
			fn(...)
		end
	end
	function methods:RegisterEvent(event)
		if not self._listening then
			self._listening = true
			S.eventFrames[#S.eventFrames + 1] = self
		end
		self._events[event] = true
	end
	function methods:UnregisterEvent(event) self._events[event] = nil end
	function methods:Show()
		if self._hidden then
			self._hidden = false
			if self._scripts.OnShow then self._scripts.OnShow(self) end
		end
	end
	function methods:Hide()
		if not self._hidden then
			self._hidden = true
			if self._scripts.OnHide then self._scripts.OnHide(self) end
		end
	end
	function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
	function methods:IsShown() return not self._hidden end
	function methods:IsVisible() return not self._hidden end
	function methods:SetAlpha(a) self._alpha = a end
	function methods:GetAlpha() return self._alpha or 1 end
	function methods:SetSize(w, h) self._w, self._h = w, h end
	function methods:SetWidth(w) self._w = w end
	function methods:SetHeight(h) self._h = h end
	function methods:GetWidth() return self._w end
	function methods:GetHeight() return self._h end
	function methods:GetSize() return self._w, self._h end
	function methods:GetNumPoints() return 0 end
	function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
	function methods:GetCenter() return 0, 0 end
	function methods:GetLeft() return 0 end
	function methods:GetTop() return 0 end
	function methods:GetEffectiveScale() return 1 end
	function methods:GetFrameLevel() return 1 end
	function methods:GetParent() return self._parent end
	function methods:SetParent(p) self._parent = p end
	function methods:GetName() return self._name end
	function methods:IsMouseOver() return false end
	function methods:HasFocus() return false end
	function methods:GetChecked() return self._checked end
	function methods:SetChecked(v) self._checked = v end
	function methods:SetText(text) self._text = text ~= nil and tostring(text) or nil end
	function methods:GetText() return self._text end
	function methods:GetStringWidth() return #(self._text or "") * 6 end
	function methods:GetStringHeight() return 12 end
	function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "" end
	function methods:CreateFontString() return newObject(self) end
	function methods:CreateTexture() return newObject(self) end
	function methods:CreateMaskTexture() return newObject(self) end
	-- ScrollingMessageFrame
	function methods:AddMessage(text, r, g, b) self._lines[#self._lines + 1] = text end
	function methods:Clear() self._lines = {} end
	function methods:AtBottom() return true end
	function methods:GetNumMessages() return #self._lines end
	function methods:GetScrollOffset() return 0 end

	local named = {}
	local function CreateFrame(_, name, parent)
		local f = newObject(parent)
		if name then
			f._name = name
			named[name] = f
		end
		return f
	end

	local function fire(event, ...)
		for _, f in ipairs(S.eventFrames) do
			if f._events[event] and f._scripts.OnEvent then
				f._scripts.OnEvent(f, event, ...)
			end
		end
	end
	S.fire = fire

	local function runTimers()
		local pending = S.timers
		S.timers = {}
		for _, fn in ipairs(pending) do fn() end
	end
	S.runTimers = runTimers

	local editBox = newObject(nil)
	editBox._name = "ChatFrame1EditBox"
	function editBox:SetChatType(t) self._chatType = t end
	function editBox:GetChatType() return self._chatType or "SAY" end
	function editBox:SetStickyType(t) self._sticky = t end
	function editBox:SetTellTarget(t) self._tell = t end
	function editBox:GetTellTarget() return self._tell end
	function editBox:SetChannelTarget(id) self._channel = id end
	function editBox:GetChannelTarget() return self._channel end
	S.editBox = editBox

	local chatFrame1 = newObject(nil)
	chatFrame1._name = "ChatFrame1"
	chatFrame1.editBox = editBox
	function chatFrame1:AddMessage(text, r, g, b)
		S.chat[#S.chat + 1] = text
	end

	local hookedSecure = {}
	local function hooksecurefunc(t, name, fn)
		if type(t) == "string" then
			t, name, fn = nil, t, name
		end
		if t then
			local old = t[name]
			t[name] = function(...)
				local r = { old(...) }
				fn(...)
				return unpack(r)
			end
		end
		hookedSecure[#hookedSecure + 1] = name
	end

	local guid = "Player-1-00000001"
	local stubs = {
		CreateFrame = CreateFrame,
		hooksecurefunc = hooksecurefunc,
		UIParent = newObject(nil),
		ChatFrame1 = chatFrame1,
		ChatFrame1EditBox = editBox,
		DEFAULT_CHAT_FRAME = chatFrame1,
		ChatFontNormal = newObject(nil),
		GameTooltip = newObject(nil),
		GameTooltip_Hide = function() end,
		UISpecialFrames = {},
		SlashCmdList = {},
		StaticPopupDialogs = {},
		StaticPopup_Show = function(which) S.popup = which end,
		SetItemRef = function() end,
		PlaySound = function() end,
		SOUNDKIT = {},
		YES = "Yes", NO = "No", DONE = "Done",
		RAID_CLASS_COLORS = {},
		ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end }),
		LE_PARTY_CATEGORY_HOME = 1,
		LE_PARTY_CATEGORY_INSTANCE = 2,
		Constants = { ChatFrameConstants = { MaxChatChannels = 20 } },
		EventRegistry = {
			RegisterCallback = function(_, name, fn) S.callbacks[name] = fn end,
		},
		C_Timer = { After = function(_, fn) S.timers[#S.timers + 1] = fn end },
		C_ChatInfo = {
			GetChannelInfoFromIdentifier = function() return nil end,
		},
		C_FriendList = {},
		C_BattleNet = {},
		C_ClassColor = {},
		C_Texture = { GetAtlasInfo = function() return nil end },
		ChatFrameUtil = {
			GetActiveWindow = function() return nil end,
			ChooseBoxForSend = function() return editBox end,
			OpenChat = function() end,
			GetChatCategory = function(t) return t end,
		},
		MenuUtil = { CreateContextMenu = function() end },
		TimeUtil = nil,
		canaccessvalue = function(...)
			for i = 1, select("#", ...) do
				if S.SECRET ~= nil and select(i, ...) == S.SECRET then return false end
			end
			return true
		end,
		GetBuildInfo = function() return "1.60.1", "71037", "Nov 1 2026", 16001 end,
		GetCVar = function(name) return name == "chatStyle" and "im" or nil end,
		GetCVarBool = function() return false end,
		GetTime = function() return S.now end,
		time = function() return S.now end,
		date = function(fmt, t) return os.date(fmt, t or S.now) end,
		UnitGUID = function(unit) if unit == "player" then return guid end end,
		UnitName = function(unit) if unit == "player" then return "Walt", "" end end,
		UnitLevel = function() return 5 end,
		UnitClass = function() return "Warrior", "WARRIOR" end,
		UnitIsUnit = function(a, b) return a == b end,
		UnitTokenFromGUID = function() return nil end,
		GetRealmName = function() return "Forever" end,
		GetPlayerInfoByGUID = function() return nil end,
		GetPlayerLink = function(name, text) return "|Hplayer:" .. name .. ":12:WHISPER|h" .. text .. "|h" end,
		GetBNPlayerLink = function(name, text) return "|HBNplayer:" .. name .. ":1|h" .. text .. "|h" end,
		GetDefaultLanguage = function() return "Common" end,
		GetChannelName = function() return 0 end,
		IsInGroup = function() return S.inGroup end,
		IsInRaid = function() return false end,
		IsInGuild = function() return S.inGuild end,
		GetGuildInfo = function() return nil end,
		GetNumGroupMembers = function() return 0 end,
		GetNumGuildMembers = function() return 0 end,
		InCombatLockdown = function() return false end,
		BNGetNumFriends = function() return 0 end,
		Ambiguate = function(name) return (name:gsub("%-.*", "")) end,
		strlower = string.lower, strupper = string.upper,
		strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
		tinsert = table.insert,
		unpack = unpack,
		HearYeDB = savedDB,
	}
	for k, v in pairs(opts.stubs or {}) do stubs[k] = v end

	local env = setmetatable({}, {
		__index = function(_, key)
			local value = stubs[key]
			if value ~= nil then return value end
			value = named[key]
			if value ~= nil then return value end
			value = realG[key]
			if value == nil then unknownGlobals[key] = true end
			return value
		end,
	})
	env._G = env
	S.env = env

	local ns = {}
	S.ns = ns
	S.loadErrors = {}
	for _, file in ipairs(opts.files or tocFiles()) do
		local chunk, err = loadfile(ADDON_DIR .. "/" .. file)
		if not chunk then
			S.loadErrors[#S.loadErrors + 1] = err
		else
			setfenv(chunk, env)
			local ok, runErr = pcall(chunk, ADDON, ns)
			if not ok then
				S.loadErrors[#S.loadErrors + 1] = file .. ": " .. tostring(runErr)
			end
		end
	end

	function S.login()
		fire("ADDON_LOADED", ADDON)
		local ok, err = pcall(fire, "PLAYER_LOGIN")
		S.loginOK, S.loginError = ok, err
		return ok, err
	end

	-- What the client writes to SavedVariables on /reload or logout.
	function S.logout()
		fire("PLAYER_LOGOUT")
		return rawget(env, "HearYeDB")
	end

	-- A chat event with the fields Hear Ye reads, in the game's order.
	function S.chatEvent(event, text, sender, fields)
		fields = fields or {}
		fire(event, text, sender, fields.language or "", "", "", "", fields.zoneChannelID or 0,
			fields.channelIndex or 0, fields.channelName or "", 0, fields.lineID or 1, fields.guid or "",
			fields.bnetID or 0, false, false, false, nil)
	end

	function S.slash(text)
		local handler
		for key, fn in pairs(stubs.SlashCmdList) do
			if key:find("HEARYE") then handler = fn end
		end
		assert(handler, "no /hearye handler")
		handler(text)
	end

	return S
end

local function lineCount(conv)
	return conv and #conv.lines or 0
end

local function hasLine(conv, needle)
	for _, l in ipairs(conv and conv.lines or {}) do
		if tostring(l.text):find(needle, 1, true) then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Checks
-------------------------------------------------------------------------------

local first -- the first session, kept for the reload checks
local savedAfterFirst

section("Loading and logging in", function()
	local S = Boot(nil)
	check("every file loads", #S.loadErrors == 0, table.concat(S.loadErrors, "; "))
	local ok, err = S.login()
	check("PLAYER_LOGIN runs", ok, err)
	local db = S.ns.db
	check("saved settings exist", type(db) == "table")
	check("schema is current", db.schema == S.ns.SCHEMA, db.schema)
	check("opacity default is 0.5", db.opacity == 0.5, db.opacity)
	check("history is marked loaded", S.ns.Conversations.loaded == true)
	check("a Nearby row exists", S.ns.Conversations:Get("nearby") ~= nil)
	check("a Game row exists", S.ns.Conversations:Get("game") ~= nil)
	S.runTimers()
	check("the welcome window asks on first login", S.ns.Setup ~= nil)
	first = S
end)

section("Whispers", function()
	local S = first
	local C = S.ns.Conversations
	S.chatEvent("CHAT_MSG_WHISPER", "hey, want to group?", "Brana Tester-Forever", { guid = "Player-1-00000002", lineID = 41 })
	local conv = C:Get(C:EnsureWhisper("Brana Tester-Forever").key)
	check("an incoming whisper makes a row", conv ~= nil)
	check("the row has the line", hasLine(conv, "want to group"))
	check("the incoming line counts as unread", conv and conv.unread == 1, conv and conv.unread)
	S.chatEvent("CHAT_MSG_WHISPER_INFORM", "sure, one sec", "Brana Tester-Forever", { guid = "Player-1-00000001", lineID = 42 })
	check("your reply joins the same row", lineCount(conv) == 2, lineCount(conv))
	check("your reply shows as [You]", hasLine(conv, "[You]"))
	S.chatEvent("CHAT_MSG_SAY", "hello there", "Someone-Forever", { guid = "Player-1-00000003" })
	check("Say goes to Nearby", hasLine(C:Get("nearby"), "hello there"))
end)

section("Secret values", function()
	local S = first
	local C = S.ns.Conversations
	S.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
	local before = lineCount(C:Get("nearby"))
	S.chatEvent("CHAT_MSG_SAY", S.SECRET, "Someone-Forever")
	check("a secret event is skipped", lineCount(C:Get("nearby")) == before)
	local stats = S.ns.db.spike.restricted.CHAT_MSG_SAY
	check("the skip is counted", stats and stats.seen == 1)
end)

section("Commands", function()
	local S = first
	for _, cmd in ipairs({ "", "status", "lock", "unlock", "hide", "show", "chat", "chat", "reset", "setup", "help", "note testing" }) do
		local ok, err = pcall(S.slash, cmd)
		check("/hearye " .. cmd .. " runs", ok, err)
	end
	check("lock is saved", S.ns.db.locked == false)
	local ok, err = pcall(S.slash, "clear")
	check("/hearye clear asks first", ok and S.popup == "HEARYE_CLEAR_HISTORY", err or S.popup)
end)

section("Saving on logout", function()
	local db = first.logout()
	local key = "Player-1-00000001"
	local saved = db.characters[key]
	check("history saved under the character's GUID", type(saved) == "table")
	local found
	for k, conv in pairs(saved and saved.convs or {}) do
		for _, l in ipairs(conv.lines) do
			if l.text:find("want to group", 1, true) then found = l end
		end
	end
	check("the whisper is in the saved copy", found ~= nil)
	check("saved player links lose their line ID", found and not found.text:find(":41:", 1, true), found and found.text)
	savedAfterFirst = db
end)

section("Reloading keeps history", function()
	local S = Boot(savedAfterFirst)
	local ok, err = S.login()
	check("PLAYER_LOGIN runs after a reload", ok, err)
	local C = S.ns.Conversations
	local conv
	for _, c in ipairs(C:Sorted()) do
		if c.chatType == "WHISPER" then conv = c end
	end
	check("the whisper row comes back", conv ~= nil)
	check("its lines come back", lineCount(conv) == 2, lineCount(conv))
	S.logout()
	check("a second save keeps it", hasLine(conv, "want to group"))
end)

section("A broken load doesn't wipe history", function()
	-- Leave out Shell.lua so login fails partway, like the bug that once
	-- saved an empty history over the real one.
	local files = {}
	for _, f in ipairs(tocFiles()) do
		if f ~= "Shell.lua" then files[#files + 1] = f end
	end
	local S = Boot(savedAfterFirst, { files = files })
	S.login()
	check("login fails without the window", S.loginOK == false)
	local db = S.logout()
	local saved = db.characters["Player-1-00000001"]
	local count = 0
	for _, conv in pairs(saved and saved.convs or {}) do count = count + #conv.lines end
	check("the saved history is still there", count >= 3, count)
end)

section("Old and damaged saved files", function()
	local S = Boot({ schema = 1, opacity = 0.92 })
	S.login()
	check("schema 1 moves to the current schema", S.ns.db.schema == S.ns.SCHEMA)
	check("the old 92% default becomes 50%", S.ns.db.opacity == 0.5, S.ns.db.opacity)

	S = Boot({ schema = 3, width = "wide", height = 99999, opacity = 7, position = "middle", characters = 5, history = { days = -3 }, spike = "x" })
	local ok, err = S.login()
	check("a damaged file still loads", ok, err)
	local db = S.ns.db
	check("a bad width falls back", db.width == 500, db.width)
	check("a huge height is limited", db.height == 800, db.height)
	check("opacity is limited to 100%", db.opacity == 1, db.opacity)
	check("a bad position is dropped", db.position == nil)
	check("bad history settings fall back", db.history.days == 1, db.history.days)
	check("a bad characters table is replaced", type(db.characters) == "table")

	S = Boot({ schema = 3, characters = { ["Player-1-00000001"] = { convs = { bad = 5, ["x"] = { lines = "no" } } } } })
	ok, err = S.login()
	check("damaged saved conversations are skipped", ok, err)
end)

-------------------------------------------------------------------------------

local unknown = {}
for k in pairs(unknownGlobals) do unknown[#unknown + 1] = k end
table.sort(unknown)
stdPrint(string.format("RESULT: %d passed, %d failed", passed, failed))
if #unknown > 0 then
	stdPrint("Not provided by the harness (fine if the addon checks first): " .. table.concat(unknown, ", "))
end
os.exit(failed == 0 and 0 or 1)
