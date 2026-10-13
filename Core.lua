local _G = _G
local ipairs = ipairs
local tostring = tostring
local GetContainerItemID = GetContainerItemID
local GetContainerNumSlots = GetContainerNumSlots
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local tinsert = table.insert

local db
local refresh = {}
local installed = {}
local booted

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

-- ʕ •ᴥ•ʔ✿ One click for the whole Break down list. Each piece is its own cast, so the next waits until that piece is gone ✿ ʕ •ᴥ•ʔ
local function InstallBreak(OC)
	local Builder, UI = OC.Builder, OC.UI
	if not (Builder and Builder.rows and Builder.Render and UI and UI.Button and OC.Send and OC.CMD_BREAK_DOWN) then return false end

	local BREAK_DOWN = 99
	local breakQueue, breakSent
	local breakAll = UI.Button(Builder.frame, "qtOutlawQoLBreakAll", "All", 36, 16)
	breakAll:Hide()

	local function SalvageByEntry(entry)
		for _, row in ipairs(Builder.salvage or {}) do
			if row.entry == entry then return row end
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
			if row.reason == 0 and (row.have or 0) > 0 then ready = ready + 1 end
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
			if row and row.reason == 0 and (row.have or 0) > 0 then
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
			if row and row.reason == 0 and have > 0 then
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
			if row.reason == 0 and (row.have or 0) > 0 then
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
		end
		GameTooltip:Show()
	end)
	breakAll:SetScript("OnLeave", GameTooltip_Hide)

	hooksecurefunc(Builder, "Render", function()
		AdvanceBreakQueue()
		UpdateBreakAll()
	end)
	refresh.breakAll = UpdateBreakAll
	UpdateBreakAll()
	return true
end

-- ʕ •ᴥ•ʔ✿ Shift-click Deposit All sends bag stacks the chest already holds. A plain click is still Deposit All ✿ ʕ •ᴥ•ʔ
local function InstallDeposit(OC)
	local depositAll = OC.Lockbox and OC.Lockbox.depositAllButton
	if not (depositAll and OC.Lockbox.DepositAll and OC.Send and OC.CMD_DEPOSIT) then return false end

	depositAll:SetScript("OnClick", function()
		if not db.deposit or not IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown() then
			OC.Lockbox.DepositAll()
			return
		end
		if OC.Lockbox.readOnly or not OC.Lockbox.IsOpen() then return end
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				local entry = GetContainerItemID(b, s)
				if ContainerHas(OC, entry) then
					OC.Send(OC.CMD_DEPOSIT .. b .. "," .. s)
				end
			end
		end
	end)
	depositAll:HookScript("OnEnter", function()
		GameTooltip:SetOwner(depositAll, "ANCHOR_TOP")
		GameTooltip:SetText("Deposit All")
		if db.deposit then
			GameTooltip:AddLine("Shift-click deposits only items already in the chest.", 1, 1, 1, true)
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

	local function SortStep()
		if not sorting or not db.sort then return end
		if not OC.Lockbox.IsOpen() then return StopSort(false) end
		if OC.Lockbox.readOnly then return StopSort(false) end
		if GetCursorInfo and GetCursorInfo() then return StopSort("you are holding something") end
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
		OC.Send(OC.CMD_MOVE .. token)
	end

	local function StartSort()
		if not db.sort or sorting or not OC.Lockbox.IsOpen() or OC.Lockbox.readOnly then return end
		if GetCursorInfo and GetCursorInfo() then
			OC.Print("Sort: you are holding something.")
			return
		end
		sorting = {
			moves = 0, since = GetTime(), wait = false, sig = Signature(),
			limit = (OC.Lockbox.capacity or 24) * 3 + 10,
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
		GameTooltip:AddLine("Columns fill downward. Common on the left, rarer to the right. Each item keeps its own column when there is room.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sortButton:SetScript("OnLeave", GameTooltip_Hide)

	sorter:SetScript("OnUpdate", function()
		if not sorting then return end
		if not OC.Lockbox.IsOpen() then return StopSort(false) end
		if GetCursorInfo and GetCursorInfo() then return StopSort("you are holding something") end
		if sorting.wait and GetTime() - sorting.since > 5 then
			StopSort("a move did not finish")
		end
	end)

	lockFrame:HookScript("OnHide", function()
		if sorting then StopSort(false) end
	end)

	hooksecurefunc(OC.Lockbox, "Render", function()
		if sorting and sorting.wait then
			local sig = Signature()
			if sig ~= sorting.sig then
				sorting.sig = sig
				sorting.wait = false
				SortStep()
			end
		end
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
		for b = 0, 4 do
			for s = 1, GetContainerNumSlots(b) or 0 do
				if GetContainerItemID(b, s) == entry then
					OC.Send(OC.CMD_DEPOSIT .. b .. "," .. s)
				end
			end
		end
		return true
	end

	_G.ContainerFrameItemButton_OnModifiedClick = function(button, mouseButton)
		if SmartDeposit(button, mouseButton) then return end
		return modifiedClick(button, mouseButton)
	end
	return true
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
	return installed.craft and installed.breakAll and installed.deposit and installed.sort and installed.shift
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
