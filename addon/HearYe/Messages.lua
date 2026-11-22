-- Incoming chat: sort messages into conversations and show the selected one.
-- The default chat keeps receiving everything; Hear Ye never hides or
-- filters its messages, so the native display is always there as a fallback.
local _, ns = ...

local Messages = {}
ns.Messages = Messages

local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL",
}

local STATE_EVENTS = {
	"GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT", "PLAYER_GUILD_UPDATE",
	"FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED",
	"CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE",
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local OWN_PREFIX = "Hear Ye|r: "

local OUTGOING = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }
local BNET = { BN_WHISPER = true, BN_WHISPER_INFORM = true }
local WHISPER = { WHISPER = true, WHISPER_INFORM = true }

local smf, newButton
local playerGUID

local function SafeCall(func, ...)
	if not func then
		return nil
	end
	local ok, result = pcall(func, ...)
	if ok then
		return result
	end
	return nil
end

local function ClassInfo(guid)
	if not guid or guid == "" or not GetPlayerInfoByGUID then
		return nil
	end
	local ok, localizedClass, englishClass = pcall(GetPlayerInfoByGUID, guid)
	if not ok or not englishClass then
		return nil
	end
	local color = (C_ClassColor and C_ClassColor.GetClassColor(englishClass)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass])
	return color, localizedClass, englishClass
end

local function Colorize(text, color)
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	elseif color and color.colorStr then
		return "|c" .. color.colorStr .. text .. "|r"
	end
	return text
end

local function ChatColor(msgType, channelNumber)
	local info = ChatTypeInfo and ((msgType == "CHANNEL" and ChatTypeInfo["CHANNEL" .. tostring(channelNumber)]) or ChatTypeInfo[msgType])
	if info then
		return info.r, info.g, info.b
	end
	return 1, 1, 1
end

-- Message types shown as plain "[Name]: text".
local FLAT = {
	SAY = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, OFFICER = true,
	CHANNEL = true, WHISPER = true, BN_WHISPER = true,
}

-- The game's own timestamp format when you've chosen one in its settings;
-- otherwise a short grey time, so every row says when it was said.
local function Timestamp()
	local stampFormat = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
	if stampFormat and TimeUtil and TimeUtil.BetterDate then
		return TimeUtil.BetterDate(stampFormat, time())
	end
	local military = GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime")
	local stamp = date(military and "%H:%M" or "%I:%M")
	if not military then
		stamp = stamp:gsub("^0", "")
	end
	return "|cff8a8a8a" .. stamp .. "|r  "
end

local function FormatLine(msgType, text, sender, language, lineID, guid, bnetID, chatGroup, chatTarget, iconReplacement)
	if lineID and C_ChatInfo and C_ChatInfo.IsChatLineCensored and SafeCall(C_ChatInfo.IsChatLineCensored, lineID) then
		return text
	end

	if C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions then
		local noGroupExpansion = true
		if ChatFrameUtil and ChatFrameUtil.CanChatGroupPerformExpressionExpansion then
			noGroupExpansion = not ChatFrameUtil.CanChatGroupPerformExpressionExpansion(chatGroup)
		end
		text = SafeCall(C_ChatInfo.ReplaceIconAndGroupExpressions, text, iconReplacement, noGroupExpansion) or text
	end

	local isEmote = msgType == "EMOTE" or msgType == "TEXT_EMOTE"
	-- Your own lines say "You", except in emotes, which read as sentences.
	local mine = OUTGOING[msgType] or (guid and guid == playerGUID and not isEmote)

	-- Battle.net friends by BattleTag, not their real name. The name the game
	-- gave stays only inside the link, where it's needed to whisper back.
	local display
	if BNET[msgType] and ns.db.hideRealNames then
		local C = ns.Conversations
		display = C.CharacterFor(bnetID) or C.ShortBattleTag(C.BattleTagFor(bnetID))
	elseif BNET[msgType] then
		display = sender
	else
		display = (Ambiguate and Ambiguate(sender, "short")) or sender
	end
	local color = ClassInfo(guid)
	display = Colorize(display, color)

	local linkText = isEmote and display or ("[" .. display .. "]")
	local link
	if mine then
		link = "[You]"
	elseif BNET[msgType] then
		link = GetBNPlayerLink and SafeCall(GetBNPlayerLink, sender, linkText, bnetID, lineID, chatGroup, chatTarget)
	else
		link = GetPlayerLink and SafeCall(GetPlayerLink, sender, linkText, lineID, chatGroup, chatTarget)
	end
	link = link or linkText

	local line
	if msgType == "TEXT_EMOTE" then
		-- The server already wrote the sender's name into the text.
		local s, e
		if sender ~= "" then
			s, e = text:find(sender, 1, true)
		end
		if s then
			line = text:sub(1, s - 1) .. link .. text:sub(e + 1)
		else
			line = text
		end
	else
		-- Flat rows: "[Name]: text". The row already says where you are, so
		-- "says:", "whispers:" and "To" are dropped. Yells, emotes, leaders and
		-- raid warnings keep the game's wording so their type stays visible.
		local prefix
		if FLAT[msgType] or mine then
			prefix = link .. ": "
		else
			local formatKey = _G["CHAT_" .. msgType .. "_GET"] or "%s: "
			prefix = SafeCall(string.format, formatKey, link) or (link .. ": ")
		end
		local languageTag = ""
		if language and language ~= "" and GetDefaultLanguage and language ~= GetDefaultLanguage() then
			languageTag = "[" .. language .. "] "
		end
		line = prefix .. languageTag .. text
	end

	return Timestamp() .. line
end

local function UpdateNewIndicator()
	local conv = ns.Conversations:GetSelected()
	if smf:AtBottom() then
		newButton:Hide()
		if conv and conv.unread > 0 then
			conv.unread = 0
			ns.Shell:Refresh()
		end
	elseif conv and conv.unread > 0 then
		newButton:Show()
	end
end

local SOUND_GROUPS = { party = true, raid = true, instance = true, guild = true, officer = true }

local function Deliver(conv, line, r, g, b, countsAsUnread)
	if countsAsUnread and SOUND_GROUPS[conv.group or ""] and not conv.readOnly then
		local looking = conv.key == ns.Conversations.selectedKey and smf:AtBottom() and ns.Shell:IsActive()
		if not looking then
			Messages:PlayGroupSound(false)
		end
	end
	if conv.key == ns.Conversations.selectedKey and #conv.lines == 1 then
		-- First message: redraw to drop the "No messages yet." note.
		Messages:Render()
		ns.Shell:NoteActivity()
	elseif conv.key == ns.Conversations.selectedKey then
		ns.Shell:NoteActivity()
		local atBottom = smf:AtBottom()
		smf:AddMessage(line, r, g, b)
		-- Read state follows what was actually seen: a reader scrolled up into
		-- older lines hasn't seen this one yet.
		if not atBottom and countsAsUnread then
			conv.unread = conv.unread + 1
			newButton:Show()
		end
	elseif countsAsUnread then
		conv.unread = conv.unread + 1
	end
	ns.Shell:Refresh()
end

-- Restricted contexts can hand addons secret values. They must not be
-- inspected here; the copy of ChatFrame1's line (below) shows them instead.
function Messages:OnRestricted(event)
	local stats = ns.db.spike.restricted
	local entry = stats[event]
	if not entry then
		entry = { seen = 0, copied = 0 }
		stats[event] = entry
		ns:Log("restricted %s first seen (combat=%s)", event, tostring(InCombatLockdown()))
	end
	entry.seen = entry.seen + 1
end

local CONVERSATION_EVENTS = {}
for _, event in ipairs(CHAT_EVENTS) do
	CONVERSATION_EVENTS[event] = true
end

local function ArgsAccessible(eventArgs)
	if type(eventArgs) ~= "table" then
		return true
	end
	local ok, result = pcall(function()
		return ns.CanAccess(unpack(eventArgs, 1, eventArgs.n or #eventArgs))
	end)
	return ok and result
end

-- Every line the default chat window shows passes through here, already
-- formatted by Blizzard's code. Conversation messages Hear Ye could read are
-- skipped (OnChatEvent has them); everything else is copied as-is, without
-- inspecting the text, which may be secret.
local function OnDefaultChatLine(_, text, r, g, b, _, _, _, event, eventArgs)
	if text == nil then
		return
	end
	local C = ns.Conversations
	local conv
	-- Battle.net notices (a friend came online, and so on) only come with the
	-- friend's real name, so they're left out while real names are hidden.
	-- Whispers aren't: those always reach their row.
	if ns.db.hideRealNames and event and ns.CanAccess(event) and not CONVERSATION_EVENTS[event]
		and type(event) == "string" and event:find("^CHAT_MSG_BN") then
		return
	end
	if event and ns.CanAccess(event) and CONVERSATION_EVENTS[event] then
		if ArgsAccessible(eventArgs) then
			return
		end
		local stats = ns.db.spike.restricted[event]
		if stats then
			stats.copied = (stats.copied or 0) + 1
		end
		local group = C.GROUP_OF[event:sub(10)]
		conv = group and C:EnsureGroup(group)
		-- Channel fields are never secret, so a restricted channel line can
		-- still go to its channel. Unreadable whispers fall through to Game.
		if not conv and event == "CHAT_MSG_CHANNEL" and type(eventArgs) == "table" then
			local zoneChannelID, channelIndex, baseName = eventArgs[7], eventArgs[8], eventArgs[9]
			if ns.CanAccess(zoneChannelID, channelIndex, baseName) then
				conv = C:ChannelFromEvent(zoneChannelID, channelIndex, baseName)
			end
		end
	end
	conv = conv or C:Get("game")
	if not conv then
		return
	end
	local ok, err = pcall(function()
		C:AddLine(conv, text, r, g, b)
		-- Game lines count as unread too (on a grey pill), so a reply to
		-- something you did, like a /who result, doesn't go unnoticed. Hear
		-- Ye's own lines don't: they're also shown where you're reading.
		local counts = true
		if ns.CanAccess(text) and type(text) == "string" and text:find(OWN_PREFIX, 1, true) then
			counts = false
		end
		Deliver(conv, text, r or 1, g or 1, b or 1, counts)
	end)
	if not ok and not Messages.copyErrorLogged then
		Messages.copyErrorLogged = true
		ns:Log("copying a default chat line failed: %s", tostring(err))
	end
end

local function OnChatEvent(event, ...)
	local msgType = event:sub(10)
	if not ns.CanAccess(...) then
		Messages:OnRestricted(event)
		return
	end

	local text, sender, language, _, _, _, zoneChannelID, channelNumber, channelName, _, lineID, guid, bnetID, _, _, hideSender, iconReplacement = ...
	if hideSender then
		return
	end

	local C = ns.Conversations
	local conv, created
	local group = C.GROUP_OF[msgType]
	if group then
		conv = C:EnsureGroup(group)
	elseif WHISPER[msgType] then
		conv, created = C:EnsureWhisper(sender)
		if msgType == "WHISPER" and guid and guid ~= "" then
			conv.guid = guid
			local color, className, classFile = ClassInfo(guid)
			if color then
				-- classFile is what's saved; the colour is rebuilt from it.
				conv.color, conv.className, conv.classFile = color, className, classFile
			end
		end
		C:RefreshPerson(conv)
	elseif BNET[msgType] then
		conv, created = C:EnsureBNet(bnetID, sender)
		C:RefreshPerson(conv)
	elseif msgType == "CHANNEL" then
		conv = C:ChannelFromEvent(zoneChannelID, channelNumber, channelName)
	end
	if not conv then
		return
	end

	local chatGroup = ChatFrameUtil and ChatFrameUtil.GetChatCategory and ChatFrameUtil.GetChatCategory(msgType) or msgType
	local chatTarget
	if FCFManager_GetChatTarget then
		chatTarget = SafeCall(FCFManager_GetChatTarget, chatGroup, sender, channelNumber)
	end

	local line = FormatLine(msgType, text, sender, language, lineID, guid, bnetID, chatGroup, chatTarget, iconReplacement)
	local r, g, b = ChatColor(msgType, channelNumber)
	C:AddLine(conv, line, r, g, b)

	local mine = OUTGOING[msgType] or (guid and guid == playerGUID)
	Deliver(conv, line, r, g, b, not mine)

	-- You just started this conversation, so open it. Incoming messages never
	-- switch the view.
	if created and OUTGOING[msgType] then
		C:Select(conv.key, true)
	end
end

local lastParty, lastGuild

local function OnStateEvent(event)
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		ns:Log("%s", event == "PLAYER_REGEN_DISABLED" and "entered combat" or "left combat")
		return
	end
	local C = ns.Conversations
	if event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
		C:RefreshPeople()
		ns.Shell:Refresh()
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		C:RefreshPeople()
	end
	C:ReconcileGroups()
	if event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_GUILD_UPDATE" then
		C:ReconcileChannels()
		-- Channels come back a moment after a reload; aim the box at the
		-- selected channel once it exists again.
		ns.Input:PointAtSelected()
	end
	local party, guild = IsInGroup(LE_PARTY_CATEGORY_HOME), IsInGuild()
	if party ~= lastParty or guild ~= lastGuild then
		ns:Log("%s: party=%s guild=%s", event, tostring(party), tostring(guild))
		lastParty, lastGuild = party, guild
	end
	ns.Shell:Refresh()
end

function Messages:ShowNotice(text)
	if smf then
		smf:AddMessage(text, 0.85, 0.75, 0.45)
		ns.Shell:NoteActivity()
	end
end



function Messages:Render()
	if not smf then
		return
	end
	smf:Clear()
	local conv = ns.Conversations:GetSelected()
	-- The empty-row note isn't a message line: it sits over the pane and
	-- fades with the list, so it never lingers after the text has gone.
	self.emptyNote:SetShown(conv ~= nil and #conv.lines == 0)
	if conv then
		local lines = conv.lines
		if #lines == 0 then
			self.emptyNote:SetText(conv.readOnly and "Nothing was said here." or "No messages yet.")
		end
		-- Mark where the messages you haven't seen start.
		local firstUnread = conv.unread > 0 and (#lines - conv.unread + 1) or nil
		local today = date("%Y-%m-%d")
		local lastDay
		for i, l in ipairs(lines) do
			-- Saved history spans days; say which day older lines are from.
			local day = l.t and date("%Y-%m-%d", l.t)
			if day and day ~= lastDay and (lastDay or day ~= today) then
				local label = day == today and "Today" or date("%A, %B %d", l.t)
				smf:AddMessage("|cff8a8a8a------  " .. label .. "  ------|r", 1, 1, 1)
			end
			lastDay = day or lastDay
			if i == firstUnread and i > 1 then
				smf:AddMessage("|cffd9b36c------  New messages  ------|r", 1, 1, 1)
			end
			smf:AddMessage(l.text, l.r, l.g, l.b)
		end
		conv.unread = 0
	end
	smf:ScrollToBottom()
	newButton:Hide()
end

---------------------------------------------------------------------------
-- Text size and sounds
---------------------------------------------------------------------------

function Messages:DefaultFontSize()
	local _, size = ChatFontNormal:GetFont()
	return math.floor((size or 14) + 0.5)
end

function Messages:ApplyFont()
	if not smf then
		return
	end
	local path, size, flags = ChatFontNormal:GetFont()
	local wanted = ns.db.fontSize
	smf:SetFont(path, wanted > 0 and wanted or size, flags or "")
	-- Lines already on screen keep their old size until redrawn.
	if newButton and ns.Conversations:GetSelected() then
		self:Render()
	end
end

-- Built-in sounds only, so nothing extra needs installing.
local SOUND_CHOICES = {
	{ key = "none", label = "None" },
	{ key = "chime", label = "Whisper chime", kit = "TELL_MESSAGE" },
	{ key = "ping", label = "Map ping", kit = "MAP_PING" },
	{ key = "ready", label = "Ready check", kit = "READY_CHECK" },
	{ key = "warning", label = "Raid warning", kit = "RAID_WARNING" },
}

function Messages:SoundChoices()
	local list = {}
	for _, choice in ipairs(SOUND_CHOICES) do
		if not choice.kit or (SOUNDKIT and SOUNDKIT[choice.kit]) then
			list[#list + 1] = choice
		end
	end
	return list
end

local lastSound = 0

-- preview: play now, even if the setting is off, for the Play button.
function Messages:PlayGroupSound(preview)
	local key = ns.db.groupSound
	for _, choice in ipairs(SOUND_CHOICES) do
		if choice.key == key and choice.kit and SOUNDKIT and SOUNDKIT[choice.kit] then
			local now = GetTime()
			if preview or now - lastSound > 3 then
				lastSound = now
				PlaySound(SOUNDKIT[choice.kit], "Master")
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- The game's chat scrolling keys
---------------------------------------------------------------------------

-- Your key bindings for Chat Page Up, Page Down, Scroll Up, Scroll Down and
-- Chat Bottom call these. They scroll the hidden default chat, so Hear Ye
-- follows along while it's standing in for it.
local function HookScrollBindings()
	if not ChatFrameUtil then
		return
	end
	local map = {
		ChatPageUp = "PageUp", ChatPageDown = "PageDown",
		ScrollUp = "ScrollUp", ScrollDown = "ScrollDown",
		ScrollToBottom = "ScrollToBottom",
	}
	for util, method in pairs(map) do
		if ChatFrameUtil[util] then
			hooksecurefunc(ChatFrameUtil, util, function()
				if smf and ns.Shell:IsActive() and smf[method] then
					smf[method](smf)
					UpdateNewIndicator()
				end
			end)
		end
	end
end

function Messages:Init()
	playerGUID = UnitGUID("player")

	smf = CreateFrame("ScrollingMessageFrame", "HearYeMessageFrame", ns.Shell.pane)
	smf:SetAllPoints()
	smf:SetFontObject(ChatFontNormal)
	smf:SetJustifyH("LEFT")
	smf:SetMaxLines(500)
	if smf.SetIndentedWordWrap then
		smf:SetIndentedWordWrap(true)
	end
	smf:SetHyperlinksEnabled(true)
	smf:EnableMouseWheel(true)
	smf:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
		UpdateNewIndicator()
	end)
	-- Catch clicks on the pane, so a right-click on a name doesn't fall
	-- through to the world and turn the camera.
	smf:EnableMouse(true)
	-- Links go through the same handler the default chat uses. Left-clicks
	-- pass DEFAULT_CHAT_FRAME, because opening a whisper wants a real chat
	-- frame's edit box. Right-clicks pass this pane: the player menu is owned
	-- by the frame it came from, and the default chat may be hidden while
	-- Hear Ye replaces it, which would leave the menu with nowhere to show.
	smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
		-- The same event the default chat sends, so addons that act on
		-- chat links (tooltips, link helpers) work here too.
		if EventRegistry then
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", self, link, text, button)
		end
		if button == "RightButton" then
			self.editBox = ns.Input:GetAdopted() or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
			SetItemRef(link, text, button, self)
		else
			SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
		end
	end)
	smf:SetScript("OnHyperlinkEnter", function(self, ...)
		if EventRegistry then
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkEnter", self, ...)
		end
	end)
	smf:SetScript("OnHyperlinkLeave", function(self)
		if EventRegistry then
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkLeave", self)
		end
	end)
	self.frame = smf
	smf:SetFading(false) -- the whole conversation side fades instead; see Shell
	self:ApplyFont()
	HookScrollBindings()

	newButton = CreateFrame("Button", nil, ns.Shell.pane)
	newButton:SetSize(110, 18)
	newButton:SetPoint("BOTTOMRIGHT", ns.Shell.pane, "BOTTOMRIGHT", 0, 2)
	newButton:SetFrameLevel(smf:GetFrameLevel() + 5)
	local bg = newButton:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.2, 0.2, 0.24, 0.95)
	local label = newButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("New messages")
	newButton:SetScript("OnClick", function()
		smf:ScrollToBottom()
		UpdateNewIndicator()
	end)
	newButton:Hide()
	self.newButton = newButton

	local emptyNote = ns.Shell.pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyNote:SetPoint("BOTTOMLEFT", ns.Shell.pane, "BOTTOMLEFT", 2, 4)
	emptyNote:SetJustifyH("LEFT")
	emptyNote:Hide()
	self.emptyNote = emptyNote

	local listener = CreateFrame("Frame")
	local failed = {}
	for _, event in ipairs(CHAT_EVENTS) do
		if not pcall(listener.RegisterEvent, listener, event) then
			failed[#failed + 1] = event
		end
	end
	for _, event in ipairs(STATE_EVENTS) do
		if not pcall(listener.RegisterEvent, listener, event) then
			failed[#failed + 1] = event
		end
	end
	if #failed > 0 then
		ns:Log("events not available in this client: %s", table.concat(failed, ", "))
	end
	listener:SetScript("OnEvent", function(_, event, ...)
		if event:sub(1, 9) == "CHAT_MSG_" and event ~= "CHAT_MSG_CHANNEL_NOTICE" then
			OnChatEvent(event, ...)
		else
			OnStateEvent(event)
		end
	end)

	if ChatFrame1 and ChatFrame1.AddMessage then
		hooksecurefunc(ChatFrame1, "AddMessage", OnDefaultChatLine)
		self.copyingDefaultChat = true
	else
		ns:Log("ChatFrame1 missing; game messages are not copied")
	end

	self:Render()
	ns.Shell:Refresh()
end
