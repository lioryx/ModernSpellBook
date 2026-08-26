--[[
	Captures class spells from the trainer window and stores them
	in the unified DB.spells table with learned=false.
--]]

class "CTrainerDataService"
{
	__init = function(self)
		self.frame = CreateFrame("Frame")
		self.frame:RegisterEvent("TRAINER_SHOW")

		local service = self
		self.frame:SetScript("OnEvent", function()
			C_Timer.After(0.3, function()
				service:CaptureTrainerData()
			end)
		end)
	end;

	-- =================== CAPTURE =============================

	CaptureTrainerData = function(self)
		if (not GetNumTrainerServices) then return end

		local numServices = GetNumTrainerServices()
		if (not numServices or numServices == 0) then return end

		-- Detect if this is a class trainer by checking if any
		-- service header matches a talent tab or class spell tab name
		local classCategories = {}
		for t = 1, GetNumTalentTabs() do
			local name = GetTalentTabInfo(t)
			if (name) then classCategories[name] = true end
		end
		local numSpellTabs = GetNumSpellTabs and GetNumSpellTabs() or 4
		for i = 1, numSpellTabs do
			local name = GetSpellTabInfo(i)
			if (name) then classCategories[name] = true end
		end
		classCategories[GENERAL or "General"] = true

		local isClassTrainer = false
		for i = 1, numServices do
			local ok, name = pcall(GetTrainerServiceInfo, i)
			if (ok and name) then
				name = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
				if (classCategories[name]) then
					isClassTrainer = true
					break
				end
			end
		end

		if (not isClassTrainer) then return end

		-- Save current filter state so we can restore after scanning
		local savedFilters = { available = 1, unavailable = 1, used = 1 }
		local filterTypes = { "available", "unavailable", "used" }
		if (GetTrainerServiceTypeFilter) then
			for _, ft in ipairs(filterTypes) do
				local ok, val = pcall(GetTrainerServiceTypeFilter, ft)
				if (ok and val ~= nil) then
					savedFilters[ft] = val
				end
			end
		end

		local function restoreFilters()
			pcall(function()
				if (SetTrainerServiceTypeFilter) then
					for _, ft in ipairs(filterTypes) do
						SetTrainerServiceTypeFilter(ft, savedFilters[ft], 1)
					end
				end
			end)
		end

		-- Enable all filters so we capture everything, then re-count
		pcall(function()
			if (SetTrainerServiceTypeFilter) then
				SetTrainerServiceTypeFilter("available", 1, 1)
				SetTrainerServiceTypeFilter("unavailable", 1, 1)
				SetTrainerServiceTypeFilter("used", 1, 1)
			end
		end)

		numServices = GetNumTrainerServices()

		-- Skip if we already scanned and this trainer has no more services
		if (ModernSpellBook_DB.trainerScanned and ModernSpellBook_DB.trainerServiceCount) then
			if (numServices <= ModernSpellBook_DB.trainerServiceCount) then
				restoreFilters()
				return
			end
		end

		local currentSpecHeader = GENERAL or "General"
		local currentSpecIsValid = true

		-- Dual-key English + zhCN (and common localized) category/skip tables
		local generalCategories = {
			["Defense"] = true, ["防御"] = true,
			["Weapons"] = true, ["武器"] = true,
			["Armor"] = true, ["护甲"] = true,
			["Plate Mail"] = true, ["板甲"] = true,
			["Mail"] = true, ["锁甲"] = true,
			["Leather"] = true, ["皮甲"] = true,
			["Shield"] = true, ["盾牌"] = true,
		}

		local skipSpells = {
			["Plate Mail"] = true, ["板甲"] = true,
			["Mail"] = true, ["锁甲"] = true,
			["Leather"] = true, ["皮甲"] = true,
			["Shield"] = true, ["盾牌"] = true,
			["Block"] = true, ["格挡"] = true,
			["Parry"] = true, ["招架"] = true,
			["Dodge"] = true, ["躲闪"] = true,
			["Dual Wield"] = true, ["双武器"] = true,
		}

		local capturedCount = 0

		for i = 1, numServices do
			local name, rank, category, expanded
			local ok, r1, r2, r3, r4 = pcall(GetTrainerServiceInfo, i)
			if (ok) then
				name = r1 and string.gsub(r1, "^%s+", "") or nil
				name = name and string.gsub(name, "%s+$", "") or nil
				rank = r2 and string.gsub(r2, "^%s+", "") or ""
				rank = string.gsub(rank, "%s+$", "")
				category = r3 and string.gsub(r3, "^%s+", "") or ""
				category = string.gsub(category, "%s+$", "")
			end

			if (name and name ~= "") then
				local icon = ""
				if (GetTrainerServiceIcon) then
					local iconOk, iconResult = pcall(GetTrainerServiceIcon, i)
					if (iconOk) then icon = iconResult or "" end
				end

				if (skipSpells[name]) then
					-- do nothing
				elseif (not icon or icon == "" or icon == 0) then
					-- Category header
					if (generalCategories[name]) then
						currentSpecHeader = GENERAL or "General"
						currentSpecIsValid = true
					elseif (classCategories[name]) then
						currentSpecHeader = name
						currentSpecIsValid = true
					else
						currentSpecHeader = name
						currentSpecIsValid = false
					end
				elseif (not currentSpecIsValid) then
					-- Skip spells under non-class categories (e.g. Poisons)
				else
					local levelReq = 0
					if (GetTrainerServiceLevelReq) then
						local lvlOk, lvlResult = pcall(GetTrainerServiceLevelReq, i)
						if (lvlOk) then levelReq = lvlResult or 0 end
					end

					local description = nil
					pcall(function()
						if (GetTrainerServiceDescription) then
							description = GetTrainerServiceDescription(i)
							if (description) then
								description = string.gsub(string.gsub(description, "^%s+", ""), "%s+$", "")
							end
						end
					end)

					local cost = nil
					pcall(function()
						if (GetTrainerServiceCost) then
							cost = GetTrainerServiceCost(i)
						end
					end)

					local key = MSB_SpellKey(name, rank or "")
					local entry = ModernSpellBook_DB.spells[key]

					if (not entry) then
						-- New spell from trainer, player doesn't know it yet
						ModernSpellBook_DB.spells[key] = {
							icon = icon,
							category = currentSpecHeader,
							desc = description,
							cost = cost,
							level_req = levelReq,
							keywords = string.lower(name .. ";" .. (rank or "") .. ";" .. currentSpecHeader .. ";"),
							learned = false,
							seen_new = true,
							seen_trainable = false,
						}
						capturedCount = capturedCount + 1
					elseif (not entry.learned) then
						-- Already registered as unlearned, update trainer data
						entry.icon = icon
						entry.category = currentSpecHeader
						entry.desc = description
						entry.cost = cost
						entry.level_req = levelReq
						capturedCount = capturedCount + 1
					else
						-- Already learned, just update metadata
						capturedCount = capturedCount + 1
					end
				end
			end
		end

		ModernSpellBook_DB.trainerScanned = true
		ModernSpellBook_DB.trainerServiceCount = numServices

		restoreFilters()

		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ModernSpellBook:|r " .. MSB_L("CmdCaptured", capturedCount))

		if (ModernSpellBookFrame:IsVisible()) then
			SpellBook:DrawPage()
		end
	end;

	-- ================= UNLEARNED SPELLS =======================

	GetUnlearnedSpells = function(self)
		-- Build a set of currently known spells from spellbook
		local knownSet = {}
		local knownHighestRank = {}
		local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 4
		for i = 1, numTabs do
			local tabName, texture, offset, numSpells = GetSpellTabInfo(i)
			if (not tabName) then break end
			for s = offset + 1, offset + numSpells do
				local spellName, spellRank = GetSpellName(s, BOOKTYPE_SPELL)
				if (spellName) then
					knownSet[MSB_SpellKey(spellName, spellRank or "")] = true
					local _, _, num = string.find(spellRank or "", "(%d+)")
					local rankNum = tonumber(num) or 0
					if (not knownHighestRank[spellName] or rankNum > knownHighestRank[spellName]) then
						knownHighestRank[spellName] = rankNum
					end
				end
			end
		end

		-- Find spells whose Rank 1 comes from an unlearned talent
		local talentBlockedSpells = {}
		for t = 1, GetNumTalentTabs() do
			local talentGroupName = GetTalentTabInfo(t)
			if (talentGroupName) then
				for i = 1, GetNumTalents(t) do
					local nameTalent, icon, tier, column, currRank, maxRank = GetTalentInfo(t, i)
					if (nameTalent and currRank == 0) then
						local trainerHas = false
						for spellKey, entry in pairs(ModernSpellBook_DB.spells) do
							if (not entry.learned and MSB_SpellNameFromKey(spellKey) == nameTalent) then
								trainerHas = true
								break
							end
						end
						if (trainerHas) then
							talentBlockedSpells[nameTalent] = true
						end
					end
				end
			end
		end

		local unlearnedByCategory = {}
		local trainerSpellNames = {}

		-- Collect unlearned spells from DB (trainer data)
		if (ModernSpellBook_DB.trainerScanned) then
			for spellKey, entry in pairs(ModernSpellBook_DB.spells) do
				if (not entry.learned) then
					local name = MSB_SpellNameFromKey(spellKey)
					local rank = MSB_SpellRankFromKey(spellKey)
					if (not name) then
						-- skip malformed key
					elseif (knownSet[spellKey]) then
						entry.learned = true
					else
						local rankNum = MSB_RankNumber(rank)
						local highest = knownHighestRank[name]
						if (highest and (rankNum <= highest or highest == 0)) then
							entry.learned = true
						else
							local cat = entry.category or MSB_L("UnknownCategory")
							if (not unlearnedByCategory[cat]) then
								unlearnedByCategory[cat] = {}
							end
							local isPassive = (rank == (PASSIVE or "Passive") or rank == (PET_PASSIVE or "Passive"))
							table.insert(unlearnedByCategory[cat], {
								spellName = name,
								spellRank = rank,
								spellIcon = entry.icon,
								spellID = nil,
								bookType = nil,
								description = entry.desc,
								cost = entry.cost,
								isPassive = isPassive,
								isTalent = false,
								isPetSpell = false,
								isUnlearned = true,
								talentBlocked = talentBlockedSpells[name] or false,
								levelReq = entry.level_req,
								castName = nil,
								category = cat,
							})
							trainerSpellNames[name] = true
						end
					end
				end
			end
		end

		-- Always add unlearned talents (doesn't require trainer data)
		for t = 1, GetNumTalentTabs() do
			local talentGroupName = GetTalentTabInfo(t)
			if (talentGroupName) then
				for i = 1, GetNumTalents(t) do
					local nameTalent, icon, tier, column, currRank, maxRank = GetTalentInfo(t, i)
					if (nameTalent and currRank == 0) then
						local isKnown = false
						for knownKey, _ in pairs(knownSet) do
							if (MSB_SpellNameFromKey(knownKey) == nameTalent) then
								isKnown = true
								break
							end
						end

						if (not isKnown) then
							local trainerHasRanks = trainerSpellNames[nameTalent]

							if (not unlearnedByCategory[talentGroupName]) then
								unlearnedByCategory[talentGroupName] = {}
							end

							local alreadyAdded = false
							for _, s in ipairs(unlearnedByCategory[talentGroupName]) do
								-- Match by name; if trainer has ranks, prefer the lowest-rank entry
								if (s.spellName == nameTalent) then
									if (not trainerHasRanks or MSB_RankNumber(s.spellRank) == 1 or s.isTalent) then
										alreadyAdded = true
										break
									end
								end
							end

							if (not alreadyAdded) then
								local showAsTalentGate = trainerHasRanks or (maxRank == 1)
								if (showAsTalentGate) then
									table.insert(unlearnedByCategory[talentGroupName], {
										spellName = nameTalent,
										spellRank = "",
										spellIcon = icon,
										spellID = nil,
										bookType = nil,
										isPassive = false,
										isTalent = true,
										talentGrid = {t, i},
										isPetSpell = false,
										isUnlearned = true,
										levelReq = 10 + (tier - 1) * 5,
										castName = nil,
										category = talentGroupName,
									})
								end
							end
						end
					end
				end
			end
		end

		-- Sort each category
		for cat, spells in pairs(unlearnedByCategory) do
			local groupMinLevel = {}
			for _, sp in ipairs(spells) do
				local lvl = sp.levelReq or 0
				if (not groupMinLevel[sp.spellName] or lvl < groupMinLevel[sp.spellName]) then
					groupMinLevel[sp.spellName] = lvl
				end
			end

			table.sort(spells, function(a, b)
				local aGroupLvl = groupMinLevel[a.spellName] or 0
				local bGroupLvl = groupMinLevel[b.spellName] or 0
				if (aGroupLvl ~= bGroupLvl) then
					return aGroupLvl < bGroupLvl
				end
				if (a.spellName ~= b.spellName) then
					return a.spellName < b.spellName
				end
				return (a.levelReq or 0) < (b.levelReq or 0)
			end)
		end

		return unlearnedByCategory
	end;
}

TrainerDataService = CTrainerDataService()
