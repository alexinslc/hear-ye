-- Conversation identity, availability, and selection.
--
-- Rows come from the client's own state: group and guild membership, and the
-- channels you've actually joined. Nothing is added by hand. History is kept
-- in memory for now; Phase 4 adds bounded saved history.
local _, ns = ...

local Conversations = {}
ns.Conversations = Conversations

-- Lines kept in memory while you play. Saved history is much smaller; see
-- Save and the history settings in Core.lua.
local MAX_LINES = 500

-- Only your own conversations are saved across reloads: whispers, party,
-- raid and guild. Say, public channels and Game last for the session, like
-- the default chat.
local KEEPS_HISTORY = {
	WHISPER = true, BN_WHISPER = true, PARTY = true, RAID = true,
	INSTANCE_CHAT = true, GUILD = true, OFFICER = true,
}
local MAX_CHANNELS = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels) or 20

local byKey = {}
local activityCounter = 0
Conversations.selectedKey = "nearby"

local function InHomeGroup()
	return IsInGroup(LE_PARTY_CATEGORY_HOME)
end

local function InHomeRaid()
	return IsInRaid(LE_PARTY_CATEGORY_HOME)
end

local function InInstanceGroup()
	return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
end

-- One conversation per destination. A group's conversation is a session: when
-- you leave, its lines are cleared and the next group starts fresh.
local GROUPS = {
	nearby = { label = "Say", chatType = "SAY", sort = 1 },
	party = { label = "Party", chatType = "PARTY", sort = 2, available = InHomeGroup, session = true },
	raid = { label = "Raid", chatType = "RAID", sort = 3, available = InHomeRaid, session = true },
	instance = { label = "Instance", chatType = "INSTANCE_CHAT", sort = 4, available = InInstanceGroup, session = true },
	-- No "former guild": the Guild row is there while you're in a guild and
	-- gone when you aren't. Joining a different guild starts it empty.
	guild = { label = "Guild", chatType = "GUILD", sort = 5, available = IsInGuild },
	-- Officer chat depends on guild rank, which isn't simple to check, so the
	-- row appears when the first officer message arrives.
	officer = { label = "Officer", chatType = "OFFICER", sort = 6, available = IsInGuild, onDemand = true },
	-- Everything the default chat shows that isn't a conversation: system
	-- messages, loot, NPC speech, addon output. Read-only.
	game = { label = "Game", sort = 25, quiet = true },
}

-- Message types (CHAT_MSG_<type>) that belong to a group conversation.
local GROUP_OF = {
	SAY = "nearby", YELL = "nearby", EMOTE = "nearby", TEXT_EMOTE = "nearby",
	PARTY = "party", PARTY_LEADER = "party",
	RAID = "raid", RAID_LEADER = "raid", RAID_WARNING = "raid",
	INSTANCE_CHAT = "instance", INSTANCE_CHAT_LEADER = "instance",
	GUILD = "guild", OFFICER = "officer",
}
Conversations.GROUP_OF = GROUP_OF

local function Touch(conv)
	activityCounter = activityCounter + 1
	conv.lastActivity = activityCounter
end

local function Create(key, fields)
	local conv = { key = key, unread = 0, lines = {} }
	for k, v in pairs(fields) do
		conv[k] = v
	end
	byKey[key] = conv
	Touch(conv)
	return conv
end

local function CreateGroup(key)
	local group = GROUPS[key]
	return Create(key, {
		label = group.label,
		chatType = group.chatType,
		sort = group.sort,
		available = group.available,
		quiet = group.quiet,
		group = key,
	})
end

function Conversations:Get(key)
	return key and byKey[key]
end

function Conversations:GetSelected()
	return byKey[self.selectedKey]
end

-- Whether you can send here right now.
function Conversations:IsAvailable(conv)
	if conv.readOnly or not conv.chatType then
		return false
	end
	if conv.chatType == "CHANNEL" then
		return conv.joined and true or false
	end
	if conv.available then
		return conv.available() and true or false
	end
	return true
end

function Conversations:EnsureGroup(key)
	return byKey[key] or (GROUPS[key] and CreateGroup(key))
end

---------------------------------------------------------------------------
-- Group sessions
---------------------------------------------------------------------------

-- A group conversation that ended starts over empty, like the default chat
-- keeps no party of its own: the next group never sees the last one's lines
-- or inherits it as a recipient. The row leaves the list until you're in a
-- group again.
local function EndSession(conv)
	ns.Input:OnDestinationEnded(conv)
	conv.lines, conv.unread, conv.members = {}, 0, nil
	if Conversations.selectedKey == conv.key then
		Conversations.selectedKey = "nearby"
		ns.Messages:Render()
	end
	ns:Log("%s ended; its lines were cleared", conv.key)
end

function Conversations:ReconcileGroups()
	for key, group in pairs(GROUPS) do
		if group.available then
			local now = group.available() and true or false
			local conv = byKey[key]
			if now and not conv and not group.onDemand then
				conv = CreateGroup(key)
			end
			-- A group restored from last session: keep it only if it's the same
			-- group (someone from it is still with you), as after a /reload.
			if conv and conv.pendingSession and Conversations.ready then
				conv.pendingSession = nil
				if now and group.session and conv.members and not Conversations:SharesMembers(conv.members) and #conv.lines > 0 then
					EndSession(conv)
				end
			end
			-- The guild is known by its name. A different guild than the saved
			-- one starts with no history; nothing of the old one is kept.
			if key == "guild" and conv and now and GetGuildInfo then
				local name = GetGuildInfo("player")
				if name then
					if conv.guildName and conv.guildName ~= name then
						conv.lines, conv.unread, conv.draft = {}, 0, nil
						ns:Log("new guild; guild history cleared")
					end
					conv.guildName = name
				end
			end
			-- Not in a guild (once the game has had time to say so): don't
			-- leave the Guild row open.
			if key == "guild" and not now and Conversations.settled and Conversations.selectedKey == "guild" then
				Conversations.selectedKey = "nearby"
			end
			-- Until that's decided, leave a restored group alone rather than end it early.
			if conv and not conv.pendingSession then
				if conv.wasAvailable and not now and group.session then
					EndSession(conv)
					conv.wasAvailable = false
				else
					conv.wasAvailable = now
				end
			end
		elseif not byKey[key] then
			CreateGroup(key)
		end
	end
end

---------------------------------------------------------------------------
-- Channels
---------------------------------------------------------------------------

-- Zone channels (General, Trade, LocalDefense...) keep the same zone channel
-- ID as you travel, while their full name and local number change. Custom
-- channels are known by name.
local function ChannelKey(zoneChannelID, name)
	if zoneChannelID and zoneChannelID > 0 then
		return "zone:" .. zoneChannelID
	end
	return name and ("ch:" .. strlower(name))
end

local function ShortChannelName(name)
	return (name and name:match("^(.-)%s+%-%s+.+$")) or name
end

local function ChannelInfo(localID, name)
	if C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier then
		local ok, info = pcall(C_ChatInfo.GetChannelInfoFromIdentifier, name or tostring(localID))
		if ok and info then
			return info
		end
	end
	return { name = name, shortcut = ShortChannelName(name), localID = localID, zoneChannelID = 0 }
end

local function EnsureChannel(key, fields)
	local conv = byKey[key]
	if not conv then
		conv = Create(key, { chatType = "CHANNEL", sort = 20, quiet = true })
	end
	for k, v in pairs(fields) do
		conv[k] = v
	end
	return conv
end

-- The channels you're in right now, from the client.
local function JoinedChannels()
	local list = {}
	for localID = 1, MAX_CHANNELS do
		local id, name, _, isCommunity = GetChannelName(localID)
		if id and id > 0 and name and not isCommunity then
			local info = ChannelInfo(id, name)
			local key = ChannelKey(info.zoneChannelID, info.name or name)
			if key then
				list[key] = { localID = id, name = info.name or name, shortcut = info.shortcut ~= "" and info.shortcut or ShortChannelName(name), zoneChannelID = info.zoneChannelID }
			end
		end
	end
	return list
end

function Conversations:ReconcileChannels()
	local joined = JoinedChannels()
	for key, ch in pairs(joined) do
		local conv = byKey[key]
		local wasJoined = conv and conv.joined
		conv = EnsureChannel(key, {
			label = ch.shortcut,
			fullName = ch.name,
			localID = ch.localID,
			zoneChannelID = ch.zoneChannelID,
			joined = true,
		})
		if not wasJoined then
			ns:Log("channel %s joined as /%d (%s)", key, ch.localID, ch.name)
		end
	end
	for key, conv in pairs(byKey) do
		if conv.chatType == "CHANNEL" and conv.joined and not joined[key] then
			conv.joined = false
			conv.localID = nil
			ns.Input:OnDestinationEnded(conv)
			ns:Log("channel %s left", key)
		end
	end
end

-- From a CHAT_MSG_CHANNEL event. These three fields are never secret.
function Conversations:ChannelFromEvent(zoneChannelID, channelIndex, baseName)
	local key = ChannelKey(zoneChannelID, baseName)
	if not key then
		return nil
	end
	local conv = byKey[key]
	if not conv or not conv.joined then
		self:ReconcileChannels()
		conv = byKey[key]
	end
	if not conv then
		conv = EnsureChannel(key, { label = ShortChannelName(baseName), fullName = baseName, localID = channelIndex, zoneChannelID = zoneChannelID, joined = true })
	end
	return conv
end

-- The channel's current local number, looked up at send time.
function Conversations:ResolveChannel(conv)
	local ch = JoinedChannels()[conv.key]
	if ch then
		conv.localID, conv.fullName = ch.localID, ch.name
		return ch.localID
	end
	return nil
end

---------------------------------------------------------------------------
-- Whispers
---------------------------------------------------------------------------

local function ShortName(fullName)
	return (Ambiguate and Ambiguate(fullName, "short")) or fullName
end

-- Keyed by the full name the server sends. The short label is for display
-- only; Shell shows full names when two labels would look the same.
function Conversations:EnsureWhisper(fullName)
	local key = "w:" .. strlower(fullName)
	local conv = byKey[key]
	local created = false
	if not conv then
		conv = Create(key, { label = ShortName(fullName), fullName = fullName, chatType = "WHISPER", tellTarget = fullName, sort = 30 })
		created = true
	end
	return conv, created
end

-- Level and class, only from what the client already knows: a unit you can
-- see, your friends list, your guild roster, or Battle.net. No /who traffic.
-- A level found this way is a last-known value, so the tooltip says where
-- it came from; unknown stays unknown.
local function ClassColor(classFile)
	if not classFile then
		return nil
	end
	return (C_ClassColor and C_ClassColor.GetClassColor(classFile)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
end

local function SameName(a, b)
	if not a or not b then
		return false
	end
	a, b = strlower(a), strlower(b)
	if a == b then
		return true
	end
	if Ambiguate then
		return strlower(Ambiguate(a, "none")) == strlower(Ambiguate(b, "none"))
	end
	return false
end

local function LookupPerson(conv)
	if conv.guid and UnitTokenFromGUID then
		local ok, unit = pcall(UnitTokenFromGUID, conv.guid)
		if ok and unit then
			local level = UnitLevel(unit)
			local className, classFile = UnitClass(unit)
			if level and level > 0 then
				return level, "seen nearby or in your group", className, classFile
			end
		end
	end
	if conv.chatType == "BN_WHISPER" and conv.bnetID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
		local info = C_BattleNet.GetAccountInfoByID(conv.bnetID)
		local game = info and info.gameAccountInfo
		if game and game.characterLevel and game.characterLevel > 0 then
			return game.characterLevel, "from Battle.net", game.className, nil
		end
		return nil
	end
	local name = conv.fullName
	if C_FriendList and C_FriendList.GetFriendInfo and name then
		local ok, info = pcall(C_FriendList.GetFriendInfo, name)
		if ok and info and info.level and info.level > 0 then
			return info.level, "from your friends list", info.className, nil
		end
	end
	if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo and name then
		for i = 1, GetNumGuildMembers() do
			local member, _, _, level, classDisplay, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
			if SameName(member, name) then
				return level, "from your guild roster", classDisplay, classFile
			end
		end
	end
	return nil
end

function Conversations:RefreshPerson(conv)
	if conv.chatType == "BN_WHISPER" then
		self:LabelBNet(conv) -- they may have switched characters or logged off
	end
	local level, source, className, classFile = LookupPerson(conv)
	if level then
		conv.level, conv.levelSource = level, source
	end
	if className and not conv.className then
		conv.className = className
	end
	if classFile and not conv.color then
		conv.color = ClassColor(classFile)
	end
	conv.classFile = conv.classFile or classFile
end

function Conversations:RefreshPeople()
	for _, conv in pairs(byKey) do
		if conv.chatType == "WHISPER" or conv.chatType == "BN_WHISPER" then
			self:RefreshPerson(conv)
		end
	end
end

local function BattleTagFor(bnetID)
	if bnetID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
		local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
		if ok and info and info.battleTag and info.battleTag ~= "" then
			return info.battleTag
		end
	end
	return nil
end

-- Battle.net friends are shown by BattleTag, never by their real name: just
-- the name before the "#", with the whole tag only in the row's tooltip.
local function ShortBattleTag(tag)
	return tag and (tag:match("^([^#]+)") or tag) or "Battle.net friend"
end
Conversations.BattleTagFor = BattleTagFor

-- The character a Battle.net friend is playing in WoW right now, if any.
local WOW_CLIENT = BNET_CLIENT_WOW or "WoW"
local function CharacterFor(bnetID)
	if not (bnetID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then
		return nil
	end
	local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
	local game = ok and info and info.gameAccountInfo
	local name = game and game.isOnline and game.clientProgram == WOW_CLIENT and game.characterName
	if type(name) == "string" and ns.CanAccess(name) and name ~= "" then
		return name
	end
	return nil
end
Conversations.CharacterFor = CharacterFor
Conversations.ShortBattleTag = ShortBattleTag

-- Battle.net account IDs can change between sessions; the BattleTag doesn't.
local function BNetKey(bnetID)
	local tag = BattleTagFor(bnetID)
	if tag then
		return "bn:" .. strlower(tag), tag
	end
	return "bnid:" .. tostring(bnetID), nil
end

function Conversations:EnsureBNet(bnetID, tokenName)
	local key, tag = BNetKey(bnetID)
	local conv = byKey[key]
	local created = false
	if not conv then
		conv = Create(key, { chatType = "BN_WHISPER", sort = 30 })
		created = true
	end
	-- tellTarget is what the game needs to send the whisper.
	conv.bnetID, conv.battleTag, conv.tellTarget = bnetID, tag or conv.battleTag, tokenName
	self:LabelBNet(conv)
	return conv, created
end

-- A Battle.net friend's name in the list and header. While "Hide friends'
-- real names" is on (the default): the character they're playing, or their
-- BattleTag. When it's off: their real name, as the game gives it.
function Conversations:LabelBNet(conv)
	-- Finds the friend by BattleTag first: after a reload the saved row has
	-- no session ID yet, which is what says what they're playing.
	local accountName = self:ResolveBNet(conv)
	local realName = not ns.db.hideRealNames and accountName
	-- While they're playing WoW, the character they're on; otherwise the
	-- BattleTag. The row stays the same conversation either way.
	conv.label = realName or CharacterFor(conv.bnetID) or ShortBattleTag(conv.battleTag)
	conv.fullName = conv.label -- the "#1234" part is only in the tooltip
end

function Conversations:RelabelBNet()
	for _, conv in pairs(byKey) do
		if conv.chatType == "BN_WHISPER" then
			self:LabelBNet(conv)
		end
	end
end

-- The current account name to whisper a Battle.net friend, found by BattleTag.
function Conversations:ResolveBNet(conv)
	if conv.battleTag and BattleTagFor(conv.bnetID) ~= conv.battleTag and C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
		for i = 1, BNGetNumFriends() do
			local info = C_BattleNet.GetFriendAccountInfo(i)
			if info and info.battleTag == conv.battleTag then
				conv.bnetID, conv.tellTarget = info.bnetAccountID, info.accountName
				break
			end
		end
	end
	if conv.bnetID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
		local info = C_BattleNet.GetAccountInfoByID(conv.bnetID)
		if info and info.accountName then
			conv.tellTarget = info.accountName
		end
	end
	return conv.tellTarget
end

---------------------------------------------------------------------------
-- Native edit box ↔ conversation
---------------------------------------------------------------------------

function Conversations:KeyForEditBox(editBox)
	local chatType = editBox:GetChatType()
	if not chatType then
		return nil
	end
	local group = GROUP_OF[chatType]
	if group then
		return group
	end
	if chatType == "WHISPER" then
		local target = editBox:GetTellTarget()
		return target and ("w:" .. strlower(target))
	elseif chatType == "BN_WHISPER" then
		local target = editBox:GetTellTarget()
		local id = target and BNet_GetBNetIDAccount and BNet_GetBNetIDAccount(target)
		return id and (BNetKey(id))
	elseif chatType == "CHANNEL" then
		local _, name = GetChannelName(editBox:GetChannelTarget())
		if not name then
			return nil
		end
		local info = ChannelInfo(nil, name)
		return ChannelKey(info.zoneChannelID, info.name or name)
	end
	return nil
end

---------------------------------------------------------------------------
-- Lines, ordering, selection
---------------------------------------------------------------------------

function Conversations:AddLine(conv, text, r, g, b)
	local lines = conv.lines
	-- Copied default-chat lines can be secret: shown, but never saved.
	lines[#lines + 1] = { text = text, r = r, g = g, b = b, t = time(), secret = not ns.CanAccess(text) or nil }
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end
	Touch(conv)
end

function Conversations:Sorted()
	local list = {}
	for _, conv in pairs(byKey) do
		list[#list + 1] = conv
	end
	table.sort(list, function(a, b)
		if a.sort ~= b.sort then
			return a.sort < b.sort
		end
		if a.sort >= 30 then
			return a.lastActivity > b.lastActivity
		end
		return (a.label or "") < (b.label or "")
	end)
	return list
end

-- fromNative: the player chose this destination with a slash command or
-- reply key, so the edit box already points there and must not be re-routed.
function Conversations:Select(key, fromNative)
	local conv = byKey[key]
	if not conv then
		return false
	end
	local previous = byKey[self.selectedKey]
	local changed = self.selectedKey ~= key
	self.selectedKey = key
	if changed then
		ns.Messages:Render()
		ns.Shell:NoteActivity()
		ns:Log("selected %s (%s)", key, fromNative and "native command" or "sidebar")
	end
	if not fromNative then
		-- Choosing a row yourself settles where you are.
		ns.Input:CancelReturn()
		-- Clicking a row switches what you're reading, like a chat tab: it
		-- doesn't take the keyboard, so you keep walking. The chat box is
		-- pointed there for when you press Enter. Only while you're already
		-- typing does the click move the open box (and your text) along.
		local typing = ns.Input:IsTyping()
		if self:IsAvailable(conv) then
			if typing then
				ns.Input:Route(conv, previous)
			else
				ns.Input:PointQuietly(conv)
			end
		elseif typing and (conv.chatType or conv.readOnly) then
			ns:Print("You can't send to %s right now. Its history stays here to read.", conv.label)
		end
	end
	ns.Shell:Refresh()
	return true
end

---------------------------------------------------------------------------
-- Saved history (per character, bounded)
---------------------------------------------------------------------------

local SAVED_FIELDS = {
	"label", "fullName", "chatType", "tellTarget", "battleTag", "sort", "group", "archiveOf", "readOnly",
	"zoneChannelID", "className", "classFile", "level", "levelSource", "draft", "unread", "quiet", "members",
	"guildName",
}

-- The character's GUID: names alone aren't unique here (the realm name can
-- be empty and the unit name leaves out the surname).
local function CharacterKey()
	return UnitGUID("player") or ((UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"))
end

local function GroupMembers()
	local names = {}
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		local name, realm = UnitName(prefix .. i)
		if name and not UnitIsUnit(prefix .. i, "player") then
			names[#names + 1] = realm and realm ~= "" and (name .. "-" .. realm) or name
		end
	end
	return names
end

function Conversations:SharesMembers(saved)
	local now = {}
	for _, name in ipairs(GroupMembers()) do
		now[strlower(name)] = true
	end
	for _, name in ipairs(saved) do
		if now[strlower(name)] then
			return true
		end
	end
	return false
end

-- Saved links are made safe to replay: a player link loses its chat line ID
-- (a stale ID could point a report at the wrong message), and Battle.net
-- links, whose IDs only last a session, become plain text.
local function ScrubLinks(text)
	text = text:gsub("|Hplayer:([^:|]+)[^|]*|h", "|Hplayer:%1|h")
	text = text:gsub("|HBNplayer:[^|]*|h(.-)|h", "%1")
	return text
end

function Conversations:Save()
	-- If loading failed partway, what's in memory isn't the real history;
	-- saving it would wipe the saved copy. Leave the saved copy alone.
	if not self.loaded then
		ns:Log("history not saved: it never finished loading this session")
		return
	end
	local db = ns.db
	local limits = db.history
	local cutoff = time() - limits.days * 86400
	local out = { selected = self.selectedKey, savedAt = time(), convs = {} }
	local all = {}
	for key, conv in pairs(byKey) do
		if KEEPS_HISTORY[conv.chatType] then
			local saved = {}
			for _, field in ipairs(SAVED_FIELDS) do
				saved[field] = conv[field]
			end
			if conv.group == "guild" and conv.available and conv.available() then
				-- A guild is known by its name; party members say nothing about it.
				saved.members = nil
				saved.guildName = (GetGuildInfo and GetGuildInfo("player")) or conv.guildName
			elseif conv.group and conv.chatType and conv.available and conv.available() then
				saved.members = GroupMembers()
			end
			saved.lines = {}
			local first = math.max(1, #conv.lines - limits.perConversation + 1)
			for i = first, #conv.lines do
				local l = conv.lines[i]
				if not l.secret and l.t and l.t >= cutoff then
					local line = { text = ScrubLinks(l.text), r = l.r, g = l.g, b = l.b, t = l.t }
					saved.lines[#saved.lines + 1] = line
					all[#all + 1] = { lines = saved.lines, line = line }
				end
			end
			if #saved.lines > 0 or saved.draft or conv.group then
				out.convs[key] = saved
			end
		end
	end
	-- Total cap: drop the oldest lines first, across all conversations.
	if #all > limits.total then
		table.sort(all, function(a, b) return a.line.t < b.line.t end)
		local drop = {}
		for i = 1, #all - limits.total do
			drop[all[i].line] = true
		end
		for _, saved in pairs(out.convs) do
			local kept = {}
			for _, line in ipairs(saved.lines) do
				if not drop[line] then
					kept[#kept + 1] = line
				end
			end
			saved.lines = kept
		end
	end
	db.characters[CharacterKey()] = out
end

function Conversations:Restore()
	local saved = ns.db.characters[CharacterKey()]
	if type(saved) ~= "table" or type(saved.convs) ~= "table" then
		return
	end
	local restored = 0
	local inOrder = {}
	for key, s in pairs(saved.convs) do
		-- Earlier party, raid and former guild rows from older versions
		-- aren't brought back.
		if type(key) == "string" and type(s) == "table" and type(s.lines) == "table" and not s.archiveOf and KEEPS_HISTORY[s.chatType] then
			local conv = Create(key, {})
			inOrder[#inOrder + 1] = conv
			for _, field in ipairs(SAVED_FIELDS) do
				conv[field] = s[field]
			end
			-- Only what today's limits keep: recent lines, the last few of each.
			local limits = ns.db.history
			local cutoff = time() - limits.days * 86400
			local kept = {}
			for _, l in ipairs(s.lines) do
				if type(l) == "table" and tonumber(l.t) and l.t >= cutoff then
					kept[#kept + 1] = l
				end
			end
			while #kept > limits.perConversation do
				table.remove(kept, 1)
			end
			conv.lines = kept
			conv.unread = tonumber(conv.unread) or 0
			if conv.chatType == "BN_WHISPER" then
				self:LabelBNet(conv)
			end
			conv.sort = tonumber(conv.sort) or 30
			conv.label = conv.label or key
			if conv.classFile then
				conv.color = ClassColor(conv.classFile)
			end
			local group = conv.group and GROUPS[conv.group]
			if group and not conv.readOnly then
				-- Group rows take today's name, so a renamed row ("Nearby" is
				-- now "Say") isn't stuck with the saved one.
				conv.label = group.label
				conv.available = group.available
				conv.wasAvailable = true
				conv.pendingSession = group.session or nil
			end
			restored = restored + 1
		end
	end
	-- Saved rows come back in no particular order. Touch them oldest first,
	-- by their last message, so the most recent conversation still sorts first.
	local function LastTime(conv)
		local last = conv.lines[#conv.lines]
		return type(last) == "table" and tonumber(last.t) or 0
	end
	table.sort(inOrder, function(a, b) return LastTime(a) < LastTime(b) end)
	for _, conv in ipairs(inOrder) do
		Touch(conv)
	end
	-- The selected row may be a channel, which only exists once channels
	-- are read; Init selects it again after that.
	self.restoredSelection = saved.selected
	if saved.selected and byKey[saved.selected] then
		self.selectedKey = saved.selected
	end
	ns:Log("restored %d conversations", restored)
end

-- Close a whisper you're done with: the row and its lines go. Another
-- whisper from them starts a new one.
function Conversations:Close(key)
	local conv = byKey[key]
	if not conv or (conv.chatType ~= "WHISPER" and conv.chatType ~= "BN_WHISPER") then
		return false
	end
	byKey[key] = nil
	if self.selectedKey == key then
		self.selectedKey = "nearby"
		ns.Messages:Render()
		ns.Input:PointQuietly(byKey.nearby or self:Get("nearby"))
	end
	ns:Log("closed %s", key)
	ns.Shell:Refresh()
	return true
end

-- Forget saved and shown history for this character. Rows for places you
-- can still chat stay; whisper rows go.
function Conversations:ClearHistory()
	for key, conv in pairs(byKey) do
		if conv.readOnly or conv.chatType == "WHISPER" or conv.chatType == "BN_WHISPER" or (conv.chatType == "CHANNEL" and not conv.joined) then
			byKey[key] = nil
		else
			conv.lines, conv.unread, conv.draft = {}, 0, nil
		end
	end
	if not byKey[self.selectedKey] then
		self.selectedKey = "nearby"
	end
	ns.db.characters[CharacterKey()] = nil
	ns.Messages:Render()
	ns.Shell:Refresh()
	ns:Log("history cleared")
end

function Conversations:Init()
	self:Restore()
	self:ReconcileGroups()
	self:ReconcileChannels()
	local wanted = self.restoredSelection
	if type(wanted) == "string" and byKey[wanted] then
		self.selectedKey = wanted
	end
	self.loaded = true
	-- Group and guild data can arrive a moment after login; decide whether a
	-- restored group is the same one once it has.
	if C_Timer then
		C_Timer.After(3, function()
			Conversations.ready = true
			Conversations:ReconcileGroups()
			-- The friends list has arrived by now: names and levels catch up.
			Conversations:RefreshPeople()
			ns.Input:PointAtSelected()
			ns.Shell:Refresh()
		end)
		-- If the game still hasn't said you're in a guild by now, you aren't.
		C_Timer.After(30, function()
			Conversations.settled = true
			Conversations:ReconcileGroups()
			ns.Shell:Refresh()
		end)
	end
end
