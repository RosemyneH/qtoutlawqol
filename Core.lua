local _G = _G
local ipairs = ipairs
local tostring = tostring
local ClearCursor = ClearCursor
local GetContainerItemID = GetContainerItemID
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots
local GetItemInfo = GetItemInfo
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local PickupContainerItem = PickupContainerItem
local SplitContainerItem = SplitContainerItem
local hooksecurefunc = hooksecurefunc
local tinsert = table.insert

local db
local refresh = {}
local installed = {}
local booted
local boxBusy

local function EnsureDB()
	if db then return db end
	if type(qtOutlawQoLDB) ~= "table" then qtOutlawQoLDB = {} end
	db = qtOutlawQoLDB
	if db.craftTab == nil then db.craftTab = true end
	if db.breakAll == nil then db.breakAll = true end
	if db.deposit == nil then db.deposit = true end
	if db.sort == nil then db.sort = true end
	return db
end

local function Say(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1qt|rOutlawQoL: " .. msg)
end

local TOGGLES = {
	{ key = "craftTab", name = "Crafting tab", cmd = "craft" },
	{ key = "breakAll", name = "Break down all", cmd = "break" },
	{ key = "deposit", name = "Smart deposit", cmd = "deposit" },
	{ key = "sort", name = "Lockbox sort", cmd = "sort" },
}

local function Slash(msg)
	EnsureDB()
	msg = string.lower(strtrim(msg or ""))
	if msg == "" then
		Say("Crafting tab, break down all, smart deposit, lockbox sort.")
		for i = 1, #TOGGLES do
			local row = TOGGLES[i]
			Say("/qol " .. row.cmd .. "  " .. row.name .. ": " .. (db[row.key] and "|cff00ff00on|r" or "|cffff0000off|r"))
		end
		return
	end
	for i = 1, #TOGGLES do
		local row = TOGGLES[i]
		if msg == row.cmd then
			db[row.key] = not db[row.key]
			if refresh[row.key] then refresh[row.key]() end
			Say(row.name .. (db[row.key] and " on." or " off."))
			return
		end
	end
	Say("Try /qol, /qol craft, /qol break, /qol deposit, /qol sort.")
end

local function RegisterSlash()
	SLASH_QTOUTLAWQOL1 = "/qol"
	SLASH_QTOUTLAWQOL2 = "/qtqol"
	SlashCmdList.QTOUTLAWQOL = Slash
end

-- ʕ •ᴥ•ʔ✿ Same read the lockbox uses: a real item row, never a coin stack ✿ ʕ •ᴥ•ʔ
local function ContainerHas(OC, entry)
	entry = tonumber(entry)
	if not entry or entry == 0 or not OC.Lockbox then return false end
	local items = OC.Lockbox.items
	if items then
		for _, row in ipairs(items) do
			if tonumber(row.entry) == entry and not row.coin then return true end
		end
	end
	local slots = OC.Lockbox.slots
	if slots then
		for _, slot in ipairs(slots) do
			if tonumber(slot.entry) == entry and not slot.coin then return true end
		end
	end
end

-- ＼ʕ •ᴥ•ʔ／✿ A Crafting tab under the spellbook's school tabs, so the Blueprints window is one click away ✿ ＼ʕ •ᴥ•ʔ／
local function InstallCraft(OC)
	local Builder, book = OC.Builder, _G.SpellBookFrame
	if not (Builder and Builder.frame and Builder.IsOpen and Builder.Open and Builder.Close and book) then return false end

	local BLUEPRINTS_SPELL = 901514
	local icon = (GetSpellInfo and select(3, GetSpellInfo(BLUEPRINTS_SPELL))) or "Interface\\Icons\\Trade_Engineering"
	local tab = CreateFrame("CheckButton", "qtOutlawQoLCraftTab", book, "SpellBookSkillLineTabTemplate")
	tab:SetWidth(32)
	tab:SetHeight(32)
	tab:SetNormalTexture(icon)

	local function Place()
		local last
		for i = _G.MAX_SKILLLINE_TABS, 1, -1 do
			local skillTab = _G["SpellBookSkillLineTab"..i]
			if skillTab and skillTab:IsShown() then last = skillTab break end
		end
		tab:ClearAllPoints()
		if last then
			tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -17)
		else
			tab:SetPoint("TOPLEFT", book, "TOPRIGHT", -33, -65)
		end
		if not db.craftTab or book.bookType == _G.BOOKTYPE_PET then tab:Hide() else tab:Show() end
		tab:SetChecked(Builder.IsOpen())
	end

	tab:SetScript("OnClick", function(self)
		if not db.craftTab then return end
		if Builder.IsOpen() then Builder.Close() else Builder.Open() end
		self:SetChecked(Builder.IsOpen())
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Crafting")
		GameTooltip:AddLine("Open the Blueprints crafting window.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)

	book:HookScript("OnShow", Place)
	if _G.SpellBookFrame_UpdateSkillLineTabs then
		hooksecurefunc("SpellBookFrame_UpdateSkillLineTabs", Place)
	end
	Builder.frame:HookScript("OnShow", function() tab:SetChecked(true) end)
	Builder.frame:HookScript("OnHide", function() tab:SetChecked(false) end)
	refresh.craftTab = Place
	Place()
	return true
end

-- ʕ •ᴥ•ʔ✿ One click for the whole Break down list. Each piece is its own cast, so the next waits until that piece is gone. Alt-click holds a piece out of that batch until reload ✿ ʕ •ᴥ•ʔ
local function InstallBreak(OC)
	local Builder, UI = OC.Builder, OC.UI
	if not (Builder and Builder.rows and Builder.Render and UI and UI.Button and OC.Send and OC.CMD_BREAK_DOWN) then return false end

	local BREAK_DOWN = 99
	local breakQueue, breakSent
	local heldBreak = {}
	local breakAll = UI.Button(Builder.frame, "qtOutlawQoLBreakAll", "All", 36, 16)
	breakAll:Hide()

	local function SalvageByEntry(entry)
		for _, row in ipairs(Builder.salvage or {}) do
			if row.entry == entry then return row end
		end
	end

	local function CanBreak(row)
		return row and row.reason == 0 and (row.have or 0) > 0 and not heldBreak[row.entry]
	end

	local function BatchYield()
		local totals, order, pieces, leftOut = {}, {}, 0, 0
		for _, row in ipairs(Builder.salvage or {}) do
			if row.reason == 0 and (row.have or 0) > 0 then
				if heldBreak[row.entry] then
					leftOut = leftOut + 1
				else
					pieces = pieces + 1
					for _, y in ipairs(row.yields or {}) do
						local id = y.entry
						if id then
							local slot = totals[id]
							if not slot then
								slot = { entry = id, name = y.name or "Item", count = 0 }
								totals[id] = slot
								order[#order + 1] = slot
							end
							if y.name and y.name ~= "" then slot.name = y.name end
							slot.count = slot.count + (y.count or 0) * (row.have or 0)
						end
					end
				end
			end
		end
		table.sort(order, function(a, b)
			if a.name ~= b.name then return a.name < b.name end
			return a.entry < b.entry
		end)
		return order, pieces, leftOut
	end

	local function MarkHeld()
		if not db.breakAll or not UI.Paint then return end
		for i = 1, #Builder.rows do
			local row = Builder.rows[i]
			local recipe = row.button and row.button.recipe
			if recipe and recipe.salvage and heldBreak[recipe.entry] then
				row.label:SetText(UI.Paint("dim", recipe.name or ""))
				row.icon:SetAlpha(0.3)
			end
		end
	end

	local function UpdateBreakAll()
		if not db.breakAll then
			breakQueue, breakSent = nil, nil
			breakAll:Hide()
			return
		end
		local ready = 0
		for _, row in ipairs(Builder.salvage or {}) do
			if CanBreak(row) then ready = ready + 1 end
		end
		local host
		if breakQueue or ready > 0 then
			for _, row in ipairs(Builder.rows) do
				if row.button and row.button.header == BREAK_DOWN then
					host = row
					break
				end
			end
		end
		breakAll.stopping = breakQueue ~= nil
		if not host then
			breakAll:Hide()
			return
		end
		breakAll:SetParent(host.button)
		breakAll:ClearAllPoints()
		breakAll:SetPoint("RIGHT", host.count, "LEFT", -2, 0)
		breakAll:SetFrameLevel(host.button:GetFrameLevel() + 5)
		breakAll:SetText(breakQueue and "Stop" or "All")
		breakAll:Show()
		host.label:ClearAllPoints()
		host.label:SetPoint("LEFT", host.button, "LEFT", 18, 0)
		host.label:SetPoint("RIGHT", breakAll, "LEFT", -4, 0)
	end

	local function SendBreak(row)
		local qty = math.min(row.have or 1, 100)
		local msg = OC.CMD_BREAK_DOWN .. row.entry
		if qty > 1 then msg = msg .. "," .. qty end
		breakSent = { entry = row.entry, have = row.have }
		OC.Send(msg)
	end

	local function SendNextBreak()
		if not breakQueue then return end
		while #breakQueue > 0 do
			local row = SalvageByEntry(table.remove(breakQueue, 1))
			if CanBreak(row) then
				SendBreak(row)
				UpdateBreakAll()
				return
			end
		end
		breakQueue, breakSent = nil, nil
		UpdateBreakAll()
	end

	local function AdvanceBreakQueue()
		if not breakSent then return end
		local row = SalvageByEntry(breakSent.entry)
		local have = row and row.have or 0
		if have < breakSent.have then
			if CanBreak(row) then
				if not breakQueue then breakQueue = {} end
				tinsert(breakQueue, 1, row.entry)
			end
			breakSent = nil
			SendNextBreak()
		end
	end

	breakAll:SetScript("OnClick", function()
		if not db.breakAll then return end
		if breakQueue then
			breakQueue, breakSent = nil, nil
			UpdateBreakAll()
			return
		end
		local queue = {}
		for _, row in ipairs(Builder.salvage or {}) do
			if CanBreak(row) then
				tinsert(queue, row.entry)
			end
		end
		if #queue == 0 then return end
		breakQueue = queue
		SendNextBreak()
	end)
	breakAll:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.stopping then
			GameTooltip:SetText("Stop")
			GameTooltip:AddLine("Leave the piece already started. Skip the rest.", 1, 1, 1, true)
		else
			GameTooltip:SetText("Break down all")
			GameTooltip:AddLine("Every piece you can break down, one after another.", 1, 1, 1, true)
			GameTooltip:AddLine("Alt-click a piece to leave it out until you reload.", 0.65, 0.65, 0.65, true)
			local yields, pieces, leftOut = BatchYield()
			if pieces > 0 then
				GameTooltip:AddLine(pieces == 1 and "1 piece." or (pieces .. " pieces."), 1, 1, 1, true)
			end
			for i = 1, #yields do
				local y = yields[i]
				if y.count > 0 then
					GameTooltip:AddLine("|cff20ff20+" .. y.count .. " " .. y.name .. "|r")
				end
			end
			if leftOut > 0 then
				GameTooltip:AddLine(leftOut == 1 and "1 left out." or (leftOut .. " left out."), 0.8, 0.8, 0.8, true)
			end
		end
		GameTooltip:Show()
	end)
	breakAll:SetScript("OnLeave", GameTooltip_Hide)

	local function OnRowClick(self, mouseButton)
		if mouseButton and mouseButton ~= "LeftButton" then return end
		if not db.breakAll or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
		local recipe = self.recipe
		if not recipe or not recipe.salvage or not recipe.entry then return end
		local name = recipe.name or "That piece"
		if heldBreak[recipe.entry] then
			heldBreak[recipe.entry] = nil
			Say(name .. " is back in Break down all.")
		else
			heldBreak[recipe.entry] = true
			if breakQueue then
				local kept = {}
				for i = 1, #breakQueue do
					if breakQueue[i] ~= recipe.entry then kept[#kept + 1] = breakQueue[i] end
				end
				breakQueue = #kept > 0 and kept or (breakSent and {} or nil)
			end
			Say(name .. " left out of Break down all.")
		end
		Builder.Render()
	end

	local function OnRowEnter(self)
		if not db.breakAll then return end
		local recipe = self.recipe
		if not recipe or not recipe.salvage or not GameTooltip:IsShown() then return end
		if heldBreak[recipe.entry] then
			GameTooltip:AddLine("Left out of Break down all. Alt-click to put it back.", 1, 0.82, 0, true)
		else
			GameTooltip:AddLine("Alt-click to leave this out of Break down all.", 0.65, 0.65, 0.65, true)
		end
		GameTooltip:Show()
	end

	for i = 1, #Builder.rows do
		local button = Builder.rows[i].button
		if button then
			button:HookScript("OnClick", OnRowClick)
			button:HookScript("OnEnter", OnRowEnter)
		end
	end

	hooksecurefunc(Builder, "Render", function()
		AdvanceBreakQueue()
		UpdateBreakAll()
		MarkHeld()
	end)
	refresh.breakAll = UpdateBreakAll
	UpdateBreakAll()
	return true
end

-- ʕ •ᴥ•ʔ✿ The chest cannot merge a partial where it sits. Take that stack out, let the bags finish it, then put the stack back ✿ ʕ •ᴥ•ʔ
local stackDeposit

local function StackDeposit(OC)
	if stackDeposit then return stackDeposit end
	if not (OC.Send and OC.CMD_DEPOSIT and OC.Lockbox and OC.Lockbox.Render) then return end

	local job
	local waiter = CreateFrame("Frame")
	waiter:Hide()
	waiter:RegisterEvent("BAG_UPDATE")

	local function Signature()
		local parts = {}
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			if it and it.index ~= nil then
				parts[#parts + 1] = it.index .. "=" .. (it.entry or 0) .. ":" .. (it.count or 0)
			end
		end
		table.sort(parts)
		return table.concat(parts, "|")
	end

	local function RowsFor(entry, quality)
		local rows, total, locked = {}, 0, false
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				if GetContainerItemID(b, s) == entry then
					local _, count, isLocked, rowQuality = GetContainerItemInfo(b, s)
					if (rowQuality or 0) == quality then
						if isLocked then
							locked = true
						else
							count = count or 0
							rows[#rows + 1] = { bag = b, slot = s, count = count }
							total = total + count
						end
					end
				end
			end
		end
		return rows, total, locked
	end

	local function MaxStack(entry)
		local max = GetItemInfo and select(8, GetItemInfo(entry))
		if max and max > 1 then return max end
	end

	local function Partial(entry, quality, maxStack)
		if not maxStack then return end
		local best
		local items = OC.Lockbox.items
		if not items then return end
		for i = 1, #items do
			local it = items[i]
			local count = it and it.count or 0
			if it and not it.coin and tonumber(it.entry) == entry and (it.quality or 0) == quality and it.index ~= nil and count > 0 and count < maxStack then
				if not best or count < (best.count or 0) then best = it end
			end
		end
		return best
	end

	local function Stop(reason)
		if not job then return end
		job = nil
		if boxBusy == "deposit" then boxBusy = nil end
		waiter:Hide()
		if reason and reason ~= false then OC.Print("Deposit stopped: " .. reason .. ".") end
	end

	local Step
	local function Advance()
		if not job or not job.wait then return end
		if not OC.Lockbox.IsOpen() then return Stop(false) end
		if job.warm then return end
		local item = job.items[1]
		if not item then return end
		if job.locked then
			local rows = RowsFor(item.entry, item.quality)
			if rows[1] then
				job.locked = nil
				job.wait = false
				Step()
			end
			return
		end
		local sig = Signature()
		local _, total = RowsFor(item.entry, item.quality)
		local chestMoved = sig ~= job.sig
		if job.need then
			if chestMoved and total >= job.need then
				job.wait = false
				job.sig = sig
				Step()
			end
		elseif total < (job.bag or 0) then
			job.wait = false
			job.sig = sig
			Step()
		end
	end

	function Step()
		if not job then return end
		if not OC.Lockbox.IsOpen() or OC.Lockbox.readOnly then return Stop(false) end
		if GetCursorInfo and GetCursorInfo() then return Stop("you are holding something") end
		if job.wait then return end
		if job.moves >= job.limit then return Stop("it was going round in circles") end

		while job.items[1] do
			local item = job.items[1]
			local rows, total, locked = RowsFor(item.entry, item.quality)
			local maxStack = MaxStack(item.entry)
			if not maxStack and not item.warmed then
				if OC.UI and OC.UI.WarmItem then OC.UI.WarmItem(item.entry) end
				item.warmed = true
				job.warm = true
				job.wait = true
				job.since = GetTime()
				return
			end
			local partial = Partial(item.entry, item.quality, maxStack)
			if partial and total > 0 and OC.CMD_TAKEONE then
				local token = "T" .. partial.index
				if job.last == token then return Stop("a take was refused") end
				job.last = token
				job.moves = job.moves + 1
				job.wait = true
				job.since = GetTime()
				job.sig = Signature()
				job.bag = total
				job.need = total + (partial.count or 0)
				OC.Send(OC.CMD_TAKEONE .. partial.index)
				return
			end
			local row = rows[1]
			if row then
				local token = "D" .. row.bag .. "," .. row.slot
				if job.last == token then return Stop("a deposit was refused") end
				job.last = token
				job.moves = job.moves + 1
				job.wait = true
				job.since = GetTime()
				job.sig = Signature()
				job.bag = total
				job.need = nil
				OC.Send(OC.CMD_DEPOSIT .. row.bag .. "," .. row.slot)
				return
			end
			if locked then
				job.locked = true
				job.wait = true
				job.need = nil
				job.since = GetTime()
				return
			end
			table.remove(job.items, 1)
			job.last = nil
		end
		Stop(false)
	end

	waiter:SetScript("OnEvent", Advance)
	waiter:SetScript("OnUpdate", function()
		if not job or not job.wait then return end
		if not OC.Lockbox.IsOpen() then return Stop(false) end
		if job.warm and GetTime() - job.since > 0.4 then
			job.warm = nil
			job.wait = false
			Step()
			return
		end
		if GetTime() - job.since > 5 then Stop("a move did not finish") end
	end)
	hooksecurefunc(OC.Lockbox, "Render", Advance)
	if OC.Lockbox.frame then
		OC.Lockbox.frame:HookScript("OnHide", function()
			if job then Stop(false) end
		end)
	end

	local function Start(items)
		if job or not items or #items == 0 then return end
		if not OC.Lockbox.IsOpen() or OC.Lockbox.readOnly then return end
		if boxBusy == "sort" or boxBusy == "leave" then
			OC.Print(boxBusy == "leave" and "Leave one is still moving a stack." or "Sort is still running.")
			return
		end
		if GetCursorInfo and GetCursorInfo() then
			OC.Print("Deposit: you are holding something.")
			return
		end
		job = { items = items, moves = 0, limit = 200, wait = false, since = GetTime(), sig = Signature() }
		boxBusy = "deposit"
		waiter:Show()
		Step()
	end

	stackDeposit = Start
	return Start
end

local function DepositQueue(OC, onlyEntry, onlyQuality)
	local seen, list = {}, {}
	for b = 0, 4 do
		for s = 1, GetContainerNumSlots(b) or 0 do
			local entry = GetContainerItemID(b, s)
			if entry and ContainerHas(OC, entry) then
				local quality = select(4, GetContainerItemInfo(b, s)) or 0
				if not onlyEntry or (entry == onlyEntry and quality == (onlyQuality or 0)) then
					local key = entry .. ":" .. quality
					if not seen[key] then
						seen[key] = true
						list[#list + 1] = { entry = entry, quality = quality }
					end
				end
			end
		end
	end
	return list
end

-- ʕ •ᴥ•ʔ✿ Shift-click Deposit All sends bag stacks the chest already holds. A plain click is still Deposit All ✿ ʕ •ᴥ•ʔ
local function InstallDeposit(OC)
	local depositAll = OC.Lockbox and OC.Lockbox.depositAllButton
	if not (depositAll and OC.Lockbox.DepositAll and OC.Send and OC.CMD_DEPOSIT) then return false end
	if not StackDeposit(OC) then return false end

	depositAll:SetScript("OnClick", function()
		if not db.deposit or not IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown() then
			OC.Lockbox.DepositAll()
			return
		end
		if OC.Lockbox.readOnly or not OC.Lockbox.IsOpen() then return end
		stackDeposit(DepositQueue(OC))
	end)
	depositAll:HookScript("OnEnter", function()
		GameTooltip:SetOwner(depositAll, "ANCHOR_TOP")
		GameTooltip:SetText("Deposit All")
		if db.deposit then
			GameTooltip:AddLine("Shift-click deposits only items already in the chest. An open stack in the chest is taken out so it can join the one in your bags, then the stack goes back.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	depositAll:HookScript("OnLeave", GameTooltip_Hide)
	return true
end

-- ʕ •ᴥ•ʔ✿ Sort fills each column downward. Common on the left, rarer to the right. Same item keeps its own column when the grid has room. One real move at a time ✿ ʕ •ᴥ•ʔ
local function InstallSort(OC)
	local lockFrame = OC.Lockbox and OC.Lockbox.frame
	if not (lockFrame and lockFrame.AddBarButton and OC.UI and OC.UI.Button and OC.Send and OC.CMD_MOVE and OC.Lockbox.Render) then return false end

	local sortButton = OC.UI.Button(lockFrame, "qtOutlawQoLLockboxSort", "Sort", 44, 22)
	lockFrame:AddBarButton(sortButton)
	sortButton:Hide()

	local sorting
	local sorter = CreateFrame("Frame")
	sorter:Hide()

	local function StackKey(item)
		return tostring(item.entry) .. ":" .. tostring(item.count or 0) .. ":" .. tostring(item.quality or 0)
	end

	local function ColumnLists(columns, capacity, blocked)
		local cols = {}
		for c = 0, columns - 1 do
			local list, row = {}, 0
			while true do
				local cell = row * columns + c
				if cell >= capacity then break end
				if not blocked[cell] then tinsert(list, cell) end
				row = row + 1
			end
			cols[c + 1] = list
		end
		return cols
	end

	-- ʕ ◕ᴥ◕ ʔ✿ gapped gives each kind a fresh column. Tight packs straight down when that would run out of columns ✿ ʕ ◕ᴥ◕ ʔ
	local function Assign(groups, colLists, gapped)
		local columns, col, row = #colLists, 1, 1
		local cellOf = {}
		for g = 1, #groups do
			local group = groups[g]
			if gapped and row > 1 then
				col, row = col + 1, 1
			end
			for n = 1, #group.items do
				while col <= columns and row > #colLists[col] do
					col, row = col + 1, 1
				end
				if col > columns then return end
				cellOf[group.items[n].index] = colLists[col][row]
				row = row + 1
			end
		end
		return cellOf
	end

	local function PlanSort(items, capacity)
		items = items or {}
		capacity = capacity or 0
		if capacity < 1 then return {} end

		local columns = 6
		if OC.Lockbox.Grid then
			local grid = OC.Lockbox.Grid()
			if grid and grid.columns and grid.columns > 0 then columns = grid.columns end
		elseif OC.UI.ContainerColumns then
			columns = OC.UI.ContainerColumns(capacity)
		end

		local blocked, sortable = {}, {}
		for i = 1, #items do
			local it = items[i]
			if it and it.index ~= nil then
				if it.coin then
					blocked[it.index] = true
				elseif it.entry and it.entry ~= 0 then
					tinsert(sortable, it)
				end
			end
		end
		local groups, grouped = {}, {}
		for i = 1, #sortable do
			local it = sortable[i]
			local key = tostring(it.entry) .. ":" .. tostring(it.quality or 0)
			local group = grouped[key]
			if not group then
				group = { entry = it.entry, quality = it.quality or 0, items = {} }
				grouped[key] = group
				groups[#groups + 1] = group
			end
			tinsert(group.items, it)
		end
		-- ʕ •ᴥ•ʔ✿ Poor sits on the right. Everything else runs common to rare, tallest stack of that kind first ✿ ʕ •ᴥ•ʔ
		local function Rank(quality)
			if not quality or quality <= 0 then return 100 end
			return quality
		end
		table.sort(groups, function(a, b)
			local ra, rb = Rank(a.quality), Rank(b.quality)
			if ra ~= rb then return ra < rb end
			if #a.items ~= #b.items then return #a.items > #b.items end
			local na = a.items[1] and a.items[1].name or ""
			local nb = b.items[1] and b.items[1].name or ""
			if na ~= nb then return na < nb end
			return (a.entry or 0) < (b.entry or 0)
		end)
		for i = 1, #groups do
			table.sort(groups[i].items, function(a, b)
				if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
				return (a.index or 0) < (b.index or 0)
			end)
		end

		local cols = ColumnLists(columns, capacity, blocked)
		local cellOf = Assign(groups, cols, true) or Assign(groups, cols, false)
		if not cellOf then return {} end

		local at, want = {}, {}
		for i = 1, #sortable do
			local it = sortable[i]
			at[it.index] = StackKey(it)
			local cell = cellOf[it.index]
			if cell then want[cell] = StackKey(it) end
		end

		local moves = {}
		for cell = 0, capacity - 1 do
			local wk = want[cell]
			if wk and at[cell] ~= wk then
				local src
				for j = 0, capacity - 1 do
					if j ~= cell and at[j] == wk and want[j] ~= wk then
						src = j
						break
					end
				end
				if not src then
					for j = 0, capacity - 1 do
						if j ~= cell and at[j] == wk then
							src = j
							break
						end
					end
				end
				if src and src ~= cell then
					at[src], at[cell] = at[cell], at[src]
					moves[#moves + 1] = { from = src, to = cell }
				end
			end
		end
		return moves
	end

	local function Signature()
		local parts = {}
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			if it and it.index ~= nil then
				parts[#parts + 1] = it.index .. "=" .. (it.entry or 0) .. ":" .. (it.count or 0)
			end
		end
		table.sort(parts)
		return table.concat(parts, "|")
	end

	local function StopSort(reason)
		if not sorting then return end
		local moves = sorting.moves
		sorting = nil
		if boxBusy == "sort" then boxBusy = nil end
		sorter:Hide()
		sortButton:SetText("Sort")
		if reason == false then return end
		if reason then
			OC.Print("Sort stopped: " .. reason .. ".")
		elseif moves == 0 then
			OC.Print("The lockbox is already sorted.")
		else
			OC.Print("Lockbox sorted.")
		end
	end

	local function SyncSortButton()
		if not db.sort or OC.Lockbox.readOnly then
			if sorting then StopSort(false) end
			sortButton:Hide()
			return
		end
		sortButton:Show()
		sortButton:SetText(sorting and "Stop" or "Sort")
	end

	local function BagRows(entry)
		local rows, total, held = {}, 0, 0
		entry = tonumber(entry)
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				local id = GetContainerItemID(b, s)
				if id and tonumber(id) == entry then
					local _, count, isLocked = GetContainerItemInfo(b, s)
					count = count or 0
					held = held + count
					if not isLocked then
						rows[#rows + 1] = { bag = b, slot = s, count = count }
						total = total + count
					end
				end
			end
		end
		return rows, total, held
	end

	local function EmptySlots()
		local n = 0
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				if not GetContainerItemID(b, s) then n = n + 1 end
			end
		end
		return n
	end

	local function Cap(entry)
		local max = select(8, GetItemInfo(entry))
		if max and max > 1 then return max end
	end

	-- ʕ •ᴥ•ʔ✿ Open stacks of one item. The chest will not join them, so they have to leave and come back ✿ ʕ •ᴥ•ʔ
	local function Partials(entry, taken)
		local cap = Cap(entry)
		local list = {}
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			local count = it and it.count or 0
			if it and not it.coin and tonumber(it.entry) == entry and it.index ~= nil and count > 0 and not (taken and taken[it.index]) then
				if cap and count < cap then list[#list + 1] = it end
			end
		end
		table.sort(list, function(a, b)
			if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) < (b.count or 0) end
			return (a.index or 0) < (b.index or 0)
		end)
		return list
	end

	local function NextSplit()
		local seen = {}
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			local entry = it and not it.coin and tonumber(it.entry)
			if entry and entry ~= 0 and not seen[entry] and not (sorting.done and sorting.done[entry]) then
				seen[entry] = true
				if #Partials(entry) >= 2 then return entry end
			end
		end
	end

	local function CanTake(entry, count)
		if EmptySlots() > 0 then return true end
		local cap = Cap(entry)
		if not cap then return false end
		local rows = BagRows(entry)
		for i = 1, #rows do
			if (rows[i].count or 0) + count <= cap then return true end
		end
	end

	local function WarmSplits()
		local seen, any = {}, false
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			local entry = it and not it.coin and tonumber(it.entry)
			if entry and entry ~= 0 and not seen[entry] and not (sorting.done and sorting.done[entry]) and not Cap(entry) then
				seen[entry] = true
				local n = 0
				for j = 1, #items do
					local other = items[j]
					if other and not other.coin and tonumber(other.entry) == entry and (other.count or 0) > 0 and other.index ~= nil then
						n = n + 1
					end
				end
				if n >= 2 then
					any = true
					if OC.UI and OC.UI.WarmItem then OC.UI.WarmItem(entry) end
				end
			end
		end
		return any
	end

	local function SendWait(token, message)
		if sorting.moves >= sorting.limit then return StopSort("it was going round in circles") end
		if sorting.last == token then return StopSort("a move was refused") end
		sorting.last = token
		sorting.moves = sorting.moves + 1
		sorting.wait = true
		sorting.since = GetTime()
		sorting.sig = Signature()
		OC.Send(message)
	end

	local function SortStep()
		if not sorting or not db.sort then return end
		if not OC.Lockbox.IsOpen() then return StopSort(false) end
		if OC.Lockbox.readOnly then return StopSort(false) end
		if GetCursorInfo and GetCursorInfo() then return StopSort("you are holding something") end

		local pull = sorting.pull
		if pull and OC.CMD_TAKEONE and OC.CMD_DEPOSIT then
			local rows, total, held = BagRows(pull.entry)
			local partial = Partials(pull.entry, pull.taken)[1]
			if partial and CanTake(pull.entry, partial.count or 0) then
				pull.taken = pull.taken or {}
				pull.taken[partial.index] = true
				pull.need = total + (partial.count or 0)
				pull.phase = "out"
				return SendWait("T" .. partial.index, OC.CMD_TAKEONE .. partial.index)
			end
			local row = rows[1]
			if row then
				pull.bag = held
				pull.phase = "in"
				return SendWait("P" .. row.bag .. "," .. row.slot, OC.CMD_DEPOSIT .. row.bag .. "," .. row.slot)
			end
			if held > total then
				pull.phase = "hold"
				sorting.wait = true
				sorting.since = GetTime()
				return
			end
			sorting.done = sorting.done or {}
			sorting.done[pull.entry] = true
			sorting.pull = nil
		end

		if not sorting.warmed then
			sorting.warmed = true
			if WarmSplits() then
				sorting.warm = true
				sorting.wait = true
				sorting.since = GetTime()
				return
			end
		end

		if not sorting.pull and OC.CMD_TAKEONE and OC.CMD_DEPOSIT then
			local entry = NextSplit()
			local partial = entry and Partials(entry)[1]
			if partial and not CanTake(entry, partial.count or 0) then
				if not sorting.toldFull then
					sorting.toldFull = true
					OC.Print("Sort: need a free bag slot to stack open piles.")
				end
			elseif partial then
				local _, total = BagRows(entry)
				sorting.didPull = true
				sorting.pull = {
					entry = entry, phase = "out", taken = { [partial.index] = true },
					need = total + (partial.count or 0),
				}
				return SendWait("T" .. partial.index, OC.CMD_TAKEONE .. partial.index)
			end
		end

		if sorting.didPull and not sorting.laidOut then
			if Signature() == sorting.sig then
				sorting.chest = true
				sorting.wait = true
				sorting.since = GetTime()
				return
			end
			sorting.laidOut = true
		end

		local moves = PlanSort(OC.Lockbox.items, OC.Lockbox.capacity)
		local move = moves[1]
		if not move then return StopSort() end
		if sorting.moves >= sorting.limit then return StopSort("it was going round in circles") end
		local token = move.from .. "," .. move.to
		if sorting.last == token then return StopSort("a move was refused") end
		sorting.last = token
		sorting.moves = sorting.moves + 1
		sorting.wait = true
		sorting.since = GetTime()
		sorting.sig = Signature()
		sorting.pull = nil
		OC.Send(OC.CMD_MOVE .. token)
	end

	local function PullAdvance()
		if not sorting or not sorting.wait or sorting.warm then return end
		if not sorting.pull then
			if Signature() ~= sorting.sig then
				sorting.chest = nil
				sorting.laidOut = true
				sorting.wait = false
				sorting.last = nil
				SortStep()
			end
			return
		end
		local pull = sorting.pull
		local _, total, held = BagRows(pull.entry)
		local arrived = pull.phase == "hold" and held == total or pull.phase == "in" and held < (pull.bag or 0) or pull.phase ~= "in" and pull.phase ~= "hold" and total >= (pull.need or 0)
		if not arrived then return end
		sorting.wait = false
		sorting.last = nil
		SortStep()
	end

	local function StartSort()
		if not db.sort or sorting or not OC.Lockbox.IsOpen() or OC.Lockbox.readOnly then return end
		if boxBusy == "deposit" or boxBusy == "leave" then
			OC.Print(boxBusy == "leave" and "Leave one is still moving a stack." or "Deposit is still stacking items.")
			return
		end
		if GetCursorInfo and GetCursorInfo() then
			OC.Print("Sort: you are holding something.")
			return
		end
		boxBusy = "sort"
		sorting = {
			moves = 0, since = GetTime(), wait = false, sig = Signature(),
			limit = (OC.Lockbox.capacity or 24) * 3 + 70,
		}
		sorter:Show()
		sortButton:SetText("Stop")
		SortStep()
	end

	sortButton:SetScript("OnClick", function()
		if sorting then StopSort("you stopped it") else StartSort() end
	end)
	sortButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(sortButton, "ANCHOR_BOTTOM")
		GameTooltip:SetText(sorting and "Stop" or "Sort")
			GameTooltip:AddLine("Open stacks are taken out and put straight back, then the columns fill. Common on the left, rarer to the right.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sortButton:SetScript("OnLeave", GameTooltip_Hide)

	sorter:RegisterEvent("BAG_UPDATE")
	sorter:SetScript("OnEvent", function()
		PullAdvance()
	end)
	sorter:SetScript("OnUpdate", function()
		if not sorting then return end
		if not OC.Lockbox.IsOpen() then return StopSort(false) end
		if GetCursorInfo and GetCursorInfo() then return StopSort("you are holding something") end
		if sorting.warm and GetTime() - sorting.since > 0.4 then
			sorting.warm = nil
			sorting.wait = false
			SortStep()
			return
		end
		PullAdvance()
		if sorting and sorting.wait and GetTime() - sorting.since > 2 then
			StopSort("a move did not finish")
		end
	end)

	lockFrame:HookScript("OnHide", function()
		if sorting then StopSort(false) end
	end)

	hooksecurefunc(OC.Lockbox, "Render", function()
		if sorting and sorting.wait then PullAdvance() end
		SyncSortButton()
	end)

	refresh.sort = SyncSortButton
	SyncSortButton()
	return true
end

-- ʕ •ᴥ•ʔ✿ Shift-click a bag item to pour every stack of it in, and only when the open container already holds it. Wrapped so the chat link does not also fire ✿ ʕ •ᴥ•ʔ
local function InstallShift(OC)
	local modifiedClick = _G.ContainerFrameItemButton_OnModifiedClick
	if not (modifiedClick and OC.Lockbox and OC.Send and OC.CMD_DEPOSIT) then return false end

	local function SmartDeposit(button, mouseButton)
		if not db.deposit then return end
		if mouseButton and mouseButton ~= "LeftButton" then return end
		if not IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown() then return end
		local box = OC.Lockbox
		if not box.IsOpen() or box.readOnly then return end
		local parent = button and button.GetParent and button:GetParent()
		if not parent or not parent.GetID or not button.GetID then return end
		local bag, slot = parent:GetID(), button:GetID()
		if not bag or bag < 0 or bag > 4 then return end
		local entry = GetContainerItemID(bag, slot)
		if not ContainerHas(OC, entry) then return end
		local start = StackDeposit(OC)
		if not start then return end
		local quality = select(4, GetContainerItemInfo(bag, slot)) or 0
		start(DepositQueue(OC, entry, quality))
		return true
	end

	_G.ContainerFrameItemButton_OnModifiedClick = function(button, mouseButton)
		if SmartDeposit(button, mouseButton) then return end
		return modifiedClick(button, mouseButton)
	end
	return true
end

-- ʕ •ᴥ•ʔ✿ Alt-click a stack in the chest and one stays behind. The server only takes a whole square, so the stack leaves, one is split off, and that one goes back ✿ ʕ •ᴥ•ʔ
local function InstallLeave(OC)
	local slots = OC.Lockbox and OC.Lockbox.slots
	if not (slots and slots[1] and OC.Send and OC.CMD_TAKEONE and OC.CMD_DEPOSIT and OC.Lockbox.frame) then return false end

	local job
	local busy
	local waiter = CreateFrame("Frame")
	waiter:Hide()
	waiter:RegisterEvent("BAG_UPDATE")
	waiter:RegisterEvent("ITEM_LOCK_CHANGED")

	local function Tally(entry, quality)
		local same, any, empties, room = 0, 0, 0, 0
		local one, pile
		local cap = GetItemInfo and select(8, GetItemInfo(entry))
		entry, quality = tonumber(entry), quality or 0
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				local id = GetContainerItemID(b, s)
				if not id then
					empties = empties + 1
				elseif tonumber(id) == entry then
					local _, count, locked, q = GetContainerItemInfo(b, s)
					count = count or 0
					q = q or 0
					any = any + count
					if q == quality then
						same = same + count
						if cap and cap > 1 and count < cap then room = room + (cap - count) end
					end
					if not locked then
						local row = { bag = b, slot = s, count = count, quality = q }
						if count == 1 and (not one or (q == quality and one.quality ~= quality)) then one = row end
						if count > 1 and (not pile or (q == quality and pile.quality ~= quality)) then pile = row end
					end
				end
			end
		end
		return { same = same, any = any, empties = empties, room = room, cap = cap, one = one, pile = pile }
	end

	local function EmptiesNeeded(count, scan)
		local cap = scan.cap
		if cap and cap > 1 and scan.room >= count then return 1 end
		if not cap or cap <= 1 then return 2 end
		local spill = count - scan.room
		if spill < 0 then spill = 0 end
		return math.ceil(spill / cap) + 1
	end

	local function Stop(reason)
		if not job then return end
		if job.cursor and GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
		job = nil
		if boxBusy == "leave" then boxBusy = nil end
		waiter:Hide()
		if reason and reason ~= false then OC.Print("Leave one stopped: " .. reason .. ".") end
	end

	local function EmptySlot()
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				if not GetContainerItemID(b, s) then return b, s end
			end
		end
	end

	local function ChestLeft()
		local n = 0
		local items = OC.Lockbox.items or {}
		for i = 1, #items do
			local it = items[i]
			if it and it.index == job.index and tonumber(it.entry) == job.entry and not it.coin then
				n = n + (it.count or 0)
			end
		end
		return n
	end

	local function SendBack(row)
		job.phase = "back"
		job.since = GetTime()
		job.bag, job.slot = row.bag, row.slot
		job.cursor = nil
		OC.Send(OC.CMD_DEPOSIT .. row.bag .. "," .. row.slot)
	end

	local function Run()
		if not job then return end
		if not OC.Lockbox.IsOpen() then return Stop(false) end
		if job.pause then
			job.pause = nil
			return
		end
		if GetTime() - job.since > 5 then return Stop("a move did not finish") end

		local scan = Tally(job.entry, job.quality)
		local have = job.loose and scan.any or scan.same

		if job.phase == "out" then
			if ChestLeft() >= job.count then return end
			if scan.same >= job.sameBefore + job.count then
				job.want = job.sameBefore + job.count - 1
			elseif scan.any >= job.anyBefore + job.count then
				job.loose = true
				job.want = job.anyBefore + job.count - 1
				have = scan.any
			else
				return
			end
			job.phase = "return"
			job.since = GetTime()
		end

		if job.phase == "back" then
			if have <= job.want then Stop(false) end
			return
		end

		if job.phase == "cursor" then
			if not (GetCursorInfo and GetCursorInfo()) then return end
			local bag, slot = EmptySlot()
			if not bag or not PickupContainerItem then return end
			if InCombatLockdown and InCombatLockdown() then return Stop("you are in combat") end
			job.phase = "place"
			job.since = GetTime()
			job.bag, job.slot = bag, slot
			job.pause = true
			PickupContainerItem(bag, slot)
			return
		end

		if job.phase == "place" then
			if GetCursorInfo and GetCursorInfo() then return end
			local id = GetContainerItemID(job.bag, job.slot)
			local _, count, locked = GetContainerItemInfo(job.bag, job.slot)
			if tonumber(id) == job.entry and (count or 0) == 1 and not locked then
				job.cursor = nil
				SendBack({ bag = job.bag, slot = job.slot })
			end
			return
		end

		if have <= job.want then return Stop(false) end
		local one = scan.one
		if one and (job.loose or one.quality == job.quality) then return SendBack(one) end
		if InCombatLockdown and InCombatLockdown() then return Stop("you are in combat") end
		if job.phase == "return" and (not scan.pile or scan.empties < 1 or not SplitContainerItem) then return end
		if not scan.pile or not SplitContainerItem then return end
		if not job.loose and scan.pile.quality ~= job.quality then return end
		job.phase = "cursor"
		job.cursor = true
		job.pause = true
		job.since = GetTime()
		local ok = pcall(SplitContainerItem, scan.pile.bag, scan.pile.slot, 1)
		if not ok then
			job.cursor = nil
			job.phase = "return"
			Stop("could not split one off")
		end
	end

	local function Step()
		if busy or not job then return end
		busy = true
		Run()
		busy = false
	end

	waiter:SetScript("OnEvent", Step)
	waiter:SetScript("OnUpdate", Step)
	if OC.Lockbox.Render then
		hooksecurefunc(OC.Lockbox, "Render", function()
			if job then Step() end
		end)
	end
	OC.Lockbox.frame:HookScript("OnHide", function()
		if job then Stop(false) end
	end)

	local function LeaveClick(slot)
		if slot.ocPressDeposited then return end
		if GetCursorInfo and GetCursorInfo() then return end
		if not slot.index or slot.coin then return end
		if OC.Lockbox.readOnly then return end
		if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
		local count = tonumber(slot.count) or 0
		if count <= 1 then return end
		if job then return true end
		if boxBusy == "sort" then
			OC.Print("Sort is still running.")
			return true
		end
		if boxBusy == "deposit" then
			OC.Print("Deposit is still stacking items.")
			return true
		end
		local scan = Tally(slot.entry, slot.quality)
		if scan.empties < EmptiesNeeded(count, scan) then
			OC.Print("Leave one: need a free bag slot.")
			return true
		end
		job = {
			entry = tonumber(slot.entry), quality = slot.quality or 0, index = slot.index, count = count,
			sameBefore = scan.same, anyBefore = scan.any, phase = "out", since = GetTime(),
		}
		boxBusy = "leave"
		waiter:Show()
		OC.Send(OC.CMD_TAKEONE .. slot.index)
		return true
	end

	for i = 1, #slots do
		local slot = slots[i]
		local orig = slot:GetScript("OnClick")
		slot:SetScript("OnClick", function(self)
			if LeaveClick(self) then return end
			if orig then orig() end
		end)
		slot:HookScript("OnEnter", function(self)
			local count = tonumber(self.count) or 0
			if self.coin or count <= 1 or OC.Lockbox.readOnly or not GameTooltip:IsShown() then return end
			GameTooltip:AddLine("Alt-click to take all but one.", 0.65, 0.65, 0.65, true)
			GameTooltip:Show()
		end)
	end
	return true
end

-- ʕ ◕ᴥ◕ ʔ✿ Alt-click a material in the crafting window and the list opens on the recipe that makes it ✿ ʕ ◕ᴥ◕ ʔ
local function InstallRecipe(OC)
	local Builder = OC.Builder
	if not (Builder and Builder.Select and Builder.Render and Builder.IsCollapsed and Builder.ToggleCategory) then return false end

	local function Pick(entry)
		local list, entryId = {}, tonumber(entry)
		if not entryId or entryId == 0 then return end
		for _, recipe in ipairs(Builder.recipes or {}) do
			if not recipe.salvage and not recipe.coins then
				local made = tonumber(recipe.item or recipe.entry)
				if made == entryId then list[#list + 1] = recipe end
			end
		end
		if #list == 0 then return end
		for i = 1, #list do
			if (list[i].key or list[i].entry) == Builder.selected then
				return list[(i % #list) + 1]
			end
		end
		return list[1]
	end

	local function ScrollTo(recipe)
		local lines = Builder.lines or {}
		local key = recipe.key or recipe.entry
		local index
		for i = 1, #lines do
			local line = lines[i]
			if line.recipe and (line.recipe.key or line.recipe.entry) == key then
				index = i
				break
			end
		end
		local scroll = Builder.scrollFrame
		local bar = _G.OutlawCraftBuilderScrollScrollBar
		if not index or not scroll or not bar or not FauxScrollFrame_SetOffset then return end
		local rowH = 18
		local visible = math.floor((scroll:GetHeight() or rowH) / rowH + 0.5)
		if visible < 1 then visible = 1 end
		local offset = math.max(0, math.min(index - 1, #lines - visible))
		FauxScrollFrame_SetOffset(scroll, offset)
		bar:SetValue(offset * rowH)
	end

	local function ShowMade(entry, name)
		local recipe = Pick(entry)
		if not recipe then
			OC.Print("Nothing on your crafting list makes " .. ((name and name ~= "") and name or "that") .. ".")
			return
		end
		local search = _G.OutlawCraftBuilderSearch
		if search and search.GetText and search.SetText then
			local text = string.lower(strtrim(search:GetText() or ""))
			local recipeName = string.lower(recipe.name or "")
			if text ~= "" and not string.find(recipeName, text, 1, true) then search:SetText("") end
		end
		local category = recipe.category or 0
		if Builder.IsCollapsed(category) then Builder.ToggleCategory(category) end
		Builder.Select(recipe.key or recipe.entry)
		ScrollTo(recipe)
	end

	local hooked
	for k = 1, 8 do
		local slot = _G["OutlawCraftBuilderReagent" .. k]
		if slot then
			hooked = true
			slot:RegisterForClicks("LeftButtonUp")
			slot:SetScript("OnClick", function(self)
				if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
				if not self.entry then return end
				ShowMade(self.entry, self.plainName)
			end)
			slot:HookScript("OnEnter", function(self)
				if not self.entry or not GameTooltip:IsShown() or not Pick(self.entry) then return end
				GameTooltip:AddLine("Alt-click to show its recipe.", 0.65, 0.65, 0.65, true)
				GameTooltip:Show()
			end)
		end
	end
	return hooked
end

local function Attempt()
	local OC = _G.OutlawCraft
	if not OC then return false end
	EnsureDB()
	if not installed.craft then installed.craft = InstallCraft(OC) end
	if not installed.breakAll then installed.breakAll = InstallBreak(OC) end
	if not installed.deposit then installed.deposit = InstallDeposit(OC) end
	if not installed.sort then installed.sort = InstallSort(OC) end
	if not installed.shift then installed.shift = InstallShift(OC) end
	if not installed.leave then installed.leave = InstallLeave(OC) end
	if not installed.recipe then installed.recipe = InstallRecipe(OC) end
	return installed.craft and installed.breakAll and installed.deposit and installed.sort and installed.shift and installed.leave and installed.recipe
end

local waiter = CreateFrame("Frame")
waiter:Hide()
local waited, step = 0, 0
waiter:SetScript("OnUpdate", function(self, dt)
	step = step + dt
	waited = waited + dt
	if step < 0.25 then return end
	step = 0
	if Attempt() or waited > 20 then self:Hide() end
end)

local function Boot()
	EnsureDB()
	if not booted then
		booted = true
		RegisterSlash()
	end
	if not IsAddOnLoaded("OutlawCraft") then
		waiter:Hide()
		return
	end
	if Attempt() then
		waiter:Hide()
	elseif not waiter:IsShown() then
		waited = 0
		waiter:Show()
	end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(_, _, name)
	if name and name ~= "qtoutlawqol" and name ~= "OutlawCraft" then return end
	Boot()
end)
