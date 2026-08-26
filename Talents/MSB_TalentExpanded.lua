--[[
	CExpandedSpecFrame: Expanded spec detail view.
	Shows spec info (name, description, key abilities) on the left
	and the full talent grid on the right.
	UI elements are created once and reused to avoid Frame leaks.
--]]

local TALENT_ASSETS = "Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\"

local function MSB_FontPath()
	return MSB_GetUIFont()
end

class "CExpandedSpecFrame"
{
	__init = function(self, parent, constants)
		self.parent_tree = nil -- set externally after creation
		self.constants = constants
		self.built = false
		self.ability_rows = {}
		self.grids_by_tab = {}
		self.grid = nil

		self.frame = CreateFrame("Frame", nil, parent)
		self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
		self.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
		self.frame:Hide()

		-- Right-click to go back
		self.frame:EnableMouse(true)
		self.frame:RegisterForDrag("LeftButton")
		self.frame:SetScript("OnDragStart", function()
			if (self.parent_tree) then
				self.parent_tree.frame:StartMoving()
			end
		end)
		self.frame:SetScript("OnDragStop", function()
			if (self.parent_tree) then
				self.parent_tree.frame:StopMovingOrSizing()
				local point, _, relPoint, x, y = self.parent_tree.frame:GetPoint()
				ModernSpellBook_DB.talentPosition = { point = point, relPoint = relPoint, x = x, y = y }
			end
		end)
		self.frame:SetScript("OnMouseUp", function()
			if (arg1 == "RightButton" and self.parent_tree) then
				self.parent_tree:CollapseSpec()
			end
		end)
	end;

	EnsureBuilt = function(self)
		if (self.built) then return end
		self.built = true

		local c = self.constants
		local expW = c.TOTAL_WIDTH - 16
		local expH = c.TOTAL_HEIGHT - 16
		local fontPath = MSB_FontPath()

		self.bgLeft = self.frame:CreateTexture(nil, "ARTWORK")
		self.bgLeft:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
		self.bgLeft:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
		self.bgLeft:SetWidth(expW / 2)

		self.bgRight = self.frame:CreateTexture(nil, "ARTWORK")
		self.bgRight:SetPoint("TOPLEFT", self.bgLeft, "TOPRIGHT", 0, 0)
		self.bgRight:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)

		local gridW = c.GRID_COLS_DEFAULT * c.CELL_SIZE + 20
		local leftColW = c.EXPANDED_HORIZONTAL_PADDING * 2

		self.leftCol = CreateFrame("Frame", nil, self.frame)
		self.leftCol:SetWidth(leftColW)
		self.leftCol:SetHeight(expH)
		self.leftCol:SetPoint("CENTER", self.frame, "LEFT", c.EXPANDED_HORIZONTAL_PADDING, 0)

		self.specName = self.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.specName:SetFont(fontPath, 22)
		self.specName:SetTextColor(1, 1, 1)
		self.specName:SetJustifyH("CENTER")

		self.specDesc = self.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.specDesc:SetPoint("TOP", self.specName, "BOTTOM", 0, -30)
		self.specDesc:SetFont(fontPath, 16)
		self.specDesc:SetTextColor(1, 1, 1)
		self.specDesc:SetJustifyH("CENTER")
		self.specDesc:SetWidth(400)
		if (self.specDesc.SetWordWrap) then self.specDesc:SetWordWrap(true) end

		local gridH = c.GRID_ROWS * c.CELL_SIZE + 20
		self.gridContainer = CreateFrame("Frame", nil, self.frame)
		self.gridContainer:SetWidth(gridW)
		self.gridContainer:SetHeight(gridH)
		self.gridContainer:SetPoint("CENTER", self.frame, "RIGHT", -c.EXPANDED_HORIZONTAL_PADDING, 0)

		self.abilitiesHeader = self.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.abilitiesHeader:SetPoint("TOP", self.specDesc, "BOTTOM", 0, -30)
		self.abilitiesHeader:SetFont(fontPath, 18)
		self.abilitiesHeader:SetText(MSB_L("TalentKeyAbilities"))
		self.abilitiesHeader:SetTextColor(1, 1, 1)
		self.abilitiesHeader:SetJustifyH("CENTER")

		-- Pre-create up to 3 ability showcase rows
		for i = 1, 3 do
			local row = CreateFrame("Frame", nil, self.leftCol)
			row:SetWidth(200)
			row:SetHeight(c.CELL_SIZE)
			row:Hide()

			row.lockText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.lockText:SetFont(fontPath, 16)
			row.lockText:SetTextColor(190/255, 136/255, 121/255)
			row.lockText:SetWidth(40)
			row.lockText:SetJustifyH("RIGHT")
			row.lockText:SetPoint("LEFT", row, "LEFT", -130, 0)

			row.lockTex = row:CreateTexture(nil, "OVERLAY")
			row.lockTex:SetWidth(138)
			row.lockTex:SetHeight(16)
			row.lockTex:SetTexture(TALENT_ASSETS .. "tier-lock")
			row.lockTex:SetPoint("LEFT", row.lockText, "RIGHT", 6, 0)

			row.icon = CTalentIcon(row, c.CELL_SIZE)
			row.icon.frame:RegisterForClicks()
			row.icon.frame:SetScript("OnClick", nil)

			row.abilName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.abilName:SetPoint("LEFT", row.icon.frame, "RIGHT", 8, 0)
			row.abilName:SetFont(fontPath, 12)
			row.abilName:SetTextColor(1, 1, 1)

			self.ability_rows[i] = row
		end

		self.pointsTitle = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.pointsTitle:SetFont(fontPath, 22)
		self.pointsTitle:SetTextColor(1, 1, 1)
		self.pointsTitle:SetJustifyH("CENTER")
	end;

	Show = function(self, spec, specIndex, haze_colors)
		self:EnsureBuilt()

		local c = self.constants
		local _, englishClass = UnitClass("player")

		-- Update backgrounds
		local bgBase = "Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\Backgrounds\\talentbg-" .. string.lower(englishClass) .. "-" .. specIndex
		self.bgLeft:SetTexture(bgBase .. "-left")
		self.bgLeft:Show()
		self.bgRight:SetTexture(bgBase .. "-right")
		self.bgRight:Show()

		-- Points used in this branch (simulated when in sim mode)
		local _, _, branchPoints = GetTalentTabInfo(spec.tab_index)
		local pointsSpent = branchPoints
		if (TalentSimulation and TalentSimulation:IsSimulated()) then
			branchPoints = TalentSimulation:GetPlannedPointsInTab(spec.tab_index)
			pointsSpent = branchPoints
		end

		self.specName:SetText(string.upper(spec.tab_name) .. " (" .. branchPoints .. ")")
		self.specName:Show()

		local descText = MSB_GetSpecDescription(englishClass, specIndex)
		self.specDesc:SetText(descText)
		self.specDesc:Show()

		-- Create or reuse talent grid (one per tab — never recreate)
		local hazeColor = (haze_colors and haze_colors[specIndex]) or {0.2, 0.2, 0.4}
		if (self.grid and self.grid ~= self.grids_by_tab[spec.tab_index]) then
			self.grid:Hide()
		end
		if (not self.grids_by_tab[spec.tab_index]) then
			self.grids_by_tab[spec.tab_index] = CTalentGrid(self.gridContainer, spec.tab_index, c.CELL_SIZE, 10, 10, hazeColor, c.GRID_ROWS)
		end
		self.grid = self.grids_by_tab[spec.tab_index]
		self.grid:Show()
		if (self.grid.lines_frame) then
			self.grid.lines_frame:Show()
		end
		for _, talent in ipairs(self.grid.icons) do
			talent.frame:Show()
		end

		self.abilitiesHeader:Show()

		-- Select key abilities: last exceptional from rows 3, 5, 7
		local hasOutgoing = {}
		local hasIncoming = {}
		for _, talent in ipairs(self.grid.icons) do
			if (talent.prereq_tier) then
				hasIncoming[talent.tier .. "," .. talent.column] = true
				hasOutgoing[talent.prereq_tier .. "," .. talent.prereq_column] = true
			end
		end
		local showcase = {}
		local showcaseRows = {3, 5, 7}
		for _, targetRow in ipairs(showcaseRows) do
			local pick = nil
			local pickScore = 0
			for _, talent in ipairs(self.grid.exceptional_talents) do
				if (talent.tier == targetRow) then
					local key = talent.tier .. "," .. talent.column
					local score = 1
					if (hasIncoming[key]) then score = 2 end
					if (hasOutgoing[key]) then score = 3 end
					if (score > pickScore) then
						pick = talent
						pickScore = score
					end
				end
			end
			if (not pick) then
				local bestRank = 999
				for _, talent in ipairs(self.grid.icons) do
					if (talent.tier == targetRow and talent.max_rank < bestRank) then
						bestRank = talent.max_rank
						pick = talent
					end
				end
			end
			if (pick) then
				table.insert(showcase, pick)
			end
		end

		-- Hide all ability rows first
		for i = 1, 3 do
			self.ability_rows[i]:Hide()
		end

		for i, talent in ipairs(showcase) do
			local row = self.ability_rows[i]
			if (row) then
				row:ClearAllPoints()
				row:SetPoint("TOP", self.abilitiesHeader, "BOTTOM", 0, -(i - 1) * (c.CELL_SIZE + 5) - 20)

				local tierReq = (talent.tier - 1) * 5
				row.lockText:SetText(tierReq - pointsSpent)
				if (pointsSpent >= tierReq) then
					row.lockText:SetAlpha(0)
					row.lockTex:SetAlpha(0)
				else
					row.lockText:SetAlpha(1)
					row.lockTex:SetAlpha(1)
				end

				row.icon:SetTalentData(talent.talent_tab, talent.talent_index)
				if (talent.is_exceptional and not row.icon.is_exceptional) then
					row.icon.is_exceptional = true
					row.icon:ApplyFrameShape()
				end
				if (row.icon.curr_rank >= row.icon.max_rank) then
					if (row.icon.is_exceptional) then
						row.icon.border:SetTexture(TALENT_ASSETS .. "talent-frame-square-gold")
					else
						row.icon.border:SetTexture(TALENT_ASSETS .. "talent-frame-circle-gold")
					end
				end
				row.icon.frame:ClearAllPoints()
				row.icon.frame:SetPoint("LEFT", row.lockTex, "RIGHT", -40, 0)
				row.icon:SetHazeColor(hazeColor[1], hazeColor[2], hazeColor[3])
				row.icon.haze_tex:SetAlpha(1.0)

				row.abilName:SetText(talent.talent_name)
				row:Show()
			end
		end

		if (branchPoints > 0) then
			self.pointsTitle:SetText(MSB_L("TalentPointsInvested", "|cff00ff00" .. branchPoints .. "|r"))
		else
			self.pointsTitle:SetText(MSB_L("TalentPointsInvested", "|cff808080" .. branchPoints .. "|r"))
		end

		-- Refresh grid state
		local totalAvailable = UnitLevel("player") - 9
		if (totalAvailable < 0) then totalAvailable = 0 end
		local totalSpent = 0
		for _, s in ipairs(self.parent_tree.specs) do
			local _, _, sp = GetTalentTabInfo(s.tab_index)
			totalSpent = totalSpent + sp
		end
		local remaining = totalAvailable - totalSpent
		self.grid:Refresh(pointsSpent, remaining)

		-- Align titles
		self.pointsTitle:ClearAllPoints()
		self.pointsTitle:SetPoint("TOP", self.gridContainer, "TOP", 0, 30)
		self.specName:ClearAllPoints()
		self.specName:SetPoint("TOP", self.pointsTitle, "TOP", 0, 0)
		self.specName:SetPoint("LEFT", self.leftCol, "LEFT", 0, 0)
		self.specName:SetPoint("RIGHT", self.leftCol, "RIGHT", 0, 0)

		self.frame:Show()
	end;

	Hide = function(self)
		if (self.grid) then
			self.grid:Hide()
			-- Keep grid reference for reuse (do not nil)
		end
		self.frame:Hide()
	end;
}
