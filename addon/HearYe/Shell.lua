-- The window: bronze-bordered frame, sidebar, conversation pane, input area.
-- Styled after the game's own windows (and Fireside Tales): tooltip border in
-- bronze, recessed marble insets, quest-log rows and section headers.
local _, ns = ...

local Shell = {}
ns.Shell = Shell

local SIDEBAR_WIDTH = 136
local HEADER_HEIGHT = 22
local INPUT_HEIGHT = 30
local ROW_HEIGHT = 18
local SECTION_HEIGHT = 16
local MIN_WIDTH, MIN_HEIGHT = 360, 200
local MAX_WIDTH, MAX_HEIGHT = 1200, 800
local BRONZE = { 0.72, 0.55, 0.32 }

local frame, sidebar, pane, inputArea, hint, settingsButton
local rows, sections = {}, {}

function ns.ApplyBackdrop(target, alpha)
	target:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	target:SetBackdropColor(0.06, 0.05, 0.04, alpha or 0.92)
	target:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3])
end

-- A recessed panel on dark marble, where the client has the template.
function ns.NewInset(parent)
	local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
	if not ok or not inset then
		inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		inset:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
		inset:SetBackdropColor(0, 0, 0, 0.4)
		return inset
	end
	if type(inset.Bg) == "table" and inset.Bg.SetTexture then
		inset.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
		inset.Bg:SetHorizTile(true)
		inset.Bg:SetVertTile(true)
		inset.Bg:SetVertexColor(0.55, 0.55, 0.55, 0.9)
	end
	return inset
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.db.position = { point, relativePoint, x, y }
	ns.db.width, ns.db.height = frame:GetSize()
end

-- First placement: exactly where the default chat window sits.
local function DefaultPosition()
	local chat = ChatFrame1
	if chat and chat:GetLeft() and chat:GetBottom() then
		local scale = chat:GetEffectiveScale() / UIParent:GetEffectiveScale()
		return "BOTTOMLEFT", "BOTTOMLEFT", chat:GetLeft() * scale - 6, chat:GetBottom() * scale - 34
	end
	return "BOTTOMLEFT", "BOTTOMLEFT", 32, 96
end

local function ApplyPosition()
	frame:ClearAllPoints()
	local pos = ns.db.position
	if not pos then
		local point, relativePoint, x, y = DefaultPosition()
		pos = { point, relativePoint, math.max(0, x), math.max(0, y) }
	end
	frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	frame:SetSize(ns.db.width, ns.db.height)
end

local function ShowRowTooltip(row)
	local conv = row.conv
	if not conv then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(conv.fullName or conv.label, 1, 1, 1)
	if conv.chatType == "WHISPER" or conv.chatType == "BN_WHISPER" then
		if conv.level then
			GameTooltip:AddLine(("Level %d %s"):format(conv.level, conv.className or ""), 0.8, 0.8, 0.8)
			GameTooltip:AddLine("Last known, " .. (conv.levelSource or "from the game"), 0.6, 0.6, 0.6)
		else
			GameTooltip:AddLine(conv.className and (conv.className .. ", level unknown") or "Class and level unknown", 0.8, 0.8, 0.8)
		end
	end
	if conv.key == "game" then
		GameTooltip:AddLine("System messages, loot, NPCs and addon messages", 0.8, 0.8, 0.8, true)
	end
	if conv.chatType == "CHANNEL" and conv.localID then
		GameTooltip:AddLine("/" .. conv.localID .. " right now", 0.8, 0.8, 0.8)
	end
	if conv.draft then
		GameTooltip:AddLine("Unsent message saved", 1, 0.82, 0)
	end
	if conv.readOnly then
		GameTooltip:AddLine("Ended. Read only.", 0.7, 0.7, 0.7)
	elseif conv.chatType and not ns.Conversations:IsAvailable(conv) then
		GameTooltip:AddLine("You can't send here right now", 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

local function CreateRow(index)
	local row = CreateFrame("Button", nil, sidebar)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.selected:SetBlendMode("ADD")
	row.selected:SetVertexColor(1, 0.82, 0.3, 0.55)
	row.selected:SetAllPoints()

	-- Unread count on a small round badge, so it can't be read as a level.
	row.badgeBg = row:CreateTexture(nil, "ARTWORK")
	row.badgeBg:SetPoint("RIGHT", row, "RIGHT", -3, 0)
	row.badgeBg:SetSize(16, 14)
	row.badgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
	if row.badgeBg.SetMask then
		pcall(row.badgeBg.SetMask, row.badgeBg, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end
	row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.badge:SetPoint("CENTER", row.badgeBg, "CENTER", 0, 0)

	-- Whispers show the other player's level, small and grey; "-" when unknown.
	row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.level:SetPoint("RIGHT", row, "RIGHT", -22, 0)

	-- A small round marker: chat-type colour for channels, class colour for
	-- people, grey when the class isn't known.
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(7, 7)
	row.dot:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
	if row.dot.SetMask then
		pcall(row.dot.SetMask, row.dot, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row:SetScript("OnClick", function(self)
		if self.conv then
			ns.Conversations:Select(self.conv.key, false)
		end
	end)
	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	rows[index] = row
	return row
end

local function CreateSection(index)
	local section = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	section:SetJustifyH("LEFT")
	sections[index] = section
	return section
end

local function OpenMenu(owner)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle("Hear Ye")
			root:CreateCheckbox("Lock window", function() return ns.db.locked end, function()
				Shell:SetLocked(not ns.db.locked)
			end)
			root:CreateCheckbox("Replace the default chat", function() return ns.db.replaceChat end, function()
				ns.ChatReplace:SetEnabled(not ns.db.replaceChat)
			end)
			root:CreateButton("Settings...", function() ns.Setup:Show() end)
			root:CreateButton("Reset position", function() Shell:ResetPosition() end)
		end)
	else
		ns.Setup:Show()
	end
end

function Shell:Create()
	frame = CreateFrame("Frame", "HearYeFrame", UIParent, "BackdropTemplate")
	-- The lowest layer, so unit frames (your character, target) and other
	-- windows always draw over Hear Ye, never under it. The native edit box
	-- raises itself to DIALOG while you type.
	frame:SetFrameStrata("BACKGROUND")
	frame:SetToplevel(false)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	end
	ns.ApplyBackdrop(frame, ns.db.opacity)
	ApplyPosition()

	-- Header: title, drag handle, settings.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 4, -4)
	header:SetPoint("TOPRIGHT", -4, -4)
	header:SetHeight(HEADER_HEIGHT - 4)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		if not ns.db.locked then
			frame:StartMoving()
		end
	end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
	header:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			OpenMenu(self)
		end
	end)
	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("LEFT", 6, 0)
	title:SetText("Hear Ye")
	self.title = title

	settingsButton = CreateFrame("Button", nil, header)
	settingsButton:SetSize(16, 16)
	settingsButton:SetPoint("RIGHT", -2, 0)
	local gear = settingsButton:CreateTexture(nil, "ARTWORK")
	gear:SetAllPoints()
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestLog-icon-setting") then
		gear:SetAtlas("QuestLog-icon-setting")
	else
		gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
	end
	settingsButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	settingsButton:SetScript("OnClick", function(self)
		OpenMenu(self)
	end)
	settingsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Hear Ye options")
		GameTooltip:AddLine("Right-click the title bar for the same menu.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	settingsButton:SetScript("OnLeave", GameTooltip_Hide)

	sidebar = ns.NewInset(frame)
	sidebar:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - 2)
	sidebar:SetPoint("BOTTOMLEFT", 6, 6)
	sidebar:SetWidth(SIDEBAR_WIDTH)

	inputArea = CreateFrame("Frame", nil, frame)
	inputArea:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 4, 0)
	inputArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	inputArea:SetHeight(INPUT_HEIGHT)
	-- Drawn above the native edit box: with chatStyle "im" the box stays on
	-- screen, faded, between messages, and this reads as its placeholder.
	local hintFrame = CreateFrame("Frame", nil, inputArea)
	hintFrame:SetAllPoints()
	-- Same layer as the faded edit box, raised within it, so it reads on
	-- top of the box without covering unit frames.
	hintFrame:SetFrameStrata("LOW")
	hintFrame:SetFrameLevel(200)
	self.hintFrame = hintFrame
	hint = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 10, 0)
	hint:SetPoint("RIGHT", -20, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)

	local paneInset = ns.NewInset(frame)
	paneInset:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
	paneInset:SetPoint("BOTTOMRIGHT", inputArea, "TOPRIGHT", 0, 2)
	-- Conversation header: who or where, and a line of context.
	local paneHeader = CreateFrame("Frame", nil, paneInset)
	paneHeader:SetPoint("TOPLEFT", 8, -5)
	paneHeader:SetPoint("TOPRIGHT", -8, -5)
	paneHeader:SetHeight(18)
	self.headerName = paneHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.headerName:SetPoint("LEFT")
	self.headerName:SetJustifyH("LEFT")
	self.headerName:SetWordWrap(false)
	self.headerContext = paneHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.headerContext:SetPoint("LEFT", self.headerName, "RIGHT", 8, 0)
	self.headerContext:SetPoint("RIGHT")
	self.headerContext:SetJustifyH("LEFT")
	self.headerContext:SetWordWrap(false)
	local rule = paneInset:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", paneHeader, "BOTTOMLEFT", 0, -3)
	rule:SetPoint("TOPRIGHT", paneHeader, "BOTTOMRIGHT", 0, -3)
	rule:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.35)
	-- Everything behind the text: one opacity setting covers all of it.
	self.chrome = { insets = { sidebar, paneInset }, rule = rule }

	pane = CreateFrame("Frame", nil, paneInset)
	pane:SetPoint("TOPLEFT", 8, -30)
	pane:SetPoint("BOTTOMRIGHT", -6, 4)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		if not ns.db.locked then
			frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
	self.grip = grip

	frame:SetScript("OnHide", function()
		ns.Input:Release()
		ns.ChatReplace:Apply()
	end)
	frame:SetScript("OnShow", function()
		ns.Input:AdoptCurrent()
		ns.ChatReplace:Apply()
	end)
	frame:SetScript("OnSizeChanged", function()
		Shell:Refresh()
	end)

	self.frame = frame
	self.pane = pane
	self.inputArea = inputArea
	-- Runs only while shown; cheap: one comparison per frame when settled.
	frame:HookScript("OnUpdate", function(f, elapsed)
		Shell.OnFadeUpdate(f, elapsed)
	end)
	ns.Conversations:Init()
	self:SetLocked(ns.db.locked)
end

-- Background, border, panels and the header rule at one alpha. Text, names
-- and the input box aren't touched, so they stay fully readable.
local chromeAlpha

local function PaintChrome(alpha)
	chromeAlpha = alpha
	frame:SetBackdropColor(0.06, 0.05, 0.04, alpha)
	frame:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], math.min(1, alpha * 1.1))
	for _, inset in ipairs(Shell.chrome.insets) do
		if inset.Bg then
			inset.Bg:SetAlpha(alpha)
		end
		if inset.NineSlice then
			inset.NineSlice:SetAlpha(alpha)
		end
		if not inset.Bg and inset.SetBackdropColor then
			inset:SetBackdropColor(0, 0, 0, 0.4 * alpha)
		end
	end
	Shell.chrome.rule:SetAlpha(alpha)
end

-- Like the default chat: with fading on, the background shows while the
-- mouse is over the window or you're typing, and fades out a moment after.
local FADE_SECONDS = 0.3
local FADE_DELAY = 1.5
local lastHover = 0

local function TargetAlpha()
	if not ns.db.fadeBackground then
		return ns.db.opacity
	end
	local now = GetTime()
	if Shell.typing or frame:IsMouseOver() then
		lastHover = now
	end
	if now - lastHover < FADE_DELAY then
		return ns.db.opacity
	end
	return 0
end

local function OnFadeUpdate(_, elapsed)
	local target = TargetAlpha()
	if not chromeAlpha then
		PaintChrome(target)
		return
	end
	local current = chromeAlpha
	if current ~= target then
		local step = (elapsed / FADE_SECONDS) * math.max(ns.db.opacity, 0.2)
		if current < target then
			current = math.min(target, current + step)
		else
			current = math.max(target, current - step)
		end
		PaintChrome(current)
	end
end

Shell.OnFadeUpdate = OnFadeUpdate

function Shell:DescribeChrome()
	local insets = {}
	for i, inset in ipairs(self.chrome and self.chrome.insets or {}) do
		insets[#insets + 1] = ("inset%d bg=%s nine=%s"):format(i, tostring(inset.Bg ~= nil), tostring(inset.NineSlice ~= nil))
	end
	return ("setting %d%%, fade %s, now %s; %s"):format(math.floor(ns.db.opacity * 100 + 0.5), ns.db.fadeBackground and "on" or "off",
		chromeAlpha and (math.floor(chromeAlpha * 100 + 0.5) .. "%") or "unset", table.concat(insets, ", "))
end

function Shell:ApplyOpacity()
	if frame then
		lastHover = GetTime()
		PaintChrome(ns.db.opacity)
	end
end

function Shell:IsActive()
	return frame ~= nil and frame:IsShown()
end

function Shell:SetShown(shown)
	ns.db.shown = shown and true or false
	frame:SetShown(ns.db.shown)
end

function Shell:SetLocked(locked)
	ns.db.locked = locked and true or false
	self.grip:SetShown(not ns.db.locked)
end

function Shell:ResetPosition()
	ns.db.position = nil
	ns.db.width, ns.db.height = 500, 320
	ApplyPosition()
end

function Shell:SetTyping(typing)
	self.typing = typing
	if self.hintFrame then
		self.hintFrame:SetShown(not typing)
	end
end

function Shell:SetHint(text)
	if hint then
		hint:SetText(text)
	end
end

local SECTION_NAMES = { chat = "Channels", whispers = "Whispers" }

local NEUTRAL = { r = 0.55, g = 0.55, b = 0.55 }

local function DotColor(conv)
	if conv.chatType == "WHISPER" or conv.chatType == "BN_WHISPER" then
		return conv.color or (conv.chatType == "BN_WHISPER" and ChatTypeInfo and ChatTypeInfo.BN_WHISPER) or NEUTRAL
	end
	if conv.readOnly or not conv.chatType then
		return NEUTRAL
	end
	local info = ChatTypeInfo and ((conv.chatType == "CHANNEL" and conv.localID and ChatTypeInfo["CHANNEL" .. conv.localID]) or ChatTypeInfo[conv.chatType])
	return info or NEUTRAL
end

-- The line of context next to the conversation's name.
local function Context(conv)
	if conv.readOnly then
		return "Ended - history only"
	elseif conv.key == "game" then
		return "System messages, loot and NPCs"
	elseif conv.key == "nearby" then
		return "Players around you"
	elseif conv.chatType == "PARTY" or conv.chatType == "RAID" or conv.chatType == "INSTANCE_CHAT" then
		local n = GetNumGroupMembers and GetNumGroupMembers() or 0
		return n > 0 and (n .. " players") or ""
	elseif conv.chatType == "GUILD" or conv.chatType == "OFFICER" then
		return (GetGuildInfo and GetGuildInfo("player")) or ""
	elseif conv.chatType == "CHANNEL" then
		if not conv.joined then
			return "You left this channel - history only"
		end
		local zone = conv.fullName and conv.fullName:match("^.-%s+%-%s+(.+)$")
		return (zone and (zone .. "  ") or "") .. (conv.localID and ("/" .. conv.localID) or "")
	elseif conv.chatType == "WHISPER" then
		local parts = { "Private" }
		parts[#parts + 1] = conv.level and ("Level " .. conv.level) or "Level unknown"
		if conv.className then
			parts[#parts + 1] = conv.className
		end
		return table.concat(parts, " - ")
	elseif conv.chatType == "BN_WHISPER" then
		return "Battle.net" .. (conv.battleTag and (" - " .. conv.battleTag) or "")
	end
	return ""
end
Shell.Context = Context

function Shell:Refresh()
	if not frame then
		return
	end
	local C = ns.Conversations
	local list = C:Sorted()
	local y = -6
	local bottom = sidebar:GetHeight() - 6
	local rowCount, sectionCount = 0, 0
	local currentSection

	-- Short names are for display; when two would look the same, show both
	-- in full so they can't be mistaken for each other.
	local labelCount = {}
	for _, conv in ipairs(list) do
		if conv.label then
			labelCount[conv.label] = (labelCount[conv.label] or 0) + 1
		end
	end

	for _, conv in ipairs(list) do
		local available = C:IsAvailable(conv)
		local sendable = conv.chatType ~= nil and not conv.readOnly
		-- Destinations you can't use leave the list, unless you're reading one.
		-- Earlier sessions and read-only rows stay so their history is reachable.
		local visible = available or not sendable or conv.key == C.selectedKey
		if visible then
			local sectionKey = conv.sort >= 30 and "whispers" or "chat"
			if sectionKey ~= currentSection then
				currentSection = sectionKey
				if -y + SECTION_HEIGHT > bottom then
					break
				end
				sectionCount = sectionCount + 1
				local section = sections[sectionCount] or CreateSection(sectionCount)
				section:ClearAllPoints()
				section:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, y - 2)
				section:SetText(SECTION_NAMES[sectionKey])
				section:Show()
				y = y - SECTION_HEIGHT
			end
			if -y + ROW_HEIGHT > bottom then
				break
			end
			rowCount = rowCount + 1
			local row = rows[rowCount] or CreateRow(rowCount)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, y)
			row:SetPoint("RIGHT", sidebar, "RIGHT", -4, 0)
			y = y - ROW_HEIGHT
			row.conv = conv

			local selected = conv.key == C.selectedKey
			local label = conv.label
			if labelCount[label] and labelCount[label] > 1 and conv.fullName then
				label = conv.fullName
			end
			row.label:SetText(label)
			row.label:SetFontObject(selected and "GameFontNormalSmall" or "GameFontHighlightSmall")
			if (sendable and not available) or conv.readOnly then
				row.label:SetTextColor(0.5, 0.5, 0.5)
			elseif selected then
				row.label:SetTextColor(1, 0.82, 0)
			elseif conv.color then
				row.label:SetTextColor(conv.color.r, conv.color.g, conv.color.b)
			else
				row.label:SetTextColor(0.9, 0.9, 0.9)
			end
			row.selected:SetShown(selected)
			local dot = DotColor(conv)
			row.dot:SetVertexColor(dot.r, dot.g, dot.b, (conv.readOnly or (sendable and not available)) and 0.5 or 1)
			if conv.chatType == "WHISPER" then
				row.level:SetText(conv.level and tostring(conv.level) or "-")
			else
				row.level:SetText("")
			end

			if conv.unread > 0 then
				row.badge:SetText(conv.unread > 99 and "99+" or tostring(conv.unread))
				row.badgeBg:SetWidth(math.max(16, row.badge:GetStringWidth() + 8))
				if conv.quiet then
					-- Busy public channels stay low-key.
					row.badgeBg:SetVertexColor(0.3, 0.3, 0.3, 0.9)
					row.badge:SetTextColor(0.85, 0.85, 0.85)
				else
					row.badgeBg:SetVertexColor(0.7, 0.08, 0.05, 1)
					row.badge:SetTextColor(1, 1, 1)
				end
				row.badgeBg:Show()
			else
				row.badge:SetText("")
				row.badgeBg:Hide()
			end
			-- The level sits beside the badge, or at the edge when there isn't one.
			row.level:ClearAllPoints()
			if row.badgeBg:IsShown() then
				row.level:SetPoint("RIGHT", row.badgeBg, "LEFT", -4, 0)
			else
				row.level:SetPoint("RIGHT", row, "RIGHT", -6, 0)
			end
			row:Show()
		end
	end
	for i = rowCount + 1, #rows do
		rows[i]:Hide()
		rows[i].conv = nil
	end
	for i = sectionCount + 1, #sections do
		sections[i]:Hide()
	end

	local selected = C:GetSelected()
	if selected then
		local nameColor = (selected.chatType == "WHISPER" and selected.color) or nil
		-- People get their full name here; the sidebar has the short one.
		-- (A Battle.net friend's label already renders their account name.)
		local fullWanted = selected.chatType == "WHISPER" or (labelCount[selected.label] or 0) > 1
		self.headerName:SetText(fullWanted and selected.fullName or selected.label)
		if nameColor then
			self.headerName:SetTextColor(nameColor.r, nameColor.g, nameColor.b)
		else
			self.headerName:SetTextColor(1, 0.82, 0)
		end
		self.headerContext:SetText(Context(selected))
		if selected.readOnly then
			self:SetHint(selected.label .. " has ended. Its messages stay here to read.")
		elseif selected.chatType and not C:IsAvailable(selected) then
			if selected.chatType == "CHANNEL" then
				self:SetHint("You left " .. selected.label .. ". Pick another conversation to reply.")
			else
				self:SetHint("You can't send to " .. selected.label .. " right now.")
			end
		elseif selected.chatType == "CHANNEL" and selected.fullName and selected.fullName ~= selected.label then
			self:SetHint("To " .. selected.fullName .. "  -  press Enter to chat")
		elseif selected.chatType then
			self:SetHint("To " .. (selected.fullName or selected.label) .. "  -  press Enter to chat")
		else
			-- A read-only row: say where typing will actually go.
			local editBox = ns.Input:GetAdopted()
			local target = editBox and C:Get(C:KeyForEditBox(editBox))
			if target then
				self:SetHint("Press Enter to chat in " .. target.label)
			else
				self:SetHint("Press Enter to chat")
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Replacing the default chat window
-------------------------------------------------------------------------------
-- Hides the default chat window while Hear Ye is showing.
--
-- The default chat frames are moved under a hidden parent instead of being
-- unregistered or emptied. They keep receiving and formatting every message,
-- and Hear Ye copies the lines it can't read itself (system messages, NPC
-- speech, restricted messages) from ChatFrame1. Hiding Hear Ye, turning the
-- option off, or disabling the addon puts the default chat straight back.

local ChatReplace = {}
ns.ChatReplace = ChatReplace

local hider = CreateFrame("Frame")
hider:Hide()

local moved = {} -- frame -> original parent
local suspended = {} -- reason -> true, e.g. Edit Mode is open

local function Targets()
	local list = {}
	local function add(f)
		if f then
			list[#list + 1] = f
		end
	end
	-- Regular windows and whisper pop-outs, which take numbers past NUM_CHAT_WINDOWS.
	for i = 1, 20 do
		add(_G["ChatFrame" .. i])
		add(_G["ChatFrame" .. i .. "Tab"])
		add(_G["ChatFrame" .. i .. "ButtonFrame"])
	end
	add(_G.GeneralDockManager)
	add(_G.ChatFrameMenuButton)
	add(_G.ChatFrameChannelButton)
	add(_G.ChatFrameToggleVoiceDeafenButton)
	add(_G.ChatFrameToggleVoiceMuteButton)
	add(_G.QuickJoinToastButton)
	return list
end

local function Wanted()
	return ns.db.replaceChat and ns.Shell:IsActive() and next(suspended) == nil
end

function ChatReplace:IsHiding()
	return next(moved) ~= nil
end

function ChatReplace:Apply()
	if not ns.db then
		return
	end
	if Wanted() then
		for _, f in ipairs(Targets()) do
			local parent = f:GetParent()
			if not moved[f] and parent ~= hider then
				if f:IsProtected() and InCombatLockdown() then
					ns:Log("skipped protected %s in combat", f:GetName() or "frame")
				else
					local ok, err = pcall(f.SetParent, f, hider)
					if ok then
						moved[f] = parent
					else
						ns:Log("could not hide %s: %s", f:GetName() or "frame", tostring(err))
					end
				end
			end
		end
	else
		for f, parent in pairs(moved) do
			local ok, err = pcall(f.SetParent, f, parent)
			if not ok then
				ns:Log("could not restore %s: %s", f:GetName() or "frame", tostring(err))
			end
			moved[f] = nil
		end
	end
end

function ChatReplace:SetEnabled(enabled)
	ns.db.replaceChat = enabled and true or false
	self:Apply()
	ns:Log("replace default chat: %s", tostring(ns.db.replaceChat))
end

function ChatReplace:Suspend(reason, on)
	suspended[reason] = on and true or nil
	self:Apply()
end

function ChatReplace:Init()
	-- A new whisper pop-out window would otherwise appear on screen.
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function()
			ChatReplace:Apply()
		end)
	end
	-- Edit Mode needs to see the chat window to move it.
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			ChatReplace:Suspend("editmode", true)
		end, ChatReplace)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			ChatReplace:Suspend("editmode", false)
		end, ChatReplace)
	end
	self:Apply()
end
