--[[
	CTalentGrid: A self-contained talent icon grid for one spec tab.
	Creates its own CTalentIcon instances and CTalentConnection arrows.
	Can be instantiated multiple times (overview panels, expanded view, etc.)
--]]

local TALENT_ASSETS = "Interface\\AddOns\\ModernSpellBook\\Assets\\Talents\\"
local TALENT_POINTS_AT_60 = 51

-- Grid line alpha per class-spec: [englishClass][specIndex]
local GRID_LINE_ALPHA = {
	WARRIOR = {0.4, 0.4, 0.4},
	PALADIN = {0.4, 0.5, 0.4},
	HUNTER  = {0.6, 0.4, 0.4},
	ROGUE   = {0.4, 0.4, 0.7},
	PRIEST  = {0.4, 0.4, 0.5},
	SHAMAN  = {0.4, 0.6, 0.4},
	MAGE    = {0.4, 0.4, 0.7},
	WARLOCK = {0.5, 0.4, 0.4},
	DRUID   = {0.7, 0.4, 0.4},
}

class "CTalentGrid"
{
	__init = function(self, parent, tab_index, cell_size, offset_x, offset_y, haze_color, grid_rows)
		self.parent = parent
		self.tab_index = tab_index
		self.cell_size = cell_size
		self.offset_x = offset_x
		self.offset_y = offset_y
		self.grid_rows = grid_rows or 7

		-- Create talent icons
		self.icons = {}
		self.exceptional_talents = {}
		local numTalents = GetNumTalents(tab_index)

		for i = 1, numTalents do
			local name = GetTalentInfo(tab_index, i)
			if (name) then
				local talent = CTalentIcon(parent, cell_size)
				talent:SetTalentData(tab_index, i)
				talent:SetGridPosition(
					talent.tier - 1,
					talent.column - 1,
					offset_x, offset_y)
				if (haze_color) then
					talent:SetHazeColor(haze_color[1], haze_color[2], haze_color[3])
				end
				table.insert(self.icons, talent)
				if (talent.is_exceptional) then
					table.insert(self.exceptional_talents, talent)
				end
			end
		end

		-- Ensure rows 3, 5, 7 have at least one exceptional talent
		-- If none from API, promote a rank-1 talent in that row
		local keyRows = {3, 5, 7}
		for _, row in ipairs(keyRows) do
			local hasExc = false
			for _, talent in ipairs(self.icons) do
				if (talent.tier == row and talent.is_exceptional) then
					hasExc = true
					break
				end
			end
			if (not hasExc) then
				for _, talent in ipairs(self.icons) do
					if (talent.tier == row and talent.max_rank == 1) then
						talent.is_exceptional = true
						talent:ApplyFrameShape()
						table.insert(self.exceptional_talents, talent)
						break
					end
				end
			end
		end

		-- Mark bottom-most talent as final
		local maxTier = 0
		for _, talent in ipairs(self.icons) do
			if (talent.tier > maxTier) then maxTier = talent.tier end
		end
		for _, talent in ipairs(self.icons) do
			if (talent.tier == maxTier) then
				talent.is_final = true
				talent:ApplyFrameShape()
			end
		end

		-- Build grid lines between adjacent talent cells
		self.grid_lines = {}
		self.line_pool = {}
		self.lines_frame = CreateFrame("Frame", nil, parent)
		self.lines_frame:SetAllPoints(parent)
		self.lines_frame:SetFrameLevel(parent:GetFrameLevel())

		-- Determine line alpha for this class-spec
		local _, englishClass = UnitClass("player")
		local classAlphas = GRID_LINE_ALPHA[englishClass]
		local lineAlpha = (classAlphas and classAlphas[tab_index]) or 0.2

		self.haze_color = haze_color
		self.line_alpha = lineAlpha

		self:RebuildGridLines()

		-- Build connections
		self.connections = {}
		self:RebuildConnections()

		-- Tier lock
		self.tier_lock = CreateFrame("Frame", nil, parent)
		self.tier_lock:SetWidth(138)
		self.tier_lock:SetHeight(16)
		self.tier_lock:SetFrameLevel(parent:GetFrameLevel() + 5)
		local tierLockTex = self.tier_lock:CreateTexture(nil, "OVERLAY")
		tierLockTex:SetAllPoints(self.tier_lock)
		tierLockTex:SetTexture(TALENT_ASSETS .. "tier-lock")
		self.tier_lock:Hide()

		self.tier_lock_text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.tier_lock_text:SetFont(MSB_GetUIFont(), 16)
		self.tier_lock_text:SetTextColor(190/255, 136/255, 121/255)
		self.tier_lock_text:SetPoint("RIGHT", self.tier_lock, "LEFT", -2, 0)
		self.tier_lock_text:Hide()
	end;

	-- Rebuild only grid lines (reuse textures from pool — no Frame leak)
	RebuildGridLines = function(self)
		local cell_size = self.cell_size
		local offset_x = self.offset_x
		local offset_y = self.offset_y
		local parent = self.parent
		local haze_color = self.haze_color
		local lineAlpha = self.line_alpha

		-- Hide pooled textures
		for _, tex in ipairs(self.line_pool) do
			tex:Hide()
		end
		self.grid_lines = {}

		local cellMap = {}
		for _, talent in ipairs(self.icons) do
			cellMap[(talent.tier) .. "," .. (talent.column)] = true
		end

		local gl = (ModernSpellBook_DB and ModernSpellBook_DB.talentGridLines)
			or { vertical = true, diagonal = true, horizontal = true }

		local edges = {}
		for _, talent in ipairs(self.icons) do
			local t, c = talent.tier, talent.column
			local neighbors = {}
			if (gl.vertical) then
				table.insert(neighbors, {t + 1, c, "v"})
			end
			if (gl.diagonal) then
				table.insert(neighbors, {t + 1, c - 1, "dl"})
				table.insert(neighbors, {t + 1, c + 1, "dr"})
			end
			if (gl.horizontal) then
				table.insert(neighbors, {t, c + 1, "h"})
			end
			for _, nb in ipairs(neighbors) do
				local nt, nc, dir = nb[1], nb[2], nb[3]
				if (cellMap[nt .. "," .. nc]) then
					table.insert(edges, {t = t, c = c, nt = nt, nc = nc, dir = dir})
				end
			end
		end

		local skipEdge = {}
		for i = 1, table.getn(edges) do
			for j = i + 1, table.getn(edges) do
				local a, b = edges[i], edges[j]
				if (a.t == b.t and (a.dir == "dl" or a.dir == "dr") and (b.dir == "dl" or b.dir == "dr")) then
					local a_min = math.min(a.c, a.nc)
					local a_max = math.max(a.c, a.nc)
					local b_min = math.min(b.c, b.nc)
					local b_max = math.max(b.c, b.nc)
					if (a.dir ~= b.dir and a_min < b_max and b_min < a_max) then
						local a_dist = math.abs(a.nc - 2)
						local b_dist = math.abs(b.nc - 2)
						if (a_dist <= b_dist) then
							skipEdge[j] = true
						else
							skipEdge[i] = true
						end
					end
				end
			end
		end

		if (self.lines_frame) then
			self.lines_frame:Show()
		end

		local poolIndex = 0
		local function acquireLine()
			poolIndex = poolIndex + 1
			local line = self.line_pool[poolIndex]
			if (not line) then
				line = self.lines_frame:CreateTexture(nil, "OVERLAY")
				self.line_pool[poolIndex] = line
			end
			line:SetBlendMode("ADD")
			line:SetAlpha(lineAlpha)
			if (haze_color) then
				line:SetVertexColor(haze_color[1], haze_color[2], haze_color[3])
			end
			line:Show()
			return line
		end

		for i, edge in ipairs(edges) do
			if (not skipEdge[i]) then
				local line = acquireLine()
				local cx = offset_x + (edge.c - 1) * cell_size + cell_size / 2
				local cy = -(offset_y + (edge.t - 1) * cell_size + cell_size / 2)
				line:ClearAllPoints()
				if (edge.dir == "v") then
					line:SetTexture(TALENT_ASSETS .. "line-v")
					line:SetTexCoord(0, 1, 0, 1)
					line:SetWidth(8)
					line:SetHeight(cell_size)
					line:SetPoint("TOP", parent, "TOPLEFT", cx, cy)
				elseif (edge.dir == "dl") then
					local ncx = offset_x + (edge.nc - 1) * cell_size + cell_size / 2
					local ncy = -(offset_y + (edge.nt - 1) * cell_size + cell_size / 2)
					line:SetTexture(TALENT_ASSETS .. "line-d")
					line:SetWidth(36)
					line:SetHeight(36)
					line:SetTexCoord(1, 0, 0, 1)
					line:SetPoint("CENTER", parent, "TOPLEFT", (cx + ncx) / 2, (cy + ncy) / 2)
				elseif (edge.dir == "dr") then
					local ncx = offset_x + (edge.nc - 1) * cell_size + cell_size / 2
					local ncy = -(offset_y + (edge.nt - 1) * cell_size + cell_size / 2)
					line:SetTexture(TALENT_ASSETS .. "line-d")
					line:SetWidth(36)
					line:SetHeight(36)
					line:SetTexCoord(0, 1, 0, 1)
					line:SetPoint("CENTER", parent, "TOPLEFT", (cx + ncx) / 2, (cy + ncy) / 2)
				elseif (edge.dir == "h") then
					line:SetTexture(TALENT_ASSETS .. "line-h")
					line:SetTexCoord(0, 1, 0, 1)
					line:SetWidth(cell_size)
					line:SetHeight(8)
					line:SetPoint("LEFT", parent, "TOPLEFT", cx, cy)
				end
				table.insert(self.grid_lines, {
					tex = line,
					src_tier = edge.t,
					src_col = edge.c,
					dst_tier = edge.nt,
					dst_col = edge.nc,
				})
			end
		end
	end;

	RebuildConnections = function(self)
		-- Clear old
		for _, connData in ipairs(self.connections) do
			connData.connection:Clear()
		end

		-- Build occupied map
		local occupied = {}
		for _, talent in ipairs(self.icons) do
			occupied[(talent.tier - 1) .. "," .. (talent.column - 1)] = true
		end

		-- Sort edges: straight first, then L-shapes
		local edges = {}
		for _, talent in ipairs(self.icons) do
			if (talent.prereq_tier and talent.prereq_column) then
				table.insert(edges, talent)
			end
		end
		table.sort(edges, function(a, b)
			local a_straight = (a.prereq_column == a.column) and 0 or 1
			local b_straight = (b.prereq_column == b.column) and 0 or 1
			return a_straight < b_straight
		end)

		self.connections = {}
		for _, talent in ipairs(edges) do
			local conn = CTalentConnection(self.parent)
			conn:BuildRoute(
				talent.prereq_tier - 1,
				talent.prereq_column - 1,
				talent.tier - 1,
				talent.column - 1,
				self.cell_size,
				self.offset_x,
				self.offset_y,
				occupied)
			if (conn.routed_cells) then
				for _, cell in ipairs(conn.routed_cells) do
					occupied[cell.r .. "," .. cell.c] = true
				end
			end
			table.insert(self.connections, {
				connection = conn,
				prereq_tier = talent.prereq_tier,
				prereq_column = talent.prereq_column,
				target = talent,
			})
		end
	end;

	Refresh = function(self, pointsSpent, remaining)
		-- Set simulation mode on all icons
		local simMode = (TalentSimulation and TalentSimulation:IsSimulated()) or false
		for _, talent in ipairs(self.icons) do
			talent:SetSimulationMode(simMode)
		end

		-- Use simulated points if in simulation mode
		local effectivePointsSpent = pointsSpent
		local effectiveRemaining = remaining
		if (simMode and TalentSimulation) then
			effectivePointsSpent = TalentSimulation:GetPlannedPointsInTab(self.tab_index)
			effectiveRemaining = TALENT_POINTS_AT_60 - TalentSimulation:GetTotalPlannedPoints()
		end

		-- Prereq checker
		local function checkPrereq(tier, column)
			for _, talent in ipairs(self.icons) do
				if (talent.tier == tier and talent.column == column) then
					return talent.curr_rank == talent.max_rank
				end
			end
			return false
		end

		for _, talent in ipairs(self.icons) do
			talent:RefreshRank()
			talent:UpdateVisualState(effectivePointsSpent, checkPrereq, effectiveRemaining)
		end

		-- Arrow states
		for _, connData in ipairs(self.connections) do
			local prereq_maxed = checkPrereq(connData.prereq_tier, connData.prereq_column)
			local target_state = connData.target.visual_state
			local unlocked = prereq_maxed and (target_state ~= "locked_in_locked_tier" and target_state ~= "locked_in_unlocked_tier")
			connData.connection:UpdateState(unlocked)
		end

		-- Grid line coloring + visibility
		local gl = (ModernSpellBook_DB and ModernSpellBook_DB.talentGridLines) or {}
		local coloring = gl.coloring or "unlocked"
		local visibility = gl.visibility or "unlocked"

		-- Build rank lookup: tier,col -> curr_rank
		local rankMap = {}
		for _, talent in ipairs(self.icons) do
			rankMap[talent.tier .. "," .. talent.column] = talent.curr_rank
		end

		for _, lineData in ipairs(self.grid_lines) do
			local srcRank = rankMap[lineData.src_tier .. "," .. lineData.src_col] or 0
			local dstRank = rankMap[lineData.dst_tier .. "," .. lineData.dst_col] or 0
			local bothInvested = (srcRank > 0 and dstRank > 0)

			-- Visibility
			if (visibility == "unlocked" and not bothInvested) then
				lineData.tex:SetAlpha(0)
			else
				lineData.tex:SetAlpha(self.line_alpha)
			end

			-- Coloring
			if (coloring == "never") then
				lineData.tex:SetVertexColor(0.5, 0.5, 0.5)
			elseif (coloring == "unlocked") then
				if (bothInvested and self.haze_color) then
					lineData.tex:SetVertexColor(self.haze_color[1], self.haze_color[2], self.haze_color[3])
				else
					lineData.tex:SetVertexColor(0.5, 0.5, 0.5)
				end
			else
				if (self.haze_color) then
					lineData.tex:SetVertexColor(self.haze_color[1], self.haze_color[2], self.haze_color[3])
				end
			end
		end

		-- Tier lock (use simulated points when in sim mode)
		local firstLockedTier = nil
		local is_max_no_points = (UnitLevel("player") >= 60 and effectiveRemaining <= 0)
		if (not is_max_no_points) then
			for tier = 1, self.grid_rows do
				if (effectivePointsSpent < (tier - 1) * 5) then
					firstLockedTier = tier
					break
				end
			end
		end
		if (firstLockedTier) then
			local pointsNeeded = (firstLockedTier - 1) * 5 - effectivePointsSpent
			self.tier_lock_text:ClearAllPoints()
			self.tier_lock_text:SetPoint("LEFT", self.parent, "TOPLEFT",
				self.offset_x - 90,
				-(self.offset_y + (firstLockedTier - 1) * self.cell_size + self.cell_size / 2))
			self.tier_lock_text:SetText(pointsNeeded)
			self.tier_lock_text:Show()
			self.tier_lock:ClearAllPoints()
			self.tier_lock:SetPoint("LEFT", self.tier_lock_text, "RIGHT", 5, 0)
			self.tier_lock:Show()
		else
			self.tier_lock:Hide()
			self.tier_lock_text:Hide()
		end
	end;

	Hide = function(self)
		for _, talent in ipairs(self.icons) do
			talent.frame:Hide()
		end
		for _, connData in ipairs(self.connections) do
			connData.connection:Clear()
		end
		if (self.lines_frame) then
			self.lines_frame:Hide()
		end
		self.tier_lock:Hide()
		self.tier_lock_text:Hide()
	end;

	Show = function(self)
		for _, talent in ipairs(self.icons) do
			talent.frame:Show()
		end
	end;
}
