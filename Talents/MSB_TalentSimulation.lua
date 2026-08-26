--[[
	MSB_TalentSimulation: Talent plan management for simulation mode.
	Stores multiple named talent plans per character.
	Allows simulating talent allocation before spending actual points.
--]]

local MAX_PLAN_COUNT = 20
local TALENT_POINTS_AT_60 = 51

class "CTalentSimulation"
{
	__init = function(self)
		self.playerKey = nil
		self.mode = "learned"  -- "learned" or "simulated"
		self.applyState = nil  -- active apply state or nil
	end;

	-- =================== INITIALIZATION ==========================

	Load = function(self)
		self.playerKey = UnitName("player") .. " of " .. GetRealmName()

		if (not ModernSpellBook_DB.talentPlans) then
			ModernSpellBook_DB.talentPlans = {}
		end
		local plans = ModernSpellBook_DB.talentPlans

		local playerData = plans[self.playerKey]
		-- Migrate / reset old (20-slot) shape to the new working+saved model
		if (not playerData or playerData.selectedPlan ~= nil or not playerData.working) then
			plans[self.playerKey] = { working = nil, saved = {} }
			playerData = plans[self.playerKey]
		end
		if (not playerData.saved) then
			playerData.saved = {}
		end
		if (not playerData.working) then
			playerData.working = self:BlankPlan(nil)
		end
		self:EnsurePlanShape(playerData.working)
	end;

	Save = function(self)
		-- DB is auto-saved as part of ModernSpellBook_DB
	end;

	-- =================== PLAN HELPERS ============================

	BlankPlan = function(self, name)
		local plan = { name = name, points = 0 }
		for t = 1, 3 do
			plan[t] = { points = 0 }
		end
		return plan
	end;

	EnsurePlanShape = function(self, plan)
		if (not plan.points) then plan.points = 0 end
		for t = 1, 3 do
			if (not plan[t]) then plan[t] = { points = 0 } end
			if (not plan[t].points) then plan[t].points = 0 end
		end
		return plan
	end;

	-- Deep copy of a plan's allocation (points + per-tab ranks)
	CopyPlan = function(self, src, name)
		local dst = { name = name, points = src.points or 0 }
		for t = 1, 3 do
			local srcTab = src[t] or { points = 0 }
			local dstTab = { points = srcTab.points or 0 }
			for k, v in pairs(srcTab) do
				if (k ~= "points") then dstTab[k] = v end
			end
			dst[t] = dstTab
		end
		return dst
	end;

	-- =================== WORKING PLAN ============================

	GetPlan = function(self)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData) then return nil end
		return playerData.working
	end;

	NewWorkingPlan = function(self)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData) then return end
		playerData.working = self:BlankPlan(nil)
	end;

	GetPlanName = function(self)
		local plan = self:GetPlan()
		if (plan and plan.name and plan.name ~= "") then
			return plan.name
		end
		return MSB_L("SimNewPlanName")
	end;

	SetPlanName = function(self, name)
		local plan = self:GetPlan()
		if (plan) then
			plan.name = name
		end
	end;

	-- =================== SAVED LIBRARY ===========================

	GetSavedPlans = function(self)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		return (playerData and playerData.saved) or {}
	end;

	SaveWorkingPlan = function(self, name)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData or not name or name == "") then return end
		local working = playerData.working
		working.name = name
		-- Update an existing saved plan with the same name, else append
		for i = 1, table.getn(playerData.saved) do
			if (playerData.saved[i].name == name) then
				playerData.saved[i] = self:CopyPlan(working, name)
				return
			end
		end
		if (table.getn(playerData.saved) >= MAX_PLAN_COUNT) then
			MSB_SimulationNotify(MSB_L("SimPlanFull"))
			return
		end
		table.insert(playerData.saved, self:CopyPlan(working, name))
	end;

	LoadSavedPlan = function(self, index)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData or not playerData.saved[index]) then return end
		playerData.working = self:CopyPlan(playerData.saved[index], playerData.saved[index].name)
	end;

	DeleteSavedPlan = function(self, index)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData or not playerData.saved[index]) then return end
		table.remove(playerData.saved, index)
	end;

	RenameSavedPlan = function(self, index, name)
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData or not playerData.saved[index] or not name or name == "") then return end
		playerData.saved[index].name = name
	end;

	-- =================== SHARE / IMPORT ==========================
	-- String format: "MSB1-<ENGLISHCLASS>-<tab1>-<tab2>-<tab3>"
	-- where each <tabN> is one digit (rank 0-9) per talent in GetTalentInfo order.

	ExportWorkingPlan = function(self)
		local plan = self:GetPlan()
		if (not plan) then return "" end
		local _, englishClass = UnitClass("player")
		local parts = { "MSB1", englishClass }
		for tab = 1, 3 do
			local s = ""
			local n = GetNumTalents(tab)
			for i = 1, n do
				local rank = (plan[tab] and plan[tab][i]) or 0
				if (rank > 9) then rank = 9 end
				s = s .. rank
			end
			table.insert(parts, s)
		end
		return table.concat(parts, "-")
	end;

	ImportPlan = function(self, str)
		if (not str or str == "") then return false, "format" end
		-- Trim surrounding whitespace
		str = string.gsub(str, "^%s+", "")
		str = string.gsub(str, "%s+$", "")

		-- Split on "-"
		local parts = {}
		local start = 1
		while (true) do
			local s, e = string.find(str, "-", start, true)
			if (not s) then
				table.insert(parts, string.sub(str, start))
				break
			end
			table.insert(parts, string.sub(str, start, s - 1))
			start = e + 1
		end

		if (parts[1] ~= "MSB1") then return false, "format" end
		local _, englishClass = UnitClass("player")
		if (parts[2] ~= englishClass) then return false, "class" end

		local tabStrings = { parts[3] or "", parts[4] or "", parts[5] or "" }
		local newPlan = self:BlankPlan(nil)
		for tab = 1, 3 do
			local s = tabStrings[tab]
			local n = GetNumTalents(tab)
			for i = 1, n do
				local ch = string.sub(s, i, i)
				local rank = tonumber(ch) or 0
				local _, _, tier, _, _, maxRank = GetTalentInfo(tab, i)
				if (maxRank and rank > maxRank) then rank = maxRank end
				if (rank > 0) then
					newPlan[tab][i] = rank
					newPlan[tab].points = newPlan[tab].points + rank
					newPlan.points = newPlan.points + rank
				end
			end
		end

		-- Cap total points and drop illegal ranks (tier / prereq)
		if (newPlan.points > TALENT_POINTS_AT_60) then
			return false, "format"
		end
		-- Temporarily install as working so MeetsPlannedPrereqs / IsTierUnlocked work
		local playerData = ModernSpellBook_DB.talentPlans[self.playerKey]
		if (not playerData) then return false, "format" end
		local prevWorking = playerData.working
		playerData.working = newPlan
		for tab = 1, 3 do
			for i = 1, GetNumTalents(tab) do
				local rank = newPlan[tab][i] or 0
				if (rank > 0) then
					local _, _, tier = GetTalentInfo(tab, i)
					-- Check as if this talent had (rank-1) already for prereq of itself at first point
					-- Simpler: require tier unlocked by points excluding this talent's own contribution beyond first
					local pointsWithout = newPlan[tab].points - rank
					if (pointsWithout < (tier - 1) * 5) then
						playerData.working = prevWorking
						return false, "format"
					end
					-- Prereq must be at max in the imported plan
					if (not self:MeetsPlannedPrereqs(tab, i)) then
						playerData.working = prevWorking
						return false, "format"
					end
				end
			end
		end

		self.mode = "simulated"
		return true
	end;

	-- =================== MODE ====================================

	IsSimulated = function(self)
		return self.mode == "simulated"
	end;

	SetMode = function(self, mode)
		self.mode = mode
	end;

	ToggleMode = function(self)
		if (self.mode == "learned") then
			self.mode = "simulated"
			-- Keep existing working plan if it has points; otherwise start fresh
			local plan = self:GetPlan()
			if (not plan or (plan.points or 0) == 0) then
				self:NewWorkingPlan()
			end
		else
			self.mode = "learned"
		end
	end;

	-- =================== PLAN QUERIES ============================

	GetPlannedRank = function(self, tabID, talentID)
		local plan = self:GetPlan()
		if (not plan or not plan[tabID]) then return 0 end
		return plan[tabID][talentID] or 0
	end;

	GetPlannedPointsInTab = function(self, tabID)
		local plan = self:GetPlan()
		if (not plan or not plan[tabID]) then return 0 end
		return plan[tabID].points or 0
	end;

	GetTotalPlannedPoints = function(self)
		local plan = self:GetPlan()
		if (not plan) then return 0 end
		return plan.points or 0
	end;

	IsTierUnlocked = function(self, tier, tabID)
		local pointsInTab = self:GetPlannedPointsInTab(tabID)
		return pointsInTab >= (tier - 1) * 5
	end;

	-- =================== PLAN MODIFICATION =======================

	-- Returns true if all prereqs of talentID in tabID are at max planned rank
	MeetsPlannedPrereqs = function(self, tabID, talentID)
		if (not GetTalentPrereqs) then return true end
		local ok, pTier, pCol = pcall(GetTalentPrereqs, tabID, talentID)
		if (not ok or not pTier or pTier <= 0) then return true end
		-- Find the prereq talent by tier/column and require max planned rank
		for i = 1, GetNumTalents(tabID) do
			local _, _, tier, column, _, maxRank = GetTalentInfo(tabID, i)
			if (tier == pTier and column == pCol) then
				local planned = self:GetPlannedRank(tabID, i)
				if (planned < (maxRank or 1)) then
					return false
				end
				return true
			end
		end
		return true
	end;

	-- Returns true if removing a point from talentID would leave a dependent
	-- talent with points while this talent is no longer at max rank
	CanUnplanTalent = function(self, tabID, talentID)
		local _, _, tier, column, _, maxRank = GetTalentInfo(tabID, talentID)
		local currentPlanned = self:GetPlannedRank(tabID, talentID)
		if (currentPlanned <= 0) then return false end
		local newRank = currentPlanned - 1
		-- If still at max after unplan, dependents are fine
		if (newRank >= (maxRank or 1)) then return true end

		if (not GetTalentPrereqs) then return true end
		for i = 1, GetNumTalents(tabID) do
			if (i ~= talentID and self:GetPlannedRank(tabID, i) > 0) then
				local ok, pTier, pCol = pcall(GetTalentPrereqs, tabID, i)
				if (ok and pTier and pTier == tier and pCol == column) then
					return false
				end
			end
		end
		return true
	end;

	-- Learned-mode prereq check for Apply (uses real ranks)
	MeetsLearnedPrereqs = function(self, tabID, talentID)
		if (not GetTalentPrereqs) then return true end
		local ok, pTier, pCol = pcall(GetTalentPrereqs, tabID, talentID)
		if (not ok or not pTier or pTier <= 0) then return true end
		for i = 1, GetNumTalents(tabID) do
			local _, _, tier, column, currRank, maxRank = GetTalentInfo(tabID, i)
			if (tier == pTier and column == pCol) then
				return currRank >= (maxRank or 1)
			end
		end
		return true
	end;

	PlanTalent = function(self, tabID, talentID)
		local _, _, tier, _, _, maxRank = GetTalentInfo(tabID, talentID)
		local plan = self:GetPlan()
		if (not plan) then return end
		self:EnsurePlanShape(plan)
		local tabPlan = plan[tabID]
		local currentPlanned = tabPlan[talentID] or 0

		if (plan.points >= TALENT_POINTS_AT_60) then return end
		if (currentPlanned >= maxRank) then return end
		if (not self:IsTierUnlocked(tier, tabID)) then return end
		if (not self:MeetsPlannedPrereqs(tabID, talentID)) then return end

		if (not tabPlan[talentID]) then
			tabPlan[talentID] = 1
		else
			tabPlan[talentID] = tabPlan[talentID] + 1
		end
		tabPlan.points = tabPlan.points + 1
		plan.points = plan.points + 1
	end;

	UnplanTalent = function(self, tabID, talentID)
		local plan = self:GetPlan()
		if (not plan or not plan[tabID]) then return end
		local tabPlan = plan[tabID]
		local currentPlanned = tabPlan[talentID] or 0

		if (currentPlanned <= 0) then return end
		if (not self:CanUnplanTalent(tabID, talentID)) then return end

		local _, _, tier, column = GetTalentInfo(tabID, talentID)
		local hiTier = 0
		for i = 1, GetNumTalents(tabID) do
			local _, _, t, _, r = self:GetSimTalentInfo(tabID, i)
			if (r > 0 and t > hiTier) then hiTier = t end
		end

		local tierTotal = {}
		for i = 1, hiTier do tierTotal[i] = 0 end
		for i = 1, GetNumTalents(tabID) do
			local _, _, t, _, r = self:GetSimTalentInfo(tabID, i)
			if (t <= hiTier) then tierTotal[t] = tierTotal[t] + r end
		end

		local tierFine = true
		for i = tier + 1, hiTier do
			local tierPoints = 0
			for j = 1, i - 1 do
				tierPoints = tierPoints + tierTotal[j]
			end
			if (tierPoints <= (i - 1) * 5) then
				tierFine = false
				break
			end
		end

		if (tier == hiTier or tierFine) then
			tabPlan[talentID] = currentPlanned - 1
			if (tabPlan[talentID] <= 0) then tabPlan[talentID] = nil end
			tabPlan.points = tabPlan.points - 1
			plan.points = plan.points - 1
		end
	end;

	ResetPlan = function(self)
		local plan = self:GetPlan()
		if (not plan) then return end
		plan.points = 0
		for t = 1, 3 do
			if (plan[t]) then
				plan[t] = { points = 0 }
			end
		end
	end;

	ResetTree = function(self, treeIndex)
		local plan = self:GetPlan()
		if (not plan) then return end
		if (treeIndex >= 1 and treeIndex <= 3 and plan[treeIndex]) then
			plan.points = plan.points - plan[treeIndex].points
			plan[treeIndex] = { points = 0 }
		end
	end;

	-- =================== SIM TALENT INFO =========================

	GetSimTalentInfo = function(self, tabID, talentID)
		local name, iconTexture, tier, column, _, maxRank, isExceptional, meetsPrereq = GetTalentInfo(tabID, talentID)
		local rank = self:GetPlannedRank(tabID, talentID)
		return name, iconTexture, tier, column, rank, maxRank, isExceptional, meetsPrereq
	end;

	-- =================== APPLY PLAN ==============================

	StopApply = function(self, message)
		self.applyState = nil
		if (message) then
			MSB_SimulationNotify(message)
		end
	end;

	GetApplyStatus = function(self)
		local plan = self:GetPlan()
		if (not plan) then return 0, nil end

		local requiredPoints = 0
		local numTabs = GetNumTalentTabs()

		for tabID = 1, numTabs do
			local tabPlan = plan[tabID] or { points = 0 }
			local numTalents = GetNumTalents(tabID)

			for talentID = 1, numTalents do
				local _, _, _, _, learnedRank = GetTalentInfo(tabID, talentID)
				local plannedRank = tabPlan[talentID] or 0

				if (learnedRank > plannedRank) then
					return nil, "conflict"
				end
				requiredPoints = requiredPoints + (plannedRank - learnedRank)
			end
		end

		return requiredPoints
	end;

	FindNextApplyTalent = function(self)
		local plan = self:GetPlan()
		if (not plan) then return nil, nil, nil end

		local hasPending = nil
		local numTabs = GetNumTalentTabs()

		for tabID = 1, numTabs do
			local tabPlan = plan[tabID] or { points = 0 }
			local _, _, pointsSpent = GetTalentTabInfo(tabID)
			local numTalents = GetNumTalents(tabID)

			for talentID = 1, numTalents do
				local _, _, tier, _, learnedRank, maxRank = GetTalentInfo(tabID, talentID)
				local plannedRank = tabPlan[talentID] or 0

				if (learnedRank > plannedRank) then
					return nil, nil, "conflict"
				end
				if (learnedRank < plannedRank) then
					hasPending = true
					local meetsPrereq = self:MeetsLearnedPrereqs(tabID, talentID)
					if (learnedRank < maxRank and meetsPrereq and ((tier - 1) * 5 <= pointsSpent)) then
						return tabID, talentID
					end
				end
			end
		end

		return nil, nil, hasPending
	end;

	BeginApply = function(self)
		if (self.applyState) then
			MSB_SimulationNotify(MSB_L("SimApplyRunning"))
			return
		end

		local requiredPoints, conflict = self:GetApplyStatus()
		if (conflict) then
			MSB_SimulationNotify(MSB_L("SimApplyConflict"))
			return
		end
		if (requiredPoints == 0) then
			MSB_SimulationNotify(MSB_L("SimApplyMatched"))
			return
		end
		if (UnitCharacterPoints("player") < requiredPoints) then
			MSB_SimulationNotify(MSB_L("SimApplyNoPoints"))
			return
		end

		self.applyState = { waiting = nil }
		MSB_SimulationNotify(MSB_L("SimApplyRunning"))
		self:ContinueApply()
	end;

	ContinueApply = function(self)
		if (not self.applyState) then return end

		if (self.applyState.waiting) then
			local currentPoints = UnitCharacterPoints("player")
			local _, _, _, _, currentRank = GetTalentInfo(self.applyState.lastTab, self.applyState.lastTalent)

			if (currentPoints >= self.applyState.lastPoints and currentRank <= self.applyState.lastRank) then
				-- Timeout: LearnTalent failed or was rejected
				local started = self.applyState.waitStarted or GetTime()
				if (GetTime() - started > 2.0) then
					self:StopApply(MSB_L("SimApplyTimeout"))
				end
				return
			end
			self.applyState.waiting = nil
		end

		local requiredPoints, conflict = self:GetApplyStatus()
		if (conflict) then
			self:StopApply(MSB_L("SimApplyConflict"))
			return
		end
		if (requiredPoints == 0) then
			self:StopApply(MSB_L("SimApplyDone"))
			return
		end
		if (UnitCharacterPoints("player") < requiredPoints) then
			self:StopApply(MSB_L("SimApplyNoPoints"))
			return
		end

		local tabID, talentID, hasPending = self:FindNextApplyTalent()
		if (not tabID) then
			if (hasPending) then
				self:StopApply(MSB_L("SimApplyConflict"))
			else
				self:StopApply(MSB_L("SimApplyDone"))
			end
			return
		end

		self.applyState.lastTab = tabID
		self.applyState.lastTalent = talentID
		self.applyState.lastPoints = UnitCharacterPoints("player")
		local _, _, _, _, currRank = GetTalentInfo(tabID, talentID)
		self.applyState.lastRank = currRank
		self.applyState.waiting = true
		self.applyState.waitStarted = GetTime()

		LearnTalent(tabID, talentID)
	end;

	IsApplying = function(self)
		return self.applyState ~= nil
	end;

	-- =================== TOOLTIP =================================

	ShowSimTooltip = function(self, tabID, talentID)
		local name, _, _, _, _, maxRank = GetTalentInfo(tabID, talentID)
		local plannedRank = self:GetPlannedRank(tabID, talentID)

		-- Render the native talent tooltip (description + current/next rank effects)
		-- then append simulated-rank info. Fall back to name only if SetTalent is absent.
		if (GameTooltip.SetTalent) then
			GameTooltip:SetTalent(tabID, talentID)
		else
			GameTooltip:ClearLines()
			GameTooltip:AddLine(name or UNKNOWN, 1.0, 1.0, 1.0)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format(MSB_L("SimTooltipRank"), plannedRank, maxRank or 0), 0.0, 1.0, 1.0)
		GameTooltip:AddLine(MSB_L("SimTooltipMode"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end;
}

function MSB_SimulationNotify(messageText)
	if (not messageText or messageText == "") then return end
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff" .. MSB_L("SimTitle") .. ":|r " .. messageText)
	end
end
