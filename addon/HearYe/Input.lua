-- Native input integration.
--
-- Hear Ye does not build its own input. It moves WoW's own chat edit box into
-- the window, so Enter, Escape, slash commands, /r and the reply binding, Tab,
-- history, link insertion and secure commands all stay Blizzard's code.
-- Moving the box only changes its anchors; its scripts are untouched.
local _, ns = ...

local Input = {}
ns.Input = Input

local adopted
local savedPoints = {}
local hooked = {}

local function SavePoints(editBox)
	if savedPoints[editBox] then
		return
	end
	local points = {}
	for i = 1, editBox:GetNumPoints() do
		points[i] = { editBox:GetPoint(i) }
	end
	savedPoints[editBox] = points
end

local function RestorePoints(editBox)
	local points = savedPoints[editBox]
	if not points then
		return
	end
	editBox:ClearAllPoints()
	for _, p in ipairs(points) do
		editBox:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
end

-- A slash command (/p, /w Name, /1) or the reply binding changed where the
-- edit box sends. Follow it in the sidebar so both routes agree.
-- Opening the box re-applies its sticky type; only a change made while
-- typing counts, so reading the Game row and pressing Enter stays put.
local baselineKey

-- The game titles a Battle.net whisper with the friend's real name ("Tell
-- <name>:"). While real names are hidden, retitle it with the name Hear Ye
-- shows (their character or BattleTag), and redo the text spacing the same
-- way the game does, so typing starts after the shorter title.
local function HideRealNameInHeader(editBox)
	if not ns.db.hideRealNames or editBox:GetChatType() ~= "BN_WHISPER" or not CHAT_BN_WHISPER_SEND then
		return
	end
	local name = editBox.GetName and editBox:GetName()
	local header = name and _G[name .. "Header"]
	local suffix = name and _G[name .. "HeaderSuffix"]
	if not header then
		return
	end
	local C = ns.Conversations
	local conv = C:Get(C:KeyForEditBox(editBox))
	local shown = conv and conv.label
	if not shown then
		local target = editBox:GetTellTarget()
		local bnetID = target and BNet_GetBNetIDAccount and BNet_GetBNetIDAccount(target)
		shown = C.CharacterFor(bnetID) or C.ShortBattleTag(C.BattleTagFor(bnetID))
	end
	header:SetWidth(0)
	header:SetFormattedText(CHAT_BN_WHISPER_SEND, shown)
	local headerWidth = (header:GetRight() or 0) - (header:GetLeft() or 0)
	local boxWidth = (editBox:GetRight() or 0) - (editBox:GetLeft() or 0)
	if suffix then
		if headerWidth > boxWidth / 2 then
			header:SetWidth(boxWidth / 2)
			suffix:Show()
		else
			suffix:Hide()
		end
	end
	local languageWidth = editBox.UpdateLanguageHeader and editBox:UpdateLanguageHeader() or 0
	editBox:SetTextInsets(15 + header:GetWidth() + (suffix and suffix:IsShown() and suffix:GetWidth() or 0) + (languageWidth or 0), 13, 0, 0)
end

local function OnHeaderUpdated(editBox)
	local ok, err = pcall(HideRealNameInHeader, editBox)
	if not ok then
		ns:Log("couldn't retitle a Battle.net whisper: %s", tostring(err))
	end
	if editBox ~= adopted or not editBox:HasFocus() then
		return
	end
	local key = ns.Conversations:KeyForEditBox(editBox)
	if key == baselineKey then
		return
	end
	baselineKey = key
	if not key or key == ns.Conversations.selectedKey then
		return
	end
	if ns.Conversations:Get(key) then
		ns.Conversations:Select(key, true)
	else
		ns:Log("native destination %s has no row yet", key)
	end
end

function Input:Adopt(editBox)
	if not editBox or not ns.db.adoptInput or not ns.Shell:IsActive() then
		return
	end
	if adopted == editBox then
		return
	end
	if adopted then
		RestorePoints(adopted)
	end
	SavePoints(editBox)
	local area = ns.Shell.inputArea
	editBox:ClearAllPoints()
	editBox:SetPoint("LEFT", area, "LEFT", -2, 0)
	editBox:SetPoint("RIGHT", area, "RIGHT", -14, 0)
	adopted = editBox
	if not hooked[editBox] then
		hooked[editBox] = true
		hooksecurefunc(editBox, "UpdateHeader", OnHeaderUpdated)
	end
	ns:Log("adopted %s", editBox:GetName() or "unnamed edit box")
end

function Input:AdoptCurrent()
	if not ChatFrameUtil then
		return
	end
	self:Adopt(ChatFrameUtil.GetActiveWindow() or ChatFrameUtil.ChooseBoxForSend())
end

function Input:Release()
	if adopted then
		RestorePoints(adopted)
		ns:Log("released %s", adopted:GetName() or "unnamed edit box")
		adopted = nil
	end
end

function Input:GetAdopted()
	return adopted
end

-- Point the native edit box at a conversation and open it, the same way the
-- default UI does for a pop-out whisper window.
--
-- Each conversation keeps its own draft: text typed for one person never
-- follows you to another. previous is the conversation being left.
function Input:Route(conv, previous)
	if not ChatFrameUtil then
		return
	end
	local editBox = ChatFrameUtil.ChooseBoxForSend()
	if not editBox then
		return
	end
	self:Adopt(editBox)

	-- Resolve the real destination now, never from a stale number or name.
	if conv.chatType == "CHANNEL" then
		local id = ns.Conversations:ResolveChannel(conv)
		if not id then
			ns:Print("You're not in %s.", conv.label)
			return
		end
		editBox:SetChannelTarget(id)
	elseif conv.chatType == "BN_WHISPER" then
		local target = ns.Conversations:ResolveBNet(conv)
		if not target then
			ns:Print("%s isn't on your Battle.net friends list right now.", conv.label)
			return
		end
		editBox:SetTellTarget(target)
	elseif conv.tellTarget then
		editBox:SetTellTarget(conv.tellTarget)
	end

	local text = editBox:GetText() or ""
	if previous and previous ~= conv and text ~= "" and text:sub(1, 1) ~= "/" then
		previous.draft = text
	end
	-- A draft saved from a destination that ended moves only when you choose
	-- where it goes, as you just did.
	local draft = conv.draft
	if not draft and previous and previous.draft and not ns.Conversations:IsAvailable(previous) then
		draft, previous.draft = previous.draft, nil
	end
	conv.draft = nil

	editBox:SetChatType(conv.chatType)
	editBox:SetStickyType(conv.chatType)
	ChatFrameUtil.OpenChat(nil)
	editBox:SetText(draft or "")
	ns:Log("routed %s from sidebar%s", conv.key, draft and " with its draft" or "")
end

local GROUP_CHAT_TYPE = { party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT", guild = "GUILD" }

-- Set where the box sends, without opening it.
function Input:PointAt(editBox, conv)
	if conv.chatType == "CHANNEL" then
		local id = ns.Conversations:ResolveChannel(conv)
		if not id then
			return
		end
		editBox:SetChannelTarget(id)
	elseif conv.chatType == "BN_WHISPER" then
		local target = ns.Conversations:ResolveBNet(conv)
		if not target then
			return
		end
		editBox:SetTellTarget(target)
	elseif conv.tellTarget then
		editBox:SetTellTarget(conv.tellTarget)
	end
	editBox:SetChatType(conv.chatType)
	editBox:SetStickyType(conv.chatType)
	editBox:UpdateHeader()
end

function Input:IsTyping()
	return adopted ~= nil and adopted:HasFocus() and true or false
end

-- Point the box at a conversation without opening it, for the next Enter.
function Input:PointQuietly(conv)
	if not ChatFrameUtil then
		return
	end
	local editBox = ChatFrameUtil.ChooseBoxForSend()
	if not editBox then
		return
	end
	self:Adopt(editBox)
	self:PointAt(editBox, conv)
	ns:Log("pointed the box at %s from the sidebar", conv.key)
end

-- Point the box at the selected row when it isn't already, without opening
-- it. Right after a reload the game hasn't rejoined your channels yet, so a
-- saved channel row can't be pointed at until they're back.
function Input:PointAtSelected()
	local editBox = adopted
	if not editBox or editBox:HasFocus() then
		return
	end
	local C = ns.Conversations
	local conv = C:GetSelected()
	if not conv or not conv.chatType or not C:IsAvailable(conv) then
		return
	end
	if C:KeyForEditBox(editBox) == conv.key then
		return
	end
	self:PointAt(editBox, conv)
	ns:Log("pointed the box at %s", conv.key)
end

-- A party ended or you left a channel. If you were typing to it, keep the
-- text with that conversation and empty the box, so Enter can't send it
-- somewhere you didn't pick.
function Input:OnDestinationEnded(conv)
	local editBox = adopted
	if not editBox then
		return
	end
	local chatType = editBox:GetChatType()
	local matches
	if conv.archiveOf then
		matches = GROUP_CHAT_TYPE[conv.archiveOf] == chatType
	elseif conv.chatType == "CHANNEL" and chatType == "CHANNEL" then
		local key = ns.Conversations:KeyForEditBox(editBox)
		matches = key == nil or key == conv.key
	end
	local text = editBox:GetText() or ""
	if matches and text ~= "" and text:sub(1, 1) ~= "/" then
		conv.draft = text
		editBox:SetText("")
		ns:Print("%s ended. Your unsent message is saved there; pick a conversation to send it.", conv.label)
	end
end

function Input:Init()
	if not EventRegistry then
		ns:Log("EventRegistry missing; input adoption disabled")
		return
	end
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", function(_, editBox)
		Input:Adopt(editBox)
	end, Input)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", function(_, editBox)
		Input:Adopt(editBox)
		baselineKey = ns.Conversations:KeyForEditBox(editBox)
		ns.Shell:SetTyping(true)
		-- Opening the box on a conversation with unsent text brings it back.
		local C = ns.Conversations
		local conv = C:GetSelected()
		if conv and conv.draft and (editBox:GetText() or "") == "" and baselineKey == conv.key then
			editBox:SetText(conv.draft)
			conv.draft = nil
		end
	end, Input)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", function()
		ns.Shell:SetTyping(false)
	end, Input)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", function()
		ns.Shell:SetTyping(false)
	end, Input)
	self:AdoptCurrent()
	-- After a /reload or login the game resets the box to Say. Point it back
	-- at the restored conversation without opening it.
	self:PointAtSelected()
end
