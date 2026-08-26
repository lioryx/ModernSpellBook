--[[
	CTalentTree: Top-level talent tree window.
	Standalone test window opened via /msbt.
	Shows 3 spec panels side by side with CTalentIcon grid.
--]]

local CELL_SIZE = 60
local GRID_COLS_DEFAULT = 4
local GRID_COLS_MAX = 7
local GRID_ROWS = 7
local PANEL_PADDING = 20
local HEADER_HEIGHT = 40
local PANEL_INNER_PAD = 10
local FRAME_PAD = PANEL_PADDING + 10
local PANEL_WIDTH = GRID_COLS_MAX * CELL_SIZE + PANEL_INNER_PAD * 2
local GRID_VERT_PAD = 10
local PANEL_HEIGHT = GRID_ROWS * CELL_SIZE + HEADER_HEIGHT + GRID_VERT_PAD * 2 + 20
local TOTAL_WIDTH = 3 * PANEL_WIDTH + 4 * PANEL_PADDING + 20
local TOTAL_HEIGHT = PANEL_HEIGHT + 120
local VERT_OFFSET = (TOTAL_HEIGHT - PANEL_HEIGHT) / 2

local EXPANDED_HORIZONTAL_PADDING = 350
local TALENT_POINTS_AT_60 = 51

local TALENT_ASSETS = "Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\"

-- Shared constants for CExpandedSpecFrame
MSB_TALENT_CONSTANTS = {
	CELL_SIZE = CELL_SIZE,
	GRID_COLS_DEFAULT = GRID_COLS_DEFAULT,
	GRID_COLS_MAX = GRID_COLS_MAX,
	GRID_ROWS = GRID_ROWS,
	PANEL_INNER_PAD = PANEL_INNER_PAD,
	HEADER_HEIGHT = HEADER_HEIGHT,
	GRID_VERT_PAD = GRID_VERT_PAD,
	TOTAL_WIDTH = TOTAL_WIDTH,
	TOTAL_HEIGHT = TOTAL_HEIGHT,
	EXPANDED_HORIZONTAL_PADDING = EXPANDED_HORIZONTAL_PADDING,
}

-- Indexed by english class name then specIndex (1-3)
local SPEC_HAZE_COLORS = {
	WARRIOR = {{0.000, 0.800, 1.000}, {1.000, 0.600, 0.000}, {1.000, 0.240, 0.000}},  -- Arms, Fury, Protection
	PALADIN = {{1.000, 1.000, 0.000}, {1.000, 0.230, 0.000}, {1.000, 0.800, 0.000}},  -- Holy, Protection, Retribution
	HUNTER  = {{0.000, 0.500, 1.000}, {1.000, 1.000, 0.000}, {1.000, 0.300, 0.000}},  -- Beast Mastery, Marksmanship, Survival
	ROGUE   = {{0.400, 1.000, 0.000}, {0.000, 0.800, 1.000}, {0.540, 0.000, 1.000}},  -- Assassination, Combat, Subtlety
	PRIEST  = {{0.000, 0.750, 1.000}, {1.000, 1.000, 0.000}, {0.637, 0.000, 1.000}},  -- Discipline, Holy, Shadow
	SHAMAN  = {{1.000, 0.500, 0.000}, {0.300, 0.170, 1.000}, {0.000, 1.000, 0.600}},  -- Elemental, Enhancement, Restoration
	MAGE    = {{0.850, 0.545, 1.000}, {1.000, 0.350, 0.000}, {0.000, 0.350, 1.000}},  -- Arcane, Fire, Frost
	WARLOCK = {{0.620, 0.420, 1.000}, {0.860, 0.170, 0.110}, {1.000, 0.700, 0.000}},  -- Affliction, Demonology, Destruction
	DRUID   = {{0.350, 0.000, 1.000}, {1.000, 0.100, 0.150}, {0.000, 1.000, 0.000}},  -- Balance, Feral Combat, Restoration
}
local DEFAULT_HAZE_COLOR = {0.2, 0.2, 0.4}

function MSB_GetSpecDescription(englishClass, specIndex)
	return MSB_L("SpecDesc_" .. englishClass .. "_" .. specIndex)
end

StaticPopupDialogs["MSB_SIM_RENAME_PLAN"] = {
	text = MSB_L("SimRenamePrompt"),
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnAccept = function()
		local editBox = getglobal(this:GetParent():GetName() .. "EditBox")
		if (editBox and TalentSimulation) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:SetPlanName(newName)
				if (TalentTree) then
					TalentTree:UpdateSimControls()
				end
			end
		end
	end,
	EditBoxOnEnterPressed = function()
		local editBox = this
		if (editBox and TalentSimulation) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:SetPlanName(newName)
				if (TalentTree) then
					TalentTree:UpdateSimControls()
				end
			end
		end
		this:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["MSB_SIM_SAVE_PLAN"] = {
	text = MSB_L("SimSavePrompt"),
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnShow = function()
		local editBox = getglobal(this:GetName() .. "EditBox")
		if (editBox and TalentSimulation) then
			editBox:SetText(TalentSimulation:GetPlanName() or "")
			editBox:HighlightText()
		end
	end,
	OnAccept = function()
		local editBox = getglobal(this:GetParent():GetName() .. "EditBox")
		if (editBox and TalentSimulation) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:SaveWorkingPlan(newName)
				MSB_SimulationNotify(MSB_L("SimPlanSaved", newName))
				if (TalentTree) then
					TalentTree:UpdateSimControls()
					TalentTree:Refresh()
				end
			end
		end
	end,
	EditBoxOnEnterPressed = function()
		local editBox = this
		if (editBox and TalentSimulation) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:SaveWorkingPlan(newName)
				MSB_SimulationNotify(MSB_L("SimPlanSaved", newName))
				if (TalentTree) then
					TalentTree:UpdateSimControls()
					TalentTree:Refresh()
				end
			end
		end
		this:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["MSB_SIM_RENAME_SAVED"] = {
	text = MSB_L("SimRenamePrompt"),
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnAccept = function()
		local editBox = getglobal(this:GetParent():GetName() .. "EditBox")
		if (editBox and TalentSimulation and MSB_SimRenameSavedIndex) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:RenameSavedPlan(MSB_SimRenameSavedIndex, newName)
				if (TalentTree) then
					TalentTree:UpdateSimControls()
				end
			end
		end
		MSB_SimRenameSavedIndex = nil
	end,
	EditBoxOnEnterPressed = function()
		local editBox = this
		if (editBox and TalentSimulation and MSB_SimRenameSavedIndex) then
			local newName = editBox:GetText()
			if (newName and newName ~= "") then
				TalentSimulation:RenameSavedPlan(MSB_SimRenameSavedIndex, newName)
				if (TalentTree) then
					TalentTree:UpdateSimControls()
				end
			end
		end
		MSB_SimRenameSavedIndex = nil
		this:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["MSB_SIM_EXPORT"] = {
	text = MSB_L("SimExportPrompt"),
	button1 = OKAY,
	hasEditBox = 1,
	maxLetters = 255,
	OnShow = function()
		local editBox = getglobal(this:GetName() .. "EditBox")
		if (editBox and TalentSimulation) then
			editBox:SetText(TalentSimulation:ExportWorkingPlan())
			editBox:HighlightText()
			editBox:SetFocus()
		end
	end,
	EditBoxOnEnterPressed = function()
		this:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function()
		this:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["MSB_SIM_IMPORT"] = {
	text = MSB_L("SimImportPrompt"),
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 255,
	OnShow = function()
		local editBox = getglobal(this:GetName() .. "EditBox")
		if (editBox) then
			editBox:SetText("")
			editBox:SetFocus()
		end
	end,
	OnAccept = function()
		local editBox = getglobal(this:GetParent():GetName() .. "EditBox")
		if (editBox and TalentSimulation) then
			MSB_DoTalentImport(editBox:GetText())
		end
	end,
	EditBoxOnEnterPressed = function()
		local editBox = this
		if (editBox and TalentSimulation) then
			MSB_DoTalentImport(editBox:GetText())
		end
		this:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function MSB_DoTalentImport(str)
	if (not TalentSimulation) then return end
	local ok, reason = TalentSimulation:ImportPlan(str)
	if (ok) then
		MSB_SimulationNotify(MSB_L("SimImportSuccess"))
		if (TalentTree) then
			TalentTree:UpdateSimControls()
			TalentTree:Refresh()
		end
	elseif (reason == "class") then
		MSB_SimulationNotify(MSB_L("SimImportFailClass"))
	else
		MSB_SimulationNotify(MSB_L("SimImportFailFormat"))
	end
end

class "CTalentTree"
{
	__init = function(self)
		local tree = self
		local panel_width = PANEL_WIDTH
		local total_width = TOTAL_WIDTH
		local total_height = TOTAL_HEIGHT

		-- Main frame
		self.frame = CreateFrame("Frame", "ModernTalentTreeFrame", UIParent)
		self.frame:SetWidth(total_width)
		self.frame:SetHeight(total_height)
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self.frame:SetFrameStrata("HIGH")
		self.frame:SetFrameLevel(5)
		self.frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 }
		})
		self.frame:SetBackdropColor(0.03, 0.03, 0.06, 0.97)
		self.frame:EnableMouse(true)
		self.frame:SetMovable(true)
		self.frame:RegisterForDrag("LeftButton")
		self.frame:SetScript("OnDragStart", function() this:StartMoving() end)
		self.frame:SetScript("OnDragStop", function()
			this:StopMovingOrSizing()
			local point, _, relPoint, x, y = this:GetPoint()
			ModernSpellBook_DB.talentPosition = { point = point, relPoint = relPoint, x = x, y = y }
		end)
		self.frame:Hide()
		table.insert(UISpecialFrames, "ModernTalentTreeFrame")

		-- Restore saved position and scale
		if (ModernSpellBook_DB and ModernSpellBook_DB.talentPosition) then
			local pos = ModernSpellBook_DB.talentPosition
			self.frame:ClearAllPoints()
			self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
		end
		if (ModernSpellBook_DB and ModernSpellBook_DB.talentScale) then
			self.frame:SetScale(ModernSpellBook_DB.talentScale)
		end

		-- Close button (high frame level so it stays above expanded view)
		self.frame.CloseButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
		self.frame.CloseButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 6, 6)
		self.frame.CloseButton:SetFrameLevel(self.frame:GetFrameLevel() + 20)

		-- Settings
		self.settings = CTalentSettings(self.frame, self)

		-- Resize handle (bottom-right corner)
		local resizeHandle = CreateFrame("Button", nil, self.frame)
		resizeHandle:SetWidth(16)
		resizeHandle:SetHeight(16)
		resizeHandle:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, 4)
		resizeHandle:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		resizeHandle:SetScript("OnMouseDown", function()
			local startX, startY = GetCursorPosition()
			local startScale = self.frame:GetScale()
			local left, top = self.frame:GetLeft(), self.frame:GetTop()
			local es = self.frame:GetEffectiveScale()
			local screenLeft = left * es
			local screenTop = top * es
			resizeHandle:SetScript("OnUpdate", function()
				local curX, curY = GetCursorPosition()
				local dx = curX - startX
				local dy = startY - curY
				local delta = (dx + dy) / 2
				local newScale = math.max(0.5, math.min(1.2, startScale + delta / 500))
				self.frame:SetScale(newScale)
				local nes = self.frame:GetEffectiveScale()
				self.frame:ClearAllPoints()
				self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", screenLeft / nes, screenTop / nes)
			end)
		end)
		resizeHandle:SetScript("OnMouseUp", function()
			resizeHandle:SetScript("OnUpdate", nil)
			ModernSpellBook_DB.talentScale = self.frame:GetScale()
			local point, _, relPoint, x, y = self.frame:GetPoint()
			ModernSpellBook_DB.talentPosition = { point = point, relPoint = relPoint, x = x, y = y }
		end)

		-- Title
		self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.title:SetPoint("TOP", self.frame, "TOP", 12, -24)
		self.title:SetFont("Fonts\\MORPHEUS.TTF", 16)
		self.title:SetTextColor(1, 0.82, 0)

		-- Points display
		self.points_text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.points_text:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 30)
		self.points_text:SetFont(MSB_GetUIFont(), 14)
		self.points_text:SetTextColor(1.0, 1.0, 1.0)

		-- ===== Top-right simulation control cluster (left of settings gear) =====
		local tree_ref = self
		local function EnsureSim()
			if (not TalentSimulation) then
				TalentSimulation = CTalentSimulation()
				TalentSimulation:Load()
			end
		end

		local function MakeClusterButton(width, text)
			local btn = CreateFrame("Button", nil, tree_ref.frame, "UIPanelButtonTemplate")
			btn:SetWidth(width)
			btn:SetHeight(20)
			btn:SetFrameLevel(tree_ref.frame:GetFrameLevel() + 20)
			btn:SetText(text)
			return btn
		end

		-- Mode toggle (always visible, nearest the gear)
		self.sim_mode_btn = MakeClusterButton(70, MSB_L("SimToggleMode"))
		self.sim_mode_btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -55, -22)
		self.sim_mode_btn:SetScript("OnClick", function()
			EnsureSim()
			TalentSimulation:ToggleMode()
			tree_ref:UpdateSimControls()
			tree_ref:Refresh()
		end)

		-- Save plan
		self.sim_save_btn = MakeClusterButton(70, MSB_L("SimSavePlan"))
		self.sim_save_btn:SetPoint("RIGHT", self.sim_mode_btn, "LEFT", -4, 0)
		self.sim_save_btn:SetScript("OnClick", function()
			EnsureSim()
			StaticPopup_Show("MSB_SIM_SAVE_PLAN", TalentSimulation:GetPlanName())
		end)
		self.sim_save_btn:Hide()

		-- Plan list (opens dropdown)
		self.sim_list_btn = MakeClusterButton(80, MSB_L("SimPlanList"))
		self.sim_list_btn:SetPoint("RIGHT", self.sim_save_btn, "LEFT", -4, 0)
		self.sim_list_btn:Hide()

		-- Apply plan
		self.sim_apply_btn = MakeClusterButton(80, MSB_L("SimApplyPlan"))
		self.sim_apply_btn:SetPoint("RIGHT", self.sim_list_btn, "LEFT", -4, 0)
		self.sim_apply_btn:SetScript("OnClick", function()
			EnsureSim()
			TalentSimulation:BeginApply()
			tree_ref:Refresh()
		end)
		self.sim_apply_btn:Hide()

		-- Reset plan
		self.sim_reset_btn = MakeClusterButton(80, MSB_L("SimResetPlan"))
		self.sim_reset_btn:SetPoint("RIGHT", self.sim_apply_btn, "LEFT", -4, 0)
		self.sim_reset_btn:SetScript("OnClick", function()
			EnsureSim()
			TalentSimulation:ResetPlan()
			tree_ref:Refresh()
		end)
		self.sim_reset_btn:Hide()

		-- Working plan name label (left of the cluster)
		self.plan_name_label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.plan_name_label:SetPoint("RIGHT", self.sim_reset_btn, "LEFT", -8, 0)
		self.plan_name_label:SetFont(MSB_GetUIFont(), 12)
		self.plan_name_label:SetTextColor(0, 1, 1)
		self.plan_name_label:Hide()

		-- Plan list dropdown
		self.plan_list_dropdown = CreateFrame("Frame", "ModernTalentPlanListDropDown", self.frame)
		self.plan_list_dropdown.displayMode = "MENU"
		self.plan_list_dropdown.initialize = function(level)
			tree_ref:InitializePlanListDropdown(level)
		end
		self.sim_list_btn:SetScript("OnClick", function()
			EnsureSim()
			ToggleDropDownMenu(1, nil, tree_ref.plan_list_dropdown, tree_ref.sim_list_btn, 0, 0)
		end)

		self.enabled = true

		-- Event handling
		self.event_frame = CreateFrame("Frame")
		self.event_frame:RegisterEvent("PLAYER_TALENT_UPDATE")
		self.event_frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
		self.event_frame:SetScript("OnEvent", function()
			if (TalentSimulation and TalentSimulation:IsApplying()) then
				TalentSimulation:ContinueApply()
			end
			if (tree.frame:IsVisible()) then
				tree:Refresh()
			end
		end)

		self.specs = {}
		self.built = false
		self.expanded_spec = nil

		-- Expanded detail view
		self.expanded_view = CExpandedSpecFrame(self.frame, MSB_TALENT_CONSTANTS)
		self.expanded_view.parent_tree = self

		-- Back button (high frame level so it stays above expanded view)
		self.back_btn = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
		self.back_btn:SetWidth(60)
		self.back_btn:SetHeight(22)
		self.back_btn:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -12)
		self.back_btn:SetText(MSB_L("TalentBack"))
		self.back_btn:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		self.back_btn:Hide()
		self.back_btn:SetScript("OnClick", function()
			tree:CollapseSpec()
		end)

		-- Share / Import buttons (top-left, in line with the right-side sim cluster)
		self.sim_share_btn = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
		self.sim_share_btn:SetWidth(60)
		self.sim_share_btn:SetHeight(20)
		self.sim_share_btn:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 24, -22)
		self.sim_share_btn:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		self.sim_share_btn:SetText(MSB_L("SimShare"))
		self.sim_share_btn:Hide()
		self.sim_share_btn:SetScript("OnClick", function()
			if (not TalentSimulation) then
				TalentSimulation = CTalentSimulation()
				TalentSimulation:Load()
			end
			StaticPopup_Show("MSB_SIM_EXPORT")
		end)

		self.sim_import_btn = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
		self.sim_import_btn:SetWidth(60)
		self.sim_import_btn:SetHeight(20)
		self.sim_import_btn:SetPoint("LEFT", self.sim_share_btn, "RIGHT", 4, 0)
		self.sim_import_btn:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		self.sim_import_btn:SetText(MSB_L("SimImport"))
		self.sim_import_btn:Hide()
		self.sim_import_btn:SetScript("OnClick", function()
			if (not TalentSimulation) then
				TalentSimulation = CTalentSimulation()
				TalentSimulation:Load()
			end
			StaticPopup_Show("MSB_SIM_IMPORT")
		end)

	end;

	-- ======================== TOGGLE =============================

	Toggle = function(self)
		if (self.frame:IsVisible()) then
			self.frame:Hide()
		else
			if (not self.built) then
				self:BuildSpecs()
				self.built = true
			end
			if (not TalentSimulation) then
				TalentSimulation = CTalentSimulation()
				TalentSimulation:Load()
			end
			self:Refresh()
			self.frame:Show()
		end
	end;

	-- ===================== BUILD SPECS ===========================

	BuildSpecs = function(self)
		local className, englishClass = UnitClass("player")
		self.title:SetText(MSB_L("TalentTitle", tostring(className)))

		-- Class icon before title
		local titleIconFrame = CreateFrame("Frame", nil, self.frame)
		titleIconFrame:SetWidth(24)
		titleIconFrame:SetHeight(24)
		titleIconFrame:SetFrameLevel(self.frame:GetFrameLevel() + 20)
		titleIconFrame:SetPoint("RIGHT", self.title, "LEFT", -8, 0)
		self.title_icon_frame = titleIconFrame
		local titleIcon = titleIconFrame:CreateTexture(nil, "OVERLAY")
		titleIcon:SetAllPoints(titleIconFrame)
		titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		titleIcon:SetTexture("Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\classicon-" .. string.lower(englishClass))

		local numTabs = GetNumTalentTabs()
		-- Offset to center 4-col layout within 7-col panel
		local col_offset = (GRID_COLS_MAX - GRID_COLS_DEFAULT) * CELL_SIZE / 2

		for t = 1, numTabs do
			local tabName, tabIcon, pointsSpent = GetTalentTabInfo(t)
			local numTalents = GetNumTalents(t)

			-- Spec panel container
			-- Anchor by CENTER so SetScale scales from center naturally
			local centerX = FRAME_PAD + (t - 1) * (PANEL_WIDTH + PANEL_PADDING) + PANEL_WIDTH / 2
			local centerY = -VERT_OFFSET - PANEL_HEIGHT / 2

			local panel = CreateFrame("Frame", nil, self.frame)
			panel:SetWidth(PANEL_WIDTH)
			panel:SetHeight(PANEL_HEIGHT)
			panel:SetPoint("CENTER", self.frame, "TOPLEFT", centerX, centerY)
			panel:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 }
			})
			panel:SetBackdropColor(0.06, 0.06, 0.1, 0.9)


			-- Spec background texture (two 512x512 halves, right-cropped to fit panel)
			local bgBase = "Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\Backgrounds\\talentbg-" .. string.lower(englishClass) .. "-" .. t
			-- Original image is 1024x512 (2:1). Scale to fit panel height, crop left.
			local scaledWidth = PANEL_HEIGHT * 2
			local visibleFraction = PANEL_WIDTH / scaledWidth
			local leftCrop = 1 - visibleFraction
			-- leftCrop is in 0..1 of the full 1024 image
			-- Left half covers 0..0.5, right half covers 0.5..1.0
			local bgTexLeft = panel:CreateTexture(nil, "ARTWORK")
			local bgTexRight = panel:CreateTexture(nil, "ARTWORK")
			bgTexLeft:SetTexture(bgBase .. "-left")
			bgTexRight:SetTexture(bgBase .. "-right")
			bgTexLeft:SetAlpha(0.6)
			bgTexRight:SetAlpha(0.6)
			if (leftCrop >= 0.5) then
				-- Entire visible area is in the right half
				local rightStart = (leftCrop - 0.5) * 2
				bgTexRight:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
				bgTexRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
				bgTexRight:SetTexCoord(rightStart, 1, 0, 1)
				bgTexLeft:Hide()
			else
				-- Visible area spans both halves
				local leftStart = leftCrop * 2
				local leftVisibleFrac = (0.5 - leftCrop) / (1 - leftCrop)
				local splitX = PANEL_WIDTH * leftVisibleFrac
				bgTexLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
				bgTexLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
				bgTexLeft:SetWidth(splitX)
				bgTexLeft:SetTexCoord(leftStart, 1, 0, 1)
				bgTexRight:SetPoint("TOPLEFT", bgTexLeft, "TOPRIGHT", 0, 0)
				bgTexRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
				bgTexRight:SetTexCoord(0, 1, 0, 1)
			end


			-- Spec header
			local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			header:SetPoint("TOP", panel, "TOP", 0, -12)
			header:SetFont(MSB_GetUIFont(), 14)
			header:SetText(string.upper(tabName))
			header:SetTextColor(1, 1, 1)

			-- Per-branch reset button (simulation mode only; top-right of panel)
			local resetSpecIndex = t
			local resetBtn = CreateFrame("Button", nil, panel)
			resetBtn:SetWidth(16)
			resetBtn:SetHeight(16)
			resetBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
			resetBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
			resetBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
			resetBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
			resetBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
			resetBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(resetBtn, "ANCHOR_RIGHT")
				GameTooltip:SetText(MSB_L("SimBranchReset"), 1, 1, 1)
				GameTooltip:Show()
			end)
			resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			resetBtn:SetScript("OnClick", function()
				if (TalentSimulation) then
					TalentSimulation:ResetTree(resetSpecIndex)
					TalentTree:Refresh()
				end
			end)
			resetBtn:Hide()

			-- Talent grid
			local classColors = SPEC_HAZE_COLORS[englishClass]
			local haze_color = (classColors and classColors[t]) or DEFAULT_HAZE_COLOR
			local grid = CTalentGrid(panel, t, CELL_SIZE,
				PANEL_INNER_PAD + col_offset, HEADER_HEIGHT + GRID_VERT_PAD,
				haze_color, GRID_ROWS)

			-- Click panel to expand
			local specIndex = t
			panel:EnableMouse(true)
			panel:SetScript("OnMouseUp", function()
				if (arg1 == "LeftButton") then
					TalentTree:ExpandSpec(specIndex)
				end
			end)

			table.insert(self.specs, {
				panel = panel,
				header = header,
				reset_btn = resetBtn,
				grid = grid,
				tab_index = t,
				tab_name = tabName,
				tab_icon = tabIcon,
			})
		end
	end;

	-- ==================== REBUILD GRIDS ===========================

	RebuildAllGrids = function(self)
		for _, spec in ipairs(self.specs) do
			if (spec.grid and spec.grid.RebuildGridLines) then
				spec.grid:RebuildGridLines()
			end
		end
		-- Refresh expanded view grid lines if open (reuse, don't recreate)
		if (self.expanded_spec and self.expanded_view and self.expanded_view.grid) then
			self.expanded_view.grid:RebuildGridLines()
			local _, englishClass = UnitClass("player")
			local classColors = SPEC_HAZE_COLORS[englishClass]
			local spec = self.specs[self.expanded_spec]
			self.expanded_view:Show(spec, self.expanded_spec, classColors)
		end
		self:Refresh()
	end;

	-- ==================== EXPAND / COLLAPSE =======================

	ExpandSpec = function(self, specIndex)
		self.expanded_spec = specIndex
		local spec = self.specs[specIndex]
		local _, englishClass = UnitClass("player")

		-- Hide overview
		for _, s in ipairs(self.specs) do
			s.panel:Hide()
		end
		self.title:Hide()
		if (self.title_icon_frame) then
			self.title_icon_frame:Hide()
		end

		-- Show expanded view
		local classColors = SPEC_HAZE_COLORS[englishClass]
		self.expanded_view:Show(spec, specIndex, classColors)
		self.back_btn:Show()
		self:Refresh()
	end;

	CollapseSpec = function(self)
		self.expanded_spec = nil
		self.expanded_view:Hide()
		self.back_btn:Hide()

		for _, spec in ipairs(self.specs) do
			spec.panel:Show()
		end

		self.title:Show()
		if (self.title_icon_frame) then
			self.title_icon_frame:Show()
		end
		self:Refresh()
	end;

	-- ====================== REFRESH ==============================

	Refresh = function(self)
		local totalSpent = 0
		local totalAvailable = UnitLevel("player") - 9
		if (totalAvailable < 0) then totalAvailable = 0 end

		local isSimulated = (TalentSimulation and TalentSimulation:IsSimulated()) or false

		for _, spec in ipairs(self.specs) do
			local _, _, pointsSpent = GetTalentTabInfo(spec.tab_index)
			local displayPts = pointsSpent
			if (isSimulated and TalentSimulation) then
				displayPts = TalentSimulation:GetPlannedPointsInTab(spec.tab_index)
			end
			-- Branch name followed by its current point count
			spec.header:SetText(string.upper(spec.tab_name) .. " (" .. displayPts .. ")")
			if (displayPts == 0) then
				spec.header:SetTextColor(0.6, 0.6, 0.6)
			else
				spec.header:SetTextColor(1.0, 1.0, 1.0)
			end
			totalSpent = totalSpent + pointsSpent
		end

		local remaining = totalAvailable - totalSpent

		for _, spec in ipairs(self.specs) do
			local _, _, pointsSpent = GetTalentTabInfo(spec.tab_index)
			spec.grid:Refresh(pointsSpent, remaining)
		end

		-- Refresh expanded view's grid if visible
		if (self.expanded_spec and self.expanded_view and self.expanded_view.grid) then
			local _, _, pointsSpent = GetTalentTabInfo(self.specs[self.expanded_spec].tab_index)
			self.expanded_view.grid:Refresh(pointsSpent, remaining)
		end

		if (isSimulated and TalentSimulation) then
			local simRemaining = TALENT_POINTS_AT_60 - TalentSimulation:GetTotalPlannedPoints()
			if (simRemaining > 0) then
				self.points_text:SetText(MSB_L("SimModeLabel") .. " " .. MSB_L("TalentPointAvailable", "|cff00ffff" .. simRemaining .. "|r"))
			else
				self.points_text:SetText(MSB_L("SimModeLabel") .. " " .. MSB_L("NoTalentPointsAvailable"))
			end
		else
			if (remaining > 0) then
				self.points_text:SetText(MSB_L("TalentPointAvailable", "|cff00ff00" .. remaining .. "|r"))
			else
				self.points_text:SetText(MSB_L("NoTalentPointsAvailable"))
			end
		end

		self:UpdateSimControls()
	end;

	-- ================ SIMULATION CONTROLS ========================

	UpdateSimControls = function(self)
		if (not TalentSimulation) then return end

		local isSimulated = TalentSimulation:IsSimulated()

		-- Mode toggle reflects current mode
		if (isSimulated) then
			self.sim_mode_btn:SetText(MSB_L("SimModeSimulated"))
			self.sim_mode_btn:SetTextColor(0, 1, 1)
		else
			self.sim_mode_btn:SetText(MSB_L("SimModeLearned"))
			self.sim_mode_btn:SetTextColor(1, 1, 1)
		end

		-- Working plan name label
		self.plan_name_label:SetText(MSB_L("SimPlanLabel") .. " " .. TalentSimulation:GetPlanName())

		if (isSimulated) then
			self.sim_save_btn:Show()
			self.sim_list_btn:Show()
			self.sim_apply_btn:Show()
			self.sim_reset_btn:Show()
			self.plan_name_label:Show()
			if (TalentSimulation:IsApplying()) then
				self.sim_apply_btn:Disable()
			else
				self.sim_apply_btn:Enable()
			end
		else
			self.sim_save_btn:Hide()
			self.sim_list_btn:Hide()
			self.sim_apply_btn:Hide()
			self.sim_reset_btn:Hide()
			self.plan_name_label:Hide()
		end

		-- Per-branch reset buttons only relevant in simulation mode
		for _, spec in ipairs(self.specs) do
			if (spec.reset_btn) then
				if (isSimulated) then
					spec.reset_btn:Show()
				else
					spec.reset_btn:Hide()
				end
			end
		end

		-- Share / Import (top-left): simulation mode, overview only (avoid the back button)
		if (isSimulated and not self.expanded_spec) then
			self.sim_share_btn:Show()
			self.sim_import_btn:Show()
		else
			self.sim_share_btn:Hide()
			self.sim_import_btn:Hide()
		end
	end;

	-- ============== PLAN LIST DROPDOWN ===========================

	InitializePlanListDropdown = function(self, level)
		level = level or 1
		if (not TalentSimulation) then return end
		local tree = self

		if (level == 1) then
			local saved = TalentSimulation:GetSavedPlans()
			local count = table.getn(saved)
			if (count == 0) then
				local info = {}
				info.text = MSB_L("SimNoSavedPlans")
				info.notCheckable = 1
				info.disabled = 1
				UIDropDownMenu_AddButton(info, level)
				return
			end
			for i = 1, count do
				local info = {}
				info.text = saved[i].name .. "  (" .. (saved[i].points or 0) .. ")"
				info.hasArrow = 1
				info.notCheckable = 1
				info.value = i
				UIDropDownMenu_AddButton(info, level)
			end

		elseif (level == 2) then
			local i = UIDROPDOWNMENU_MENU_VALUE

			local info = {}
			info.text = MSB_L("SimLoadPlan")
			info.notCheckable = 1
			info.func = function()
				local name = TalentSimulation:GetSavedPlans()[i].name
				TalentSimulation:LoadSavedPlan(i)
				MSB_SimulationNotify(MSB_L("SimPlanLoaded", name))
				CloseDropDownMenus()
				tree:UpdateSimControls()
				tree:Refresh()
			end
			UIDropDownMenu_AddButton(info, level)

			info = {}
			info.text = MSB_L("SimRenamePlan")
			info.notCheckable = 1
			info.func = function()
				MSB_SimRenameSavedIndex = i
				StaticPopup_Show("MSB_SIM_RENAME_SAVED", TalentSimulation:GetSavedPlans()[i].name)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)

			info = {}
			info.text = MSB_L("SimDeletePlan")
			info.notCheckable = 1
			info.func = function()
				local name = TalentSimulation:GetSavedPlans()[i].name
				TalentSimulation:DeleteSavedPlan(i)
				MSB_SimulationNotify(MSB_L("SimPlanDeleted", name))
				CloseDropDownMenus()
				tree:UpdateSimControls()
				tree:Refresh()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end;
}

TalentTree = CTalentTree()

-- ============================================================
-- Hook default talent window: open our UI instead
-- ============================================================

local function MSB_HookTalentFrame()
	local orig = ToggleTalentFrame
	ToggleTalentFrame = function()
		if (TalentTree.enabled) then
			TalentTree:Toggle()
		else
			orig()
		end
	end
end

if (ToggleTalentFrame) then
	MSB_HookTalentFrame()
else
	local hookFrame = CreateFrame("Frame")
	hookFrame:RegisterEvent("ADDON_LOADED")
	hookFrame:SetScript("OnEvent", function()
		if (arg1 == "Blizzard_TalentUI" and ToggleTalentFrame) then
			MSB_HookTalentFrame()
			hookFrame:UnregisterEvent("ADDON_LOADED")
		end
	end)
end
