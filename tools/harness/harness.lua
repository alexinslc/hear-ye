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
		SetItemRef = function(link, text, button, source) S.itemRef = { link = link, button = button, source = source } end,
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
			TriggerEvent = function(_, name) S.triggered = name end,
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
			OpenChat = function() S.opened = (S.opened or 0) + 1 end,
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
		GetMouseFoci = function() return { S.mouseFocus } end,
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
		GetGuildInfo = function() return S.inGuild and S.guildName or nil end,
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
	check("a Say row exists", S.ns.Conversations:Get("nearby") ~= nil and S.ns.Conversations:Get("nearby").label == "Say")
	check("a Game row exists", S.ns.Conversations:Get("game") ~= nil)
	S.runTimers()
	check("the welcome window asks on first login", S.ns.Setup ~= nil)
	first = S
end)

section("Placement", function()
	local S = Boot(nil)
	S.env.UIParent:SetSize(2560 / 1440 * 768, 768) -- 1440p at the default UI scale
	S.login()
	local frame = S.ns.Shell.frame
	check("the window is invisible until the bars are placed", frame:GetAlpha() == 0)
	S.fire("EDIT_MODE_LAYOUTS_UPDATED")
	S.runTimers()
	check("it appears once they are", frame:GetAlpha() == 1)
	local w, h = frame:GetSize()
	check("it sizes itself for the screen", w == math.floor(2560 / 1440 * 768 * 0.36) and h == math.floor(768 * 0.42), w .. "x" .. h)

	S = Boot(nil)
	S.login()
	S.fire("PLAYER_ENTERING_WORLD")
	S.runTimers()
	check("it appears even without a layout event", S.ns.Shell.frame:GetAlpha() == 1)

	-- The player frame sits above the bars, centre-left: the window stops
	-- short of it instead of reaching under it.
	local player = {
		IsVisible = function() return true end,
		GetEffectiveScale = function() return 1 end,
		GetLeft = function() return 380 end, GetRight = function() return 510 end,
		GetBottom = function() return 120 end, GetTop = function() return 190 end,
	}
	S = Boot(nil, { stubs = { PlayerFrame = player } })
	S.env.UIParent:SetSize(2560 / 1440 * 768, 768)
	S.login()
	S.fire("EDIT_MODE_LAYOUTS_UPDATED")
	S.runTimers()
	local pw = S.ns.Shell.frame:GetWidth()
	check("it stops short of the player frame", pw <= 380 - 6 - 16 and pw >= 300, pw)

	S = Boot({ schema = 5, layout = "under" })
	S.login()
	check("a saved Under my character layout is cleared", S.ns.db.layout == nil and S.ns.db.schema == S.ns.SCHEMA)

	S = Boot({ schema = 3, position = { "BOTTOMLEFT", "BOTTOMLEFT", 40, 200 }, width = 700, height = 380 })
	S.login()
	check("a window resized before keeps its size", S.ns.db.sized == true and S.ns.Shell.frame:GetWidth() == 700)
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
	check("Say goes to the Say row", hasLine(C:Get("nearby"), "hello there"))
end)

section("Battle.net friends by BattleTag", function()
	local S = first
	local C = S.ns.Conversations
	S.env.C_BattleNet.GetAccountInfoByID = function(id)
		if id == 77 then return { battleTag = "WhiteFinch#1368", accountName = "Real Person", bnetAccountID = 77 } end
	end
	S.chatEvent("CHAT_MSG_BN_WHISPER", "hi from bnet", "Real Person", { bnetID = 77 })
	local conv = C:Get("bn:whitefinch#1368")
	check("a Battle.net row is named by BattleTag", conv and conv.label == "WhiteFinch", conv and conv.label)
	check("the #1368 part isn't shown in the name", conv and conv.fullName == "WhiteFinch")
	check("the whole BattleTag is kept for the tooltip", conv and conv.battleTag == "WhiteFinch#1368")
	check("the header line says Battle.net without the tag", S.ns.Shell.Context(conv) == "Battle.net")
	local shown = conv and conv.lines[#conv.lines].text or ""
	check("the message shows the BattleTag", shown:find("WhiteFinch", 1, true) ~= nil, shown)
	check("the real name only stays inside the link", select(2, shown:gsub("Real Person", "")) <= 1, shown)
	local visible = shown:gsub("|H.-|h", ""):gsub("|h", "")
	check("the real name isn't in the visible text", not visible:find("Real Person", 1, true), visible)
	check("whispers still go to the account", conv and conv.tellTarget == "Real Person")
	local game = C:Get("game")
	local before = #game.lines
	S.env.ChatFrame1:AddMessage("Real Person has come online.", 0.5, 0.8, 1, nil, nil, nil, "CHAT_MSG_BN_INLINE_TOAST_ALERT", {})
	check("Battle.net notices are left out while real names are hidden", #game.lines == before)
	S.ns.db.hideRealNames = false
	C:RelabelBNet()
	check("with real names shown, the row uses the real name", conv.label == "Real Person", conv.label)
	S.env.ChatFrame1:AddMessage("Real Person has come online.", 0.5, 0.8, 1, nil, nil, nil, "CHAT_MSG_BN_INLINE_TOAST_ALERT", {})
	check("and Battle.net notices come back", #game.lines == before + 1)
	S.ns.db.hideRealNames = true
	C:RelabelBNet()
	check("hiding them again goes back to the BattleTag", conv.label == "WhiteFinch")
	-- Playing WoW on a character: the character's name, the same row.
	S.env.C_BattleNet.GetAccountInfoByID = function(id)
		if id == 77 then
			return { battleTag = "WhiteFinch#1368", accountName = "Real Person", bnetAccountID = 77,
				gameAccountInfo = { isOnline = true, clientProgram = "WoW", characterName = "Aldric Emberheart", characterLevel = 23 } }
		end
	end
	S.fire("BN_FRIEND_INFO_CHANGED")
	check("a friend playing WoW shows by character name", conv.label == "Aldric Emberheart", conv.label)
	S.chatEvent("CHAT_MSG_BN_WHISPER", "on my paladin now", "Real Person", { bnetID = 77 })
	check("their messages show the character name", conv.lines[#conv.lines].text:find("Aldric Emberheart", 1, true) ~= nil)
	check("and stay in the same row", C:Get("bn:whitefinch#1368") == conv)
	S.env.C_BattleNet.GetAccountInfoByID = function(id)
		if id == 77 then return { battleTag = "WhiteFinch#1368", accountName = "Real Person", bnetAccountID = 77,
			gameAccountInfo = { isOnline = false } } end
	end
	S.fire("BN_FRIEND_INFO_CHANGED")
	check("logged off, it's back to the BattleTag", conv.label == "WhiteFinch", conv.label)
	-- The open chat box's "Tell <name>:" title doesn't show the real name.
	local header = { _w = 0 }
	function header:SetFormattedText(fmt, value) self.text = fmt:format(tostring(value)) end
	function header:SetWidth(w) self._w = w end
	function header:GetWidth() return self._w end
	function header:GetLeft() return 0 end
	function header:GetRight() return 60 end
	function header:GetStringWidth() return 60 end
	S.env.ChatFrame1EditBoxHeader = header
	S.env.CHAT_BN_WHISPER_SEND = "Tell %s: "
	S.env.BNet_GetBNetIDAccount = function() return 77 end
	S.editBox:SetChatType("BN_WHISPER")
	S.editBox:SetTellTarget("Real Person")
	S.editBox:UpdateHeader()
	check("the chat box title uses the shown name", header.text == "Tell WhiteFinch: ", header.text)
	S.editBox:SetChatType("SAY")
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

section("The window", function()
	local S = first
	local Shell = S.ns.Shell
	local frame = Shell.frame
	frame.CloseButton:GetScript("OnClick")()
	check("the close button hides the window", not frame:IsShown() and S.ns.db.shown == false)
	S.slash("show")
	check("/hearye show brings it back", frame:IsShown() and S.ns.db.shown == true)
	Shell:ApplyOpacity()
	check("the fade state is described", Shell:DescribeChrome():find("shown 100%%") ~= nil, Shell:DescribeChrome())
	-- Closing a section keeps its rows out of the sidebar, and it's saved.
	S.ns.db.collapsed.whispers = true
	local okRefresh, err = pcall(Shell.Refresh, Shell)
	check("a closed section refreshes", okRefresh, err)
	check("a closed section is saved", S.ns.db.collapsed.whispers == true)
	S.ns.db.collapsed.whispers = nil
	Shell:Refresh()
end)

section("Hiding the conversation list", function()
	local S = first
	local Shell = S.ns.Shell
	Shell.sidebar._h = 300 -- room for rows, which the stub frames don't lay out
	Shell.listToggle:GetScript("OnClick")()
	check("the list goes compact", S.ns.db.sidebarHidden == true and Shell.sidebar:GetWidth() == 82, Shell.sidebar:GetWidth())
	S.chatEvent("CHAT_MSG_WHISPER", "still there?", "Brana Tester-Forever", { guid = "Player-1-00000002" })
	local shownPills = 0
	for _, conv in ipairs(S.ns.Conversations:Sorted()) do
		if conv.unread > 0 then shownPills = shownPills + 1 end
	end
	check("the strip still has unread conversations to show", shownPills > 0)
	check("the button carries no total in the strip", not Shell.listToggle.pill:IsShown())
	Shell.listToggle:GetScript("OnClick")()
	check("the names come back", S.ns.db.sidebarHidden == false and Shell.sidebar:GetWidth() == 150)
	Shell.sidebar._h = 0
end)

section("Scrolling the list", function()
	local S = first
	local Shell = S.ns.Shell
	Shell.sidebar._h = 70 -- room for a header and a couple of rows
	Shell:Refresh()
	check("a list that doesn't fit says there's more", Shell.listMore == true and Shell.moreText:IsShown())
	local wheel = Shell.sidebar:GetScript("OnMouseWheel")
	wheel(Shell.sidebar, -1)
	check("the wheel scrolls it down", Shell.listOffset == 1)
	wheel(Shell.sidebar, 1)
	wheel(Shell.sidebar, 1)
	check("and back up, no further than the top", Shell.listOffset == 0)
	wheel(Shell.sidebar, -1)
	Shell.sidebar._h = 400 -- the window grows back
	Shell:Refresh()
	check("a list that fits again scrolls back to the top", Shell.listOffset == 0, Shell.listOffset)
	Shell.sidebar._h = 0
end)

section("Clicking a row", function()
	local S = first
	local C = S.ns.Conversations
	S.opened = 0
	C:Select("nearby", false)
	check("clicking a row doesn't open the chat box", S.opened == 0)
	check("it points the box there for the next Enter", S.editBox:GetChatType() == "SAY")
	S.editBox.HasFocus = function() return true end
	local whisper
	for _, c in ipairs(C:Sorted()) do
		if c.chatType == "WHISPER" then whisper = c end
	end
	C:Select(whisper.key, false)
	check("while typing, a click moves the open box along", S.opened == 1 and S.editBox:GetChatType() == "WHISPER")
	S.editBox.HasFocus = nil
	C:Select("nearby", false)
end)

section("Game lines show in the open row", function()
	local S = first
	local C = S.ns.Conversations
	local smf = S.ns.Messages.frame
	local game = C:Get("game")
	local party = C:EnsureGroup("party")
	C:Select(party.key, false)
	local partyLines, gameLines, before = #party.lines, #game.lines, game.unread
	local shown = smf:GetNumMessages()
	S.env.ChatFrame1:AddMessage("You receive loot: [Linen Cloth].", 0, 0.67, 0)
	check("loot shows in the open row", smf:GetNumMessages() == shown + 1)
	check("but isn't saved to it", #party.lines == partyLines)
	check("the Game row still keeps it", #game.lines == gameLines + 1)
	check("and it isn't unread there, you saw it", game.unread == before, game.unread)
	S.env.ChatFrame1:AddMessage("|cffd9b36cHear Ye|r: Hidden.", 1, 1, 1)
	check("Hear Ye's own lines aren't shown twice", smf:GetNumMessages() == shown + 1)
	C:Select("game", false)
	local count = smf:GetNumMessages()
	S.env.ChatFrame1:AddMessage("Brana Tester: Level 12 Dwarf Paladin - Dun Morogh", 1, 1, 0)
	check("with Game open, they show once", smf:GetNumMessages() == count + 1)
	C:Select("nearby", false)
end)

section("Hovering", function()
	local S = first
	local Shell = S.ns.Shell
	local frame = Shell.frame
	frame.IsMouseOver = function() return true end
	local function settle()
		S.now = S.now + 10
		for _ = 1, 5 do Shell.OnFadeUpdate(frame, 1) end
		return Shell:DescribeChrome()
	end
	S.mouseFocus = { GetParent = function() return nil end } -- a quest window on top
	check("a window on top of Hear Ye doesn't wake it", settle():find("shown 0%%") ~= nil, Shell:DescribeChrome())
	S.mouseFocus = Shell.pane
	check("hovering Hear Ye itself does", settle():find("shown 100%%") ~= nil, Shell:DescribeChrome())
	S.mouseFocus = nil
	frame.IsMouseOver = nil
end)

section("A quiet conversation fades", function()
	local S = first
	local Shell = S.ns.Shell
	local frame = Shell.frame
	local function settle(seconds)
		S.now = S.now + seconds
		for _ = 1, 5 do Shell.OnFadeUpdate(frame, 1) end
		return Shell:DescribeChrome()
	end
	settle(1)
	check("the messages stay while it's busy", settle(5):find("text 100%%") ~= nil, Shell:DescribeChrome())
	check("they fade after ten quiet seconds", settle(10):find("text 0%%") ~= nil, Shell:DescribeChrome())
	check("the whole message side fades as one", Shell.pane:GetAlpha() == 0 and Shell.paneHeader:GetAlpha() == 0, Shell.pane:GetAlpha())
	check("the conversation list stays", Shell.sidebar:GetAlpha() == 1, Shell.sidebar:GetAlpha())
	local selected = S.ns.Conversations.selectedKey
	S.chatEvent("CHAT_MSG_WHISPER", "meet at the bank?", "Quiet Friend-Forever", { guid = "Player-1-00000009" })
	if S.ns.Conversations.selectedKey == selected then
		check("a message in another row doesn't bring it back", settle(1):find("text 0%%") ~= nil, Shell:DescribeChrome())
	end
	local key = S.ns.Conversations:EnsureWhisper("Quiet Friend-Forever").key
	check("the whisper went to another row", key ~= selected, key)
	do
		S.ns.Conversations:Select(key)
		check("switching to a row brings it back", settle(1):find("text 100%%") ~= nil, Shell:DescribeChrome())
		settle(200)
		S.chatEvent("CHAT_MSG_WHISPER", "I'm by the mailbox", "Quiet Friend-Forever", { guid = "Player-1-00000009" })
		check("a message in the open row brings it back", settle(1):find("text 100%%") ~= nil, Shell:DescribeChrome())
	end
	settle(200)
	frame.IsMouseOver = function() return true end
	S.mouseFocus = Shell.pane
	check("hovering brings it back", settle(1):find("text 100%%") ~= nil, Shell:DescribeChrome())
	frame.IsMouseOver = nil
	S.mouseFocus = nil
	S.ns.db.fadeText = false
	check("with the setting off, it stays", settle(400):find("text 100%%") ~= nil, Shell:DescribeChrome())
	S.ns.db.fadeText = true
	Shell:ApplyOpacity()
end)

section("Clicking links", function()
	local S = first
	local pane = S.ns.Messages.frame
	local click = pane:GetScript("OnHyperlinkClick")
	click(pane, "player:Brana Tester-Forever:41:WHISPER", "[Brana]", "LeftButton")
	check("a left-click goes to the default chat frame", S.itemRef and S.itemRef.source == S.env.DEFAULT_CHAT_FRAME)
	check("a click is announced like the default chat's", S.triggered == "ChatFrame.OnHyperlinkClick")
	click(pane, "player:Brana Tester-Forever:41:WHISPER", "[Brana]", "RightButton")
	check("a right-click's menu belongs to the visible pane", S.itemRef and S.itemRef.source == pane)
	check("the pane offers the chat box to the menu", pane.editBox ~= nil)
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
	check("its lines come back", lineCount(conv) == 3, lineCount(conv))
	S.logout()
	check("a second save keeps it", hasLine(conv, "want to group"))
end)

section("A reload keeps the most recent whisper first", function()
	local S = Boot(nil)
	S.login()
	S.now = 1800000000
	S.chatEvent("CHAT_MSG_WHISPER", "first", "Older Friend-Forever", { guid = "Player-1-00000005" })
	S.now = 1800000100
	S.chatEvent("CHAT_MSG_WHISPER", "second", "Newer Friend-Forever", { guid = "Player-1-00000006" })
	local db = S.logout()
	for attempt = 1, 5 do
		local R = Boot(db)
		R.login()
		local whispers = {}
		for _, c in ipairs(R.ns.Conversations:Sorted()) do
			if c.chatType == "WHISPER" then whispers[#whispers + 1] = c.label end
		end
		check("reload " .. attempt .. " lists the newer whisper first", whispers[1] == "Newer Friend", table.concat(whispers, ", "))
	end
end)

section("Saved history is small", function()
	local S = Boot(nil)
	S.login()
	S.now = 1800000000
	for i = 1, 60 do
		S.chatEvent("CHAT_MSG_WHISPER", "line " .. i, "Chatty Friend-Forever", { guid = "Player-1-00000007" })
	end
	S.chatEvent("CHAT_MSG_SAY", "just passing by", "Someone-Forever", { guid = "Player-1-00000003" })
	local db = S.logout()
	local saved = db.characters["Player-1-00000001"].convs
	local whisperLines, sayKept = 0, saved.nearby ~= nil
	for _, conv in pairs(saved) do
		if conv.chatType == "WHISPER" then whisperLines = #conv.lines end
	end
	check("a conversation keeps its last 50 lines", whisperLines == 50, whisperLines)
	check("Say isn't saved", not sayKept)

	-- Two days later, yesterday's whispers are gone.
	local R = Boot(db)
	R.now = 1800000000 + 2 * 86400
	R.login()
	local left = 0
	for _, c in ipairs(R.ns.Conversations:Sorted()) do
		if c.chatType == "WHISPER" then left = left + #c.lines end
	end
	check("lines older than a day aren't brought back", left == 0, left)

	-- Older saved files with 7 days of history load with today's limits.
	local old = { schema = 4, history = { days = 7, perConversation = 500, total = 5000 } }
	local O = Boot(old)
	O.login()
	check("old history limits move to 1 day and 50 lines", O.ns.db.history.days == 1 and O.ns.db.history.perConversation == 50)
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

section("A reload keeps the guild session", function()
	local S = Boot(nil)
	S.inGuild, S.guildName = true, "Hearth Wardens"
	S.login()
	S.runTimers()
	S.chatEvent("CHAT_MSG_GUILD", "evening all", "Brana Tester-Forever", { guid = "Player-1-00000002" })
	local db = S.logout()

	-- Reload: the guild isn't known for a moment, as on the live client.
	local R = Boot(db)
	R.inGuild = false
	R.login()
	local ready = table.remove(R.timers, 1)
	ready()
	local function earlier()
		for _, c in ipairs(R.ns.Conversations:Sorted()) do
			if c.archiveOf == "guild" then return c end
		end
	end
	check("no Former guild row before the guild is known", earlier() == nil)
	R.inGuild, R.guildName = true, "Hearth Wardens"
	R.fire("PLAYER_GUILD_UPDATE")
	check("no Former guild row once it's the same guild", earlier() == nil)
	check("the guild row keeps its history", hasLine(R.ns.Conversations:Get("guild"), "evening all"))

	-- A different guild after the reload starts Guild empty, with no
	-- "Former guild" row.
	local db2 = R.logout()
	local D = Boot(db2)
	D.inGuild, D.guildName = true, "Other Guild"
	D.login()
	table.remove(D.timers, 1)()
	local former = false
	for _, c in ipairs(D.ns.Conversations:Sorted()) do
		if c.archiveOf == "guild" then former = true end
	end
	check("a different guild leaves no Former guild row", not former)
	check("a different guild starts with no history", #D.ns.Conversations:Get("guild").lines == 0)

	-- Old saved files with a Former guild row don't bring it back.
	local old = D.logout()
	old.characters["Player-1-00000001"].convs["guild@4"] = { label = "Former guild", archiveOf = "guild", group = "guild", readOnly = true, lines = { { text = "x", t = 1 } } }
	local O = Boot(old)
	O.login()
	check("an old Former guild row is dropped", O.ns.Conversations:Get("guild@4") == nil)
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
