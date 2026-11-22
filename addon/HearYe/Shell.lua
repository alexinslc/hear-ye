-- The window: bronze-bordered frame, sidebar, conversation pane, input area.
-- Styled after the game's own windows (and Fireside Tales): tooltip border in
-- bronze, recessed marble insets, quest-log rows and section headers.
local _, ns = ...

local Shell = {}
ns.Shell = Shell

local SIDEBAR_WIDTH = 150
local COMPACT_WIDTH = 82 -- the list as a strip of short names and unread pills
local HEADER_HEIGHT = 22
local INPUT_HEIGHT = 30
local ROW_HEIGHT = 18
local SECTION_HEIGHT = 20
local MIN_HEIGHT = 200
-- Fitting itself beside your character's frame, the window may go a little
-- narrower than you can drag it.
local AUTO_MIN_WIDTH = 300
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

-- Moving the window keeps your spot; resizing it keeps your size. Until you
-- do either, Hear Ye places and sizes itself for your screen.
local function SavePosition(resized)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.db.position = { point, relativePoint, x, y }
	if resized then
		ns.db.width, ns.db.height = frame:GetSize()
		ns.db.sized = true
	end
end

-- Bars that sit low on the screen. Hear Ye is drawn under everything, so
-- it sits above whichever of these are under it.
local LOW_BARS = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
	"StanceBar", "StanceBarFrame", "PetActionBar", "PossessActionBar", "PossessBarFrame",
}

local function Clamp(value, low, high)
	return math.min(high, math.max(low, value))
end

-- A size in proportion to the screen, the same share of it at 1080p, 1440p,
-- 4K or ultrawide, and at any UI scale.
local function AutoSize()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	return math.floor(Clamp(w * 0.36, 440, 700)), math.floor(Clamp(h * 0.42, 260, 480))
end

-- The lowest a window from left to right can sit without covering a bar.
local function ClearOfBars(left, right, bottom)
	local uiScale = UIParent:GetEffectiveScale()
	for _, name in ipairs(LOW_BARS) do
		local bar = _G[name]
		if bar and bar.IsVisible and bar:IsVisible() and bar:GetTop() and bar:GetLeft() then
			local scale = bar:GetEffectiveScale() / uiScale
			local barLeft, barRight, barTop = bar:GetLeft() * scale, bar:GetRight() * scale, bar:GetTop() * scale
			if barRight > left and barLeft < right and barTop > bottom then
				bottom = barTop + 6
			end
		end
	end
	return bottom
end

-- Unit frames that can sit just above the bars, next to where Hear Ye goes.
-- Hear Ye is drawn under them, so its own size stops short of them.
local UNIT_FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }

local function Bounds(region)
	if not (region and region.IsVisible and region:IsVisible() and region:GetLeft() and region:GetBottom()) then
		return nil
	end
	local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return region:GetLeft() * scale, region:GetRight() * scale, region:GetBottom() * scale, region:GetTop() * scale
end

-- Narrow the window, or failing that make it shorter, so it doesn't reach
-- under a unit frame.
local function ClearOfUnitFrames(left, bottom, width, height)
	for _, name in ipairs(UNIT_FRAMES) do
		local l, r, b, t = Bounds(_G[name])
		if l and r > left and l < left + width and t > bottom and b < bottom + height then
			if l - 6 - left >= AUTO_MIN_WIDTH then
				width = l - 6 - left
			elseif b - 6 - bottom >= MIN_HEIGHT then
				height = b - 6 - bottom
			end
		end
	end
	return width, height
end

local function ApplyPosition()
	local width, height = ns.db.width, ns.db.height
	local pos = ns.db.position
	frame:ClearAllPoints()
	if pos then
		frame:SetSize(width, height)
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		return
	end
	-- Bottom left, like the default chat, just above the action bars and
	-- beside (not under) your character's frame.
	if not ns.db.sized then
		width, height = AutoSize()
	end
	local margin = math.floor(Clamp(UIParent:GetWidth() * 0.012, 10, 32))
	local bottom = ClearOfBars(margin, margin + width, margin)
	if not ns.db.sized then
		width, height = ClearOfUnitFrames(margin, bottom, width, height)
	end
	frame:SetSize(math.floor(width), math.floor(height))
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", margin, bottom)
end

-- Placing itself: the bars only take their Edit Mode spots a moment after
-- login, so the window stays invisible until they have, then appears in
-- place instead of jumping there. Later changes (a new stance bar, a pet
-- bar, a different resolution or UI scale) move it along.
local placer = CreateFrame("Frame")
local revealed = false

local function Reveal()
	if not revealed and frame then
		revealed = true
		ApplyPosition()
		frame:SetAlpha(1)
	end
end

local function Replace()
	if frame and (not ns.db.position or not ns.db.sized) then
		ApplyPosition()
	end
end

placer:SetScript("OnEvent", function(_, event)
	if event == "EDIT_MODE_LAYOUTS_UPDATED" then
		-- Bars are in their places now.
		if C_Timer then
			C_Timer.After(0, function()
				Reveal()
				Replace()
			end)
		else
			Reveal()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- In case the layout event never comes, don't stay invisible.
		if C_Timer then
			C_Timer.After(1.5, Reveal)
		else
			Reveal()
		end
	elseif revealed and C_Timer then
		C_Timer.After(0, Replace)
	end
end)

local function WatchPlacement()
	for _, event in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED",
		"DISPLAY_SIZE_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE", "UPDATE_BONUS_ACTIONBAR" }) do
		pcall(placer.RegisterEvent, placer, event)
	end
	local watched = {}
	for _, name in ipairs(LOW_BARS) do watched[#watched + 1] = name end
	for _, name in ipairs(UNIT_FRAMES) do watched[#watched + 1] = name end
	for _, name in ipairs(watched) do
		local bar = _G[name]
		if bar and bar.HookScript then
			bar:HookScript("OnShow", function() if revealed and C_Timer then C_Timer.After(0, Replace) end end)
			bar:HookScript("OnHide", function() if revealed and C_Timer then C_Timer.After(0, Replace) end end)
		end
	end
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

-- An unread count on a pill, like a chat app's badge: two round ends and a
-- straight middle, so it stays a clean oval at any width. Red for messages
-- to you and your groups, grey for busy public channels.
local PILL_HEIGHT = 14
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function SetPill(pill, count, quiet)
	if not count or count <= 0 then
		pill:Hide()
		return
	end
	pill.text:SetText(count > 99 and "99+" or tostring(count))
	pill:SetWidth(math.max(PILL_HEIGHT, math.ceil(pill.text:GetStringWidth()) + 10))
	local r, g, b, a = 0.78, 0.1, 0.08, 1
	if quiet then
		r, g, b, a = 0.32, 0.32, 0.32, 0.95
	end
	for _, piece in ipairs(pill.pieces) do
		piece:SetVertexColor(r, g, b, a)
	end
	pill.text:SetTextColor(1, 1, 1)
	pill:Show()
end

local function CreatePill(parent)
	local pill = CreateFrame("Frame", nil, parent)
	pill:SetHeight(PILL_HEIGHT)
	local left = pill:CreateTexture(nil, "ARTWORK")
	left:SetTexture(DISC)
	left:SetSize(PILL_HEIGHT, PILL_HEIGHT)
	left:SetPoint("LEFT")
	local right = pill:CreateTexture(nil, "ARTWORK")
	right:SetTexture(DISC)
	right:SetSize(PILL_HEIGHT, PILL_HEIGHT)
	right:SetPoint("RIGHT")
	local middle = pill:CreateTexture(nil, "ARTWORK")
	middle:SetTexture("Interface\\Buttons\\WHITE8X8")
	middle:SetPoint("TOPLEFT", left, "TOP")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOM")
	pill.pieces = { left, right, middle }
	pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pill.text:SetPoint("CENTER", 0, 0)
	pill.SetCount = SetPill
	pill:Hide()
	return pill
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

	-- Unread count on a pill, so it can't be read as a level.
	row.pill = CreatePill(row)
	row.pill:SetPoint("RIGHT", row, "RIGHT", -3, 0)

	-- Whispers show the other player's level, small and grey; "-" when unknown.
	row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.level:SetPoint("RIGHT", row, "RIGHT", -22, 0)

	-- A small square marker, as Fireside Tales marks its stories: chat-type
	-- colour for channels, class colour for people, grey when unknown.
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(8, 8)
	row.dot:SetPoint("LEFT", row, "LEFT", 16, 0)
	row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.dot, "RIGHT", 5, 0)
	row.label:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	-- In the compact strip: a short name in the conversation's colour.
	row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.tag:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.tag:SetWidth(38)
	row.tag:SetJustifyH("LEFT")
	row.tag:SetWordWrap(false)

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

-- A section header in the quest-log style: plus or minus, a gold name, and
-- how many conversations it holds. A closed section with unread messages
-- shows their total on a pill instead.
local function CreateSection(index)
	local section = CreateFrame("Button", nil, sidebar)
	section:SetHeight(SECTION_HEIGHT)
	section:RegisterForClicks("LeftButtonUp")
	section:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	section.icon = section:CreateTexture(nil, "ARTWORK")
	section.icon:SetSize(13, 13)
	section.icon:SetPoint("LEFT", 2, 0)
	section.label = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	section.label:SetPoint("LEFT", section.icon, "RIGHT", 4, 0)
	section.label:SetJustifyH("LEFT")
	section.pill = CreatePill(section)
	section.pill:SetPoint("RIGHT", -3, 0)
	section.count = section:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	section.count:SetPoint("RIGHT", -6, 0)
	section:SetScript("OnClick", function(self)
		ns.db.collapsed[self.key] = not ns.db.collapsed[self.key] or nil
		local sound = SOUNDKIT and SOUNDKIT[ns.db.collapsed[self.key] and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON"]
		if sound then
			PlaySound(sound)
		end
		Shell:Refresh()
	end)
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

local ICON = "Interface\\AddOns\\HearYe\\Textures\\Icon"

function Shell:Create()
	-- The game's own window, the same one Fireside Tales uses: title bar,
	-- round portrait, close button. A plain bronze frame stands in if the
	-- client doesn't have the template.
	local ok, made = pcall(CreateFrame, "Frame", "HearYeFrame", UIParent, "PortraitFrameTemplate")
	if ok and made and made.SetTitle then
		frame = made
		frame:SetTitle("Hear Ye")
		if frame.SetPortraitToAsset then
			frame:SetPortraitToAsset(ICON)
		end
		self.styled = true
	else
		frame = CreateFrame("Frame", "HearYeFrame", UIParent, "BackdropTemplate")
		ns.ApplyBackdrop(frame, ns.db.opacity)
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -8)
		title:SetText("Hear Ye")
		frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		frame.CloseButton:SetPoint("TOPRIGHT", -2, -2)
	end
	-- Closing it is the same as /hearye hide, so it stays closed after a reload.
	if frame.CloseButton then
		frame.CloseButton:SetScript("OnClick", function()
			Shell:SetShown(false)
			ns:Print("Hidden. Type /hearye to bring it back.")
		end)
	end
	-- The lowest layer, so unit frames (your character, target) and other
	-- windows always draw over Hear Ye, never under it. The native edit box
	-- raises itself to DIALOG while you type.
	frame:SetFrameStrata("BACKGROUND")
	frame:SetToplevel(false)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(AUTO_MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	end
	ApplyPosition()

	-- The title bar: drag handle and right-click menu. Stops short of the
	-- gear and close button so they stay clickable.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 56, -1)
	header:SetPoint("TOPRIGHT", -46, -1)
	header:SetHeight(HEADER_HEIGHT)
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
	-- The gear sits in the title bar, left of the close button.
	settingsButton = CreateFrame("Button", nil, frame)
	settingsButton:SetSize(15, 15)
	settingsButton:SetPoint("RIGHT", header, "RIGHT", 18, 0)
	-- Above the window's border and title art, which sit high in the
	-- template and would otherwise hide the gear and swallow its clicks.
	local top = frame:GetFrameLevel()
	for _, piece in ipairs({ frame.NineSlice, frame.TitleContainer, frame.PortraitContainer }) do
		if piece and piece.GetFrameLevel then
			top = math.max(top, piece:GetFrameLevel())
		end
	end
	header:SetFrameLevel(top + 1)
	settingsButton:SetFrameLevel(top + 3)
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

	-- The list starts below the portrait, as in Fireside Tales; the
	-- conversation pane uses the full height beside it.
	sidebar = ns.NewInset(frame)
	sidebar:SetPoint("TOPLEFT", 8, self.styled and -60 or -HEADER_HEIGHT - 4)
	sidebar:SetPoint("BOTTOMLEFT", 8, 6)
	sidebar:SetWidth(SIDEBAR_WIDTH)

	inputArea = CreateFrame("Frame", nil, frame)
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
	self.paneInset = paneInset
	self.sidebar = sidebar
	self:CreateListToggle()
	self:ApplySidebar()
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
		SavePosition(true)
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
	-- Invisible until the action bars have their places; see Reveal.
	frame:SetAlpha(0)
	WatchPlacement()
end

-- Two kinds of chrome. Backgrounds (the window's fill and the marble panels)
-- follow the opacity setting. The frame art (border, title bar, portrait,
-- buttons, header rule) stays solid while the window is in use. With fading
-- on, both fade out together when the mouse is away, like the default chat.
-- Text, names and the input box are never touched, so they stay readable.
local shownAmount -- 0: faded out, 1: fully shown

local function Pieces()
	local art, backgrounds = {}, {}
	local function add(list, piece)
		if piece and piece.SetAlpha then
			list[#list + 1] = piece
		end
	end
	if Shell.styled then
		add(art, frame.NineSlice)
		add(art, frame.PortraitContainer or frame.portrait)
		add(art, frame.TitleContainer)
		add(backgrounds, frame.Bg)
		add(backgrounds, frame.TopTileStreaks)
	end
	add(art, frame.CloseButton)
	add(art, settingsButton)
	add(art, Shell.grip)
	add(art, Shell.listToggle)
	add(art, Shell.chrome.rule)
	for _, inset in ipairs(Shell.chrome.insets) do
		add(art, inset.NineSlice)
		add(backgrounds, inset.Bg)
	end
	return art, backgrounds
end

local function PaintChrome(amount)
	shownAmount = amount
	local art, backgrounds = Pieces()
	local opacity = ns.db.opacity
	for _, piece in ipairs(art) do
		piece:SetAlpha(amount)
	end
	for _, piece in ipairs(backgrounds) do
		piece:SetAlpha(amount * opacity)
	end
	if not Shell.styled then
		frame:SetBackdropColor(0.06, 0.05, 0.04, amount * opacity)
		frame:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], amount)
	end
	for _, inset in ipairs(Shell.chrome.insets) do
		if not inset.Bg and inset.SetBackdropColor then
			inset:SetBackdropColor(0, 0, 0, 0.4 * amount * opacity)
		end
	end
end

local FADE_SECONDS = 0.3
local FADE_DELAY = 1.5
local lastHover = 0

local function TargetAmount()
	if not ns.db.fadeBackground then
		return 1
	end
	local now = GetTime()
	if Shell.typing or frame:IsMouseOver() then
		lastHover = now
	end
	if now - lastHover < FADE_DELAY then
		return 1
	end
	return 0
end

local function OnFadeUpdate(_, elapsed)
	local target = TargetAmount()
	if not shownAmount then
		PaintChrome(target)
		return
	end
	local current = shownAmount
	if current ~= target then
		local step = elapsed / FADE_SECONDS
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
	return ("setting %d%%, fade %s, shown %s, %s frame; %s"):format(math.floor(ns.db.opacity * 100 + 0.5), ns.db.fadeBackground and "on" or "off",
		shownAmount and (math.floor(shownAmount * 100 + 0.5) .. "%") or "unset", self.styled and "game" or "plain", table.concat(insets, ", "))
end

function Shell:ApplyOpacity()
	if frame then
		lastHover = GetTime()
		PaintChrome(1)
	end
end

-- The conversation list can be hidden for more room to read and type. A
-- button beside the portrait hides and shows it; while it's hidden, the
-- unread total sits next to the button so nothing goes unnoticed.
function Shell:CreateListToggle()
	local toggle = CreateFrame("Button", nil, frame)
	toggle:SetSize(24, 24)
	toggle:SetPoint("TOPLEFT", frame, "TOPLEFT", self.styled and 58 or 6, self.styled and -31 or -HEADER_HEIGHT)
	toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	toggle:SetScript("OnClick", function()
		ns.db.sidebarHidden = not ns.db.sidebarHidden
		local sound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		if sound then
			PlaySound(sound)
		end
		Shell:ApplySidebar()
		Shell:Refresh()
		if GameTooltip:IsOwned(toggle) then
			toggle:GetScript("OnEnter")(toggle)
		end
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ns.db.sidebarHidden and "Show names" or "Compact list")
		GameTooltip:AddLine(ns.db.sidebarHidden and "Show each conversation's name." or "Just colours and unread counts, for more room to read.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", GameTooltip_Hide)
	toggle.label = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	toggle.label:SetPoint("LEFT", toggle, "RIGHT", 2, 0)
	toggle.pill = CreatePill(toggle)
	toggle.pill:SetPoint("LEFT", toggle, "RIGHT", 2, 0)
	self.listToggle = toggle
end

-- "Hidden" keeps the list as a narrow strip: each conversation's coloured
-- square and its unread pill, with the name in its tooltip. The pane gets
-- the room the names took.
function Shell:ApplySidebar()
	local compact = ns.db.sidebarHidden
	local toggle = self.listToggle
	local top = self.styled and -28 or -HEADER_HEIGHT - 4
	sidebar:SetWidth(compact and COMPACT_WIDTH or SIDEBAR_WIDTH)
	inputArea:ClearAllPoints()
	inputArea:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 4, 0)
	inputArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
	self.paneInset:ClearAllPoints()
	self.paneInset:SetPoint("TOP", frame, "TOP", 0, top)
	self.paneInset:SetPoint("LEFT", sidebar, "RIGHT", 4, 0)
	self.paneInset:SetPoint("BOTTOMRIGHT", inputArea, "TOPRIGHT", 0, 2)
	-- The button stays in one spot beside the portrait, so a second click
	-- in the same place switches back.
	toggle:ClearAllPoints()
	toggle:SetPoint("TOPLEFT", frame, "TOPLEFT", self.styled and 58 or 6, self.styled and -31 or -HEADER_HEIGHT)
	local arrow = compact and "NextPage" or "PrevPage"
	toggle:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "-Up")
	toggle:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "-Down")
	toggle.label:SetText(compact and "" or "Conversations")
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
	ns.db.sized = false
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

-- Short names for the compact strip, enough to tell rows apart at a glance.
local GROUP_TAGS = { nearby = "Say", party = "Party", raid = "Raid", instance = "Inst", guild = "Guild", officer = "Officer", game = "Game" }
local CHANNEL_TAGS = {
	General = "Gen", Trade = "Trade", LocalDefense = "Def", WorldDefense = "WDef",
	LookingForGroup = "LFG", GuildRecruitment = "Recruit", Services = "Serv", NewcomerChat = "New",
}

local function ShortTag(conv)
	if conv.archiveOf then
		return "Old " .. (GROUP_TAGS[conv.archiveOf] or "")
	end
	if conv.group and GROUP_TAGS[conv.group] then
		return GROUP_TAGS[conv.group]
	end
	local label = conv.label or "?"
	if conv.chatType == "CHANNEL" then
		return CHANNEL_TAGS[label] or label
	end
	-- People by first name; the full name is in the tooltip.
	return label:match("^(%S+)") or label
end

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
	local compact = ns.db.sidebarHidden
	local y = -6
	local bottom = sidebar:GetHeight() - 6
	local rowCount, sectionCount = 0, 0

	-- Short names are for display; when two would look the same, show both
	-- in full so they can't be mistaken for each other.
	local labelCount = {}
	for _, conv in ipairs(list) do
		if conv.label then
			labelCount[conv.label] = (labelCount[conv.label] or 0) + 1
		end
	end

	-- First sort the visible rows into their sections, so each header can
	-- show its count before its rows are laid out.
	local groups, order = {}, {}
	for _, conv in ipairs(list) do
		local available = C:IsAvailable(conv)
		local sendable = conv.chatType ~= nil and not conv.readOnly
		-- Destinations you can't use leave the list, unless you're reading one.
		-- Earlier sessions and read-only rows stay so their history is reachable.
		if available or not sendable or conv.key == C.selectedKey then
			local sectionKey = conv.sort >= 30 and "whispers" or "chat"
			local group = groups[sectionKey]
			if not group then
				group = { key = sectionKey, convs = {}, unread = 0, loud = false }
				groups[sectionKey] = group
				order[#order + 1] = group
			end
			group.convs[#group.convs + 1] = conv
			group.unread = group.unread + conv.unread
			if conv.unread > 0 and not conv.quiet then
				group.loud = true
			end
		end
	end

	local full = false
	for _, group in ipairs(order) do
		if full or -y + SECTION_HEIGHT > bottom then
			break
		end
		-- The strip has no headers or closed sections; a small gap
		-- separates the groups instead.
		local collapsed = not compact and ns.db.collapsed[group.key]
		if compact then
			if sectionCount > 0 then
				y = y - 6
			end
			sectionCount = sectionCount + 1
		else
			sectionCount = sectionCount + 1
			local section = sections[sectionCount] or CreateSection(sectionCount)
			section.key = group.key
			section:ClearAllPoints()
			section:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, y)
			section:SetPoint("RIGHT", sidebar, "RIGHT", -4, 0)
			section.label:SetText(SECTION_NAMES[group.key])
			section.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
			if collapsed and group.unread > 0 then
				section.count:SetText("")
				section.pill:SetCount(group.unread, not group.loud)
			else
				section.count:SetText(#group.convs)
				section.pill:Hide()
			end
			section:Show()
			y = y - SECTION_HEIGHT
		end

		for _, conv in ipairs(collapsed and {} or group.convs) do
			if -y + ROW_HEIGHT > bottom then
				full = true
				break
			end
			local available = C:IsAvailable(conv)
			local sendable = conv.chatType ~= nil and not conv.readOnly
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
			row.label:SetText(compact and "" or label)
			row.dot:ClearAllPoints()
			row.dot:SetPoint("LEFT", row, "LEFT", 16, 0)
			row.dot:SetShown(not compact)
			row.tag:SetText(compact and ShortTag(conv) or "")
			if (sendable and not available) or conv.readOnly then
				row.label:SetTextColor(0.5, 0.5, 0.5)
			elseif selected then
				row.label:SetTextColor(1, 0.82, 0)
			else
				row.label:SetTextColor(0.9, 0.9, 0.9)
			end
			row.selected:SetShown(selected)
			local dot = DotColor(conv)
			local dim = (conv.readOnly or (sendable and not available)) and 0.5 or 1
			row.dot:SetVertexColor(dot.r, dot.g, dot.b, dim)
			if selected then
				row.tag:SetTextColor(1, 0.82, 0)
			else
				row.tag:SetTextColor(dot.r, dot.g, dot.b, dim)
			end
			if conv.chatType == "WHISPER" and not compact then
				row.level:SetText(conv.level and tostring(conv.level) or "-")
			else
				row.level:SetText("")
			end

			-- Busy public channels stay low-key, on a grey pill.
			row.pill:SetCount(conv.unread, conv.quiet)
			-- The level sits beside the pill, or at the edge when there isn't one.
			row.level:ClearAllPoints()
			if row.pill:IsShown() then
				row.level:SetPoint("RIGHT", row.pill, "LEFT", -4, 0)
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
	for i = (compact and 1 or sectionCount + 1), #sections do
		sections[i]:Hide()
	end

	-- Each row in the strip shows its own pill; nothing goes on the button.
	if self.listToggle then
		self.listToggle.pill:Hide()
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
			-- A Battle.net friend goes by their name here; the BattleTag is in the header.
			local name = selected.chatType == "BN_WHISPER" and selected.label or (selected.fullName or selected.label)
			self:SetHint("To " .. name .. "  -  press Enter to chat")
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
