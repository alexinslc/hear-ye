-- /hearye: show, hide, lock, reset, and a status report for testing.
local _, ns = ...

local Slash = {}
ns.Slash = Slash

local PREFERRED = "/hearye"
local FALLBACK = "/hearyeaddon"

-- Another addon could already own /hearye; find out before claiming it.
local function OwnerOf(command)
	command = strupper(command)
	for key in pairs(SlashCmdList) do
		if key ~= "HEARYE" then
			local i = 1
			while true do
				local alias = _G["SLASH_" .. key .. i]
				if not alias then
					break
				end
				if strupper(alias) == command then
					return key
				end
				i = i + 1
			end
		end
	end
	return nil
end

local function Status()
	local client = ns.db.spike.client or {}
	local editBox = ns.Input:GetAdopted()
	ns:Print("Client %s (build %s), interface %s.", tostring(client.version), tostring(client.build), tostring(client.interface))
	ns:Print("Chat style: %s. Whisper mode: %s.", tostring(GetCVar("chatStyle")), tostring(GetCVar("whisperMode")))
	ns:Print("Background: %s.", ns.Shell:DescribeChrome())
	ns:Print("Input: %s. In combat: %s.", editBox and (editBox:GetName() or "adopted") or "not adopted", tostring(InCombatLockdown()))
	local restricted = 0
	for _, entry in pairs(ns.db.spike.restricted) do
		restricted = restricted + entry.seen
	end
	ns:Print("Restricted messages seen: %d. Details are saved with /reload.", restricted)
	ns:Log("status: input=%s combat=%s", editBox and (editBox:GetName() or "adopted") or "none", tostring(InCombatLockdown()))
end

local function Help()
	ns:Print("%s show | hide | setup | chat | clear | lock | unlock | reset | status | note <text>", Slash.command)
end

local handlers = {
	show = function()
		ns.Shell:SetShown(true)
	end,
	hide = function()
		ns.Shell:SetShown(false)
		ns:Print("Hidden. The default chat input is back in its usual place.")
	end,
	toggle = function()
		ns.Shell:SetShown(not ns.Shell:IsActive())
	end,
	lock = function()
		ns.Shell:SetLocked(true)
	end,
	unlock = function()
		ns.Shell:SetLocked(false)
	end,
	reset = function()
		ns.Shell:ResetPosition()
		ns:Print("Position and size reset.")
	end,
	status = Status,
	setup = function()
		ns.Setup:Show()
	end,
	clear = function()
		StaticPopup_Show("HEARYE_CLEAR_HISTORY")
	end,
	-- Shows the welcome window again on the next /reload, as on a new install.
	firstrun = function()
		ns.db.setupDone = false
		ns:Print("The welcome window will open after /reload.")
	end,
	chat = function()
		ns.ChatReplace:SetEnabled(not ns.db.replaceChat)
		ns:Print(ns.db.replaceChat and "Hear Ye is now your chat window." or "The default chat window is back.")
	end,
	-- Lets a tester mark what they just tried, so the saved log reads in order.
	note = function(rest)
		ns:Log("NOTE: %s", rest)
		ns:Print("Noted.")
	end,
}

function Slash:Register()
	local owner = OwnerOf(PREFERRED)
	if owner then
		self.command = FALLBACK
		ns:Log("%s is taken by %s; using %s", PREFERRED, owner, FALLBACK)
		ns:Print("%s is used by another addon, so Hear Ye uses %s.", PREFERRED, FALLBACK)
	else
		self.command = PREFERRED
	end
	SLASH_HEARYE1 = self.command
	SlashCmdList.HEARYE = function(msg)
		local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
		cmd = strlower(cmd or "")
		ns:Log("slash: %s %s", cmd, rest or "")
		local handler = handlers[cmd]
		if cmd == "" then
			handlers.toggle()
		elseif handler then
			handler(rest)
		else
			Help()
		end
	end
end

-------------------------------------------------------------------------------
-- Quick setup
-------------------------------------------------------------------------------
-- Quick setup: shown once on first login, and again from the gear menu or
-- /hearye setup. Kept to the few choices that matter.

local Setup = {}
ns.Setup = Setup

local window
local checks = {}

local ICON = "Interface\\AddOns\\HearYe\\Textures\\Icon"

local function NewWindow(name, title, width, height)
	local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
	if ok and frame and frame.SetTitle then
		frame:SetTitle(title)
		if frame.SetPortraitToAsset then
			frame:SetPortraitToAsset(ICON)
		end
	else
		frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
		ns.ApplyBackdrop(frame, 0.96)
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("TOP", 0, -8)
		text:SetText(title)
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	frame:SetSize(width, height)
	return frame
end

-- anchor is the element above. Under another checkbox's description, the
-- box steps back so the two checkboxes line up.
local function AddCheck(parent, anchor, label, detail, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.isCheckDetail and -30 or 0, -10)
	local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 4, 1)
	text:SetText(label)
	local sub = check:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
	sub:SetWidth(320)
	sub:SetJustifyH("LEFT")
	sub:SetText(detail)
	sub.isCheckDetail = true
	check:SetScript("OnClick", function(self)
		set(self:GetChecked())
		if SOUNDKIT then
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	check.get = get
	checks[#checks + 1] = check
	return sub
end

local steppers = {}

-- "Label   [-]  value  [+]", built from the game's own buttons.
local function AddStepper(parent, anchor, label, get, step)
	local row = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	row:SetWidth(150)
	row:SetJustifyH("LEFT")
	row:SetText(label)
	local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	minus:SetSize(24, 22)
	minus:SetPoint("LEFT", row, "RIGHT", 4, 0)
	minus:SetText("-")
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	value:SetWidth(100)
	local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	plus:SetSize(24, 22)
	plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
	plus:SetText("+")
	local stepper = { value = value, get = get }
	local function apply(delta)
		step(delta)
		value:SetText(get())
		if SOUNDKIT then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end
	minus:SetScript("OnClick", function() apply(-1) end)
	plus:SetScript("OnClick", function() apply(1) end)
	steppers[#steppers + 1] = stepper
	value:SetText(get())
	return row
end

-- The game's dropdown where the client has it; otherwise a button that
-- steps through the choices.
local function MakeSoundMenu(parent)
	local choices = ns.Messages:SoundChoices()
	local function isChosen(choice)
		return ns.db.groupSound == choice.key
	end
	local function choose(choice)
		ns.db.groupSound = choice.key
		ns.Messages:PreviewSound()
	end
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(180)
		dropdown:SetupMenu(function(_, root)
			for _, choice in ipairs(choices) do
				root:CreateRadio(choice.label, isChosen, choose, choice)
			end
		end)
		return { frame = dropdown, refresh = function()
			if dropdown.GenerateMenu then
				dropdown:GenerateMenu()
			end
		end }
	end
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(180, 22)
	local function refresh()
		for _, choice in ipairs(choices) do
			if isChosen(choice) then
				button:SetText(choice.label)
			end
		end
	end
	button:SetScript("OnClick", function()
		for i, choice in ipairs(choices) do
			if isChosen(choice) then
				choose(choices[i % #choices + 1])
				return refresh()
			end
		end
		choose(choices[1])
		refresh()
	end)
	return { frame = button, refresh = refresh }
end

-- Which messages play the sound, three to a row.
local SOUND_KINDS = {
	{ key = "whisper", label = "Whispers" },
	{ key = "party", label = "Party and raid" },
	{ key = "guild", label = "Guild" },
	{ key = "say", label = "Say" },
	{ key = "channel", label = "Channels" },
}

local function AddSoundChecks(parent, anchor)
	local area = CreateFrame("Frame", nil, parent)
	area:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, -6)
	area:SetSize(372, 52)
	for i, kind in ipairs(SOUND_KINDS) do
		local column, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local check = CreateFrame("CheckButton", nil, area, "UICheckButtonTemplate")
		check:SetSize(26, 26)
		check:SetPoint("TOPLEFT", column * 128, -row * 26)
		local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 2, 1)
		text:SetText(kind.label)
		check:SetScript("OnClick", function(self)
			ns.db.soundFor[kind.key] = self:GetChecked() and true or false
			if SOUNDKIT then
				PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			end
		end)
		check.get = function() return ns.db.soundFor[kind.key] end
		checks[#checks + 1] = check
	end
	return area
end

local function Build()
	window = NewWindow("HearYeSetupFrame", "Hear Ye", 420, 694)
	window:SetPoint("CENTER", 0, 10)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	tinsert(UISpecialFrames, "HearYeSetupFrame") -- Escape closes it.

	local heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 70, -36)
	heading:SetText("Never miss a conversation")

	local intro = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", 24, -72)
	intro:SetWidth(372)
	intro:SetJustifyH("LEFT")
	intro:SetText("Hear Ye puts Say, your party, your guild and each whisper in its own place. The list on the left shows where new messages are waiting.")

	local last = AddCheck(window, intro, "Use Hear Ye as my chat window",
		"Hides the default chat window. It comes back if you turn this off or hide Hear Ye.",
		function() return ns.db.replaceChat end,
		function(on) ns.ChatReplace:SetEnabled(on) end)
	last = AddCheck(window, last, "Lock the window in place",
		"Drag the title bar to move it, or the bottom-right corner to resize it, while it's unlocked.",
		function() return ns.db.locked end,
		function(on) ns.Shell:SetLocked(on) end)

	last = AddCheck(window, last, "Go back after replying to a whisper",
		"After /r or the reply key, you return to the conversation you were reading.",
		function() return ns.db.returnAfterReply end,
		function(on) ns.db.returnAfterReply = on and true or false end)

	local rule = window:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.72, 0.55, 0.32, 0.35)
	rule:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -30, -14)
	rule:SetSize(372, 1)

	local textSize = AddStepper(window, rule, "Text size",
		function()
			local size = ns.db.fontSize
			return size == 0 and "Game default" or tostring(size)
		end,
		function(delta)
			local size = ns.db.fontSize
			if size == 0 then
				size = ns.Messages:DefaultFontSize()
			end
			size = math.min(24, math.max(10, size + delta))
			-- Back at the game's own size means "follow the game" again.
			ns.db.fontSize = size == ns.Messages:DefaultFontSize() and 0 or size
			ns.Messages:ApplyFont()
		end)
	local opacity = AddStepper(window, textSize, "Background",
		function() return math.floor(ns.db.opacity * 100 + 0.5) .. "%" end,
		function(delta)
			-- Rounded to whole tens so repeated steps land on 0% and 100%.
			ns.db.opacity = math.min(10, math.max(0, math.floor(ns.db.opacity * 10 + 0.5) + delta)) / 10
			ns.Shell:ApplyOpacity()
		end)

	local fadeCheck = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	fadeCheck:SetSize(26, 26)
	fadeCheck:SetPoint("TOPLEFT", opacity, "BOTTOMLEFT", -4, -6)
	local fadeText = fadeCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fadeText:SetPoint("LEFT", fadeCheck, "RIGHT", 4, 1)
	fadeText:SetText("Fade the background when the mouse is away")
	fadeCheck:SetScript("OnClick", function(self)
		ns.db.fadeBackground = self:GetChecked() and true or false
		ns.Shell:ApplyOpacity()
		if SOUNDKIT then
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	fadeCheck.get = function() return ns.db.fadeBackground end
	checks[#checks + 1] = fadeCheck

	local quietCheck = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	quietCheck:SetSize(26, 26)
	quietCheck:SetPoint("TOPLEFT", fadeCheck, "BOTTOMLEFT", 0, 0)
	local quietText = quietCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	quietText:SetPoint("LEFT", quietCheck, "RIGHT", 4, 1)
	quietText:SetText("Fade the messages when the conversation is quiet")
	quietCheck:SetScript("OnClick", function(self)
		ns.db.fadeText = self:GetChecked() and true or false
		ns.Shell:ApplyOpacity()
		if SOUNDKIT then
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	quietCheck.get = function() return ns.db.fadeText end
	checks[#checks + 1] = quietCheck

	local soundLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	soundLabel:SetPoint("TOPLEFT", quietCheck, "BOTTOMLEFT", 4, -10)
	soundLabel:SetText("Sound for new messages")
	local soundNote = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	soundNote:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -3)
	soundNote:SetWidth(360)
	soundNote:SetJustifyH("LEFT")
	soundNote:SetText("Plays when you aren't already reading that conversation.")
	local soundMenu = MakeSoundMenu(window)
	soundMenu.frame:SetPoint("TOPLEFT", soundNote, "BOTTOMLEFT", -2, -8)
	local preview = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	preview:SetSize(70, 22)
	preview:SetPoint("LEFT", soundMenu.frame, "RIGHT", 8, 0)
	preview:SetText("Play")
	preview:SetScript("OnClick", function()
		ns.Messages:PreviewSound()
	end)
	window.refreshers = { soundMenu.refresh }
	local soundChecks = AddSoundChecks(window, soundMenu.frame)

	AddCheck(window, soundChecks, "Hide friends' real names",
		"Shows Battle.net friends by the character they're playing or their BattleTag, and leaves out notices that only come with real names.",
		function() return ns.db.hideRealNames end,
		function(on)
			ns.db.hideRealNames = on and true or false
			ns.Conversations:RelabelBNet()
			ns.Messages:Render()
			ns.Shell:Refresh()
		end)

	local clear = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	clear:SetSize(110, 24)
	clear:SetPoint("BOTTOMLEFT", 16, 14)
	clear:SetText("Clear history")
	clear:SetScript("OnClick", function()
		StaticPopup_Show("HEARYE_CLEAR_HISTORY")
	end)

	local done = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	done:SetSize(110, 24)
	done:SetPoint("BOTTOMRIGHT", -16, 14)
	done:SetText(DONE or "Done")
	done:SetScript("OnClick", function()
		window:Hide()
	end)

	local footer = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 20, 46)
	footer:SetPoint("RIGHT", -20, 0)
	footer:SetJustifyH("LEFT")
	footer:SetText("Change these any time from the gear on Hear Ye's title bar.")

	window:SetScript("OnShow", function()
		for _, refresh in ipairs(window.refreshers or {}) do
			refresh()
		end
		for _, stepper in ipairs(steppers) do
			stepper.value:SetText(stepper.get())
		end
		for _, check in ipairs(checks) do
			check:SetChecked(check.get())
		end
		if SOUNDKIT then
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		end
	end)
	window:SetScript("OnHide", function()
		ns.db.setupDone = true
		if SOUNDKIT then
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		end
	end)
	window:Hide()
end

function Setup:Show()
	if not window then
		Build()
	end
	window:Show()
end

StaticPopupDialogs["HEARYE_CLEAR_HISTORY"] = {
	text = "Clear Hear Ye's saved messages for this character? Whisper rows are removed too. This can't be undone.",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		ns.Conversations:ClearHistory()
		ns:Print("History cleared.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Setup:Init()
	-- Wait out the loading screen, which closes open windows as it ends.
	if not ns.db.setupDone and C_Timer then
		C_Timer.After(3, function()
			if not ns.db.setupDone then
				Setup:Show()
			end
		end)
	end
end
