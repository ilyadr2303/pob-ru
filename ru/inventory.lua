-- Path of Building RU: окно «Инвентарь» поверх вкладки «Предметы».
-- Слоты расположены как в игре; вместо картинок — название предмета цветом редкости,
-- гнёзда со связями, при наведении — обычная подсказка PoB и список камней в предмете.
-- Файлы PoB не изменяются: оборачивается только метод Draw у вкладки предметов открытого билда.
local ru, logErr = ...

local floor, min, max = math.floor, math.min, math.max

-- раскладка в клетках инвентаря (x, y, ширина, высота); поле 12 x 9.2
local LAYOUT = {
	["Weapon 1"]    = { 0,    0,   2, 4 },
	["Weapon 2"]    = { 10,   0,   2, 4 },
	["Helmet"]      = { 5,    0,   2, 2 },
	["Body Armour"] = { 5,    2.2, 2, 3 },
	["Amulet"]      = { 7.3,  2.2, 1, 1 },
	["Ring 3"]      = { 3.7,  2.2, 1, 1 },
	["Ring 1"]      = { 3.7,  3.4, 1, 1 },
	["Ring 2"]      = { 7.3,  3.4, 1, 1 },
	["Gloves"]      = { 2.4,  4.8, 2, 2 },
	["Boots"]       = { 7.6,  4.8, 2, 2 },
	["Belt"]        = { 5,    5.4, 2, 1 },
	["Graft 1"]     = { 0,    4.8, 2, 2 },
	["Graft 2"]     = { 10,   4.8, 2, 2 },
	["Flask 1"]     = { 3.5,  7.1, 1, 2 },
	["Flask 2"]     = { 4.5,  7.1, 1, 2 },
	["Flask 3"]     = { 5.5,  7.1, 1, 2 },
	["Flask 4"]     = { 6.5,  7.1, 1, 2 },
	["Flask 5"]     = { 7.5,  7.1, 1, 2 },
}
local ORDER = { "Weapon 1", "Weapon 2", "Helmet", "Body Armour", "Amulet", "Ring 1", "Ring 2", "Ring 3",
	"Gloves", "Boots", "Belt", "Graft 1", "Graft 2", "Flask 1", "Flask 2", "Flask 3", "Flask 4", "Flask 5" }
local GRID_W, GRID_H = 12, 9.2
local SOCKET_COL = {
	R = { 0.86, 0.25, 0.22 }, G = { 0.35, 0.78, 0.30 }, B = { 0.33, 0.50, 0.95 },
	W = { 0.92, 0.92, 0.92 }, A = { 0.55, 0.45, 0.35 },
}
local RARITY_RGB = {
	NORMAL = { 0.78, 0.78, 0.78 }, MAGIC = { 0.53, 0.53, 1 }, RARE = { 1, 1, 0.47 },
	UNIQUE = { 0.69, 0.38, 0.15 }, RELIC = { 0.38, 0.75, 0.38 },
}
local BTN_W, BTN_H = 190, 24

local function rect(x, y, w, h) DrawImage(nil, x, y, w, h) end

---------------------------------------------------------------------------
-- Картинки предметов: берутся с сайта игры (web.poecdn.com) при первом показе
-- и сохраняются в ru/icons; дальше работают без интернета.
---------------------------------------------------------------------------
local ICONS
do
	local f = loadfile("ru/data/icons.lua")
	local ok, t = pcall(f or function() return nil end)
	ICONS = (ok and type(t) == "table") and t or { base = { }, unique = { } }
end
local ICON_URL = "https://web.poecdn.com/image/Art/2DItems/"
local iconState, iconActive, iconDirOk = { }, 0, false
local DL_SCRIPT = [[
	local url, path, protocol, proxy = ...
	local curl = require("lcurl.safe")
	local f = io.open(path .. ".part", "wb")
	if not f then return false end
	local easy = curl.easy()
	easy:setopt_url(url)
	easy:setopt(curl.OPT_USERAGENT, "Path of Building RU")
	easy:setopt(curl.OPT_FOLLOWLOCATION, 1)
	if protocol then easy:setopt(curl.OPT_IPRESOLVE, protocol) end
	if proxy then easy:setopt(curl.OPT_PROXY, proxy) end
	easy:setopt_writefunction(function(data) f:write(data) return true end)
	local _, err = easy:perform()
	local code = easy:getinfo(curl.INFO_RESPONSE_CODE)
	easy:close()
	f:close()
	if err or code ~= 200 then os.remove(path .. ".part") return false end
	os.remove(path)
	return os.rename(path .. ".part", path) and true or false
]]
local function fileOk(path)
	local f = io.open(path, "rb")
	if not f then return false end
	local n = f:seek("end")
	f:close()
	return n and n > 100
end
-- общий механизм: файл есть -> загрузить; нет -> скачать в фоне (не больше 4 сразу)
local function ensureFile(st, url)
	if st.state == "need" and iconActive < 4 and ru.invIconsOff ~= true then
		local base = (GetScriptPath and GetScriptPath() or ".") .. "/"
		local id = LaunchSubScript(DL_SCRIPT, "", "", url, base .. st.file,
			launch.connectionProtocol, launch.proxyURL)
		if id then
			st.state = "loading"
			iconActive = iconActive + 1
			launch.subScripts[id] = { type = "CUSTOM", callback = function(ok)
				iconActive = iconActive - 1
				st.state = (ok and fileOk(st.file)) and "file" or "fail"
			end }
		else
			st.state = "fail"
		end
	end
	if st.state == "file" then
		local h = NewImageHandle()
		h:Load(st.file)
		st.handle = h
		st.state = "ready"
	end
	if st.state == "ready" then
		if not st.iw or st.iw == 0 then st.iw, st.ih = st.handle:ImageSize() end
		if st.iw and st.iw > 0 and st.ih and st.ih > 0 then return st end
	end
	return nil
end
local function iconFor(item)
	local art
	if item.rarity == "UNIQUE" or item.rarity == "RELIC" then art = item.title and ICONS.unique[item.title] end
	art = art or (item.baseName and ICONS.base[item.baseName])
	if not art then return nil end
	local st = iconState[art]
	if not st then
		if not iconDirOk then pcall(MakeDir, "ru/icons"); iconDirOk = true end
		st = { file = "ru/icons/" .. art:gsub("[/\\]", "_") .. ".png", sheet = art:sub(1, 7) == "Flasks/" }
		st.state = fileOk(st.file) and "file" or "need"
		iconState[art] = st
	end
	return ensureFile(st, ICON_URL .. art .. ".png")
end
local function drawIcon(st, x, y, w, h)
	local iw, ih = st.iw, st.ih
	local sheet = st.sheet and iw >= ih * 1.2 -- флаконы: три слоя в одном файле
	if sheet then iw = iw / 3 end
	local k = math.min((w - 8) / iw, (h - 8) / ih, 1.6)
	local dw, dh = math.floor(iw * k), math.floor(ih * k)
	local dx, dy = x + math.floor((w - dw) / 2), y + math.floor((h - dh) / 2)
	SetDrawColor(1, 1, 1)
	if sheet then
		DrawImage(st.handle, dx, dy, dw, dh, 2 / 3, 0, 1, 1) -- жидкость
		DrawImage(st.handle, dx, dy, dw, dh, 0, 0, 1 / 3, 1) -- склянка
	else
		DrawImage(st.handle, dx, dy, dw, dh)
	end
end
local function frame(x, y, w, h, t)
	rect(x, y, w, t); rect(x, y + h - t, w, t); rect(x, y, t, h); rect(x + w - t, y, t, h)
end
local function inside(cx, cy, x, y, w, h)
	return cx >= x and cx < x + w and cy >= y and cy < y + h
end

-- слот с учётом активного набора оружия
local function slotFor(itemsTab, name)
	if (name == "Weapon 1" or name == "Weapon 2") and itemsTab.activeItemSet and itemsTab.activeItemSet.useSecondWeaponSet then
		return itemsTab.slots[name .. " Swap"] or itemsTab.slots[name], name .. " Swap"
	end
	return itemsTab.slots[name], name
end

local function gemLines(build, slotName)
	local out = { }
	local st = build.skillsTab
	if not st or not st.socketGroupList then return out end
	for _, group in ipairs(st.socketGroupList) do
		if group.slot == slotName and group.gemList then
			for _, gem in ipairs(group.gemList) do
				local name = gem.nameSpec
				if name and name ~= "" then
					local off = (group.enabled == false or gem.enabled == false)
					out[#out + 1] = { (off and "^8" or (gem.color or "^7")) .. name,
						"  ^7" .. tostring(gem.level or "?") .. "/" .. tostring(gem.quality or 0) .. (off and "  ^8(выкл.)" or "") }
				end
			end
		end
	end
	return out
end

-- Гнёзда: спрайт с сайта игры (тот же, что в инвентаре персонажа и на трейде), 213x175, клетка 35 px.
-- Скачивается один раз в ru/img/poe_socket.png; пока его нет - свои запасные картинки.
-- Адрес спрайта в комплект не входит: он берётся из необязательного файла ru/socket_url.txt
-- (одна строка с адресом картинки гнёзд с сайта игры). Нет файла - рисуются запасные гнёзда.
local SOCK_URL
do
	local f = io.open("ru/socket_url.txt", "r")
	if f then
		local line = f:read("*l")
		f:close()
		if line and line:match("^https://web%.poecdn%.com/") then SOCK_URL = line:gsub("%s+$", "") end
	end
end
local SOCK_CELL = { R = { 140, 35 }, G = { 0, 105 }, B = { 70, 70 }, W = { 140, 70 }, A = { 35, 70 } }
local GEM_CELL = { R = { 70, 35 }, G = { 35, 35 }, B = { 0, 35 }, W = { 0, 70 } }
local SUP_CELL = { R = { 70, 140 }, G = { 0, 140 }, B = { 140, 105 }, W = { 105, 140 } }
local GEM_COL = { [1] = "R", [2] = "G", [3] = "B" }
-- камни предмета по порядку гнёзд: цвет камня и признак «камень поддержки»
local function slotGems(build, slotName)
	local out = { }
	local st = build.skillsTab
	if not st or not st.socketGroupList then return out end
	for _, group in ipairs(st.socketGroupList) do
		if group.slot == slotName and group.gemList then
			for _, gem in ipairs(group.gemList) do
				local ge = gem.grantedEffect or (gem.gemData and gem.gemData.grantedEffect)
				if ge then out[#out + 1] = { col = GEM_COL[ge.color] or "W", support = ge.support and true or false, gem = gem } end
			end
		end
	end
	return out
end
local sockSprite = { file = "ru/img/poe_socket.png" }
local sockImg
local function loadSockImg()
	sockImg = { }
	for _, n in ipairs({ "socket_R", "socket_G", "socket_B", "socket_W", "socket_A", "link_h", "link_v" }) do
		local ok, h = pcall(function()
			local h = NewImageHandle()
			h:Load("ru/img/" .. n .. ".png")
			return h
		end)
		if ok then sockImg[n] = h end
	end
end
local function spr(sp, cx, cy, cw, ch, x, y, w, h)
	DrawImage(sp.handle, x, y, w, h, cx / sp.iw, cy / sp.ih, (cx + cw) / sp.iw, (cy + ch) / sp.ih)
end
-- filled: сколько гнёзд занято камнями (в них рисуется камень цвета гнезда)
local function drawSockets(item, x, y, w, h, u, centre, filled)
	local socks = item.sockets
	if not socks or #socks == 0 then return end
	if not sockImg then loadSockImg() end
	if not sockSprite.state then
		if not iconDirOk then pcall(MakeDir, "ru/icons"); iconDirOk = true end
		pcall(MakeDir, "ru/img")
		sockSprite.state = fileOk(sockSprite.file) and "file" or "need"
	end
	local sp
	if SOCK_URL or sockSprite.state == "file" or sockSprite.state == "ready" then
		local okS, r = pcall(ensureFile, sockSprite, SOCK_URL or "")
		if okS then sp = r end
	end
	local n = #socks
	local s = max(16, floor(u * 0.45))
	local gap = max(3, floor(s * 0.34))
	local cols = (w < u * 1.5) and 1 or 2
	local rows = math.ceil(n / cols)
	if rows * s + (rows - 1) * gap > h - 6 then -- не влезает по высоте: уменьшить
		s = max(10, floor((h - 6) / (rows + (rows - 1) * 0.34)))
		gap = max(2, floor(s * 0.34))
	end
	local tw, th = cols * s + (cols - 1) * gap, rows * s + (rows - 1) * gap
	local ox, oy = floor(x + (w - tw) / 2), floor(centre and (y + (h - th) / 2) or (y + h - th - 6))
	local pos = { }
	for i = 1, n do
		local r = floor((i - 1) / cols)
		local c = (i - 1) % cols
		if cols == 2 and r % 2 == 1 then c = 1 - c end -- змейкой, как в игре
		pos[i] = { ox + c * (s + gap), oy + r * (s + gap) }
	end
	SetDrawColor(1, 1, 1)
	for i = 1, n do
		local col = socks[i].color
		if not (col == "R" or col == "G" or col == "B" or col == "A") then col = "W" end
		if sp then
			local c = SOCK_CELL[col]
			spr(sp, c[1], c[2], 35, 35, pos[i][1], pos[i][2], s, s)
			local gm = filled and filled[i]
			if gm and col ~= "A" then
				gm.x, gm.y, gm.s = pos[i][1], pos[i][2], s
				local g = (gm.support and SUP_CELL or GEM_CELL)[gm.col]
				if g then spr(sp, g[1], g[2], 35, 35, pos[i][1], pos[i][2], s, s) end
			end
		elseif sockImg["socket_" .. col] then
			DrawImage(sockImg["socket_" .. col], pos[i][1], pos[i][2], s, s)
		else
			local c = SOCKET_COL[col] or SOCKET_COL.W
			SetDrawColor(c[1], c[2], c[3]); rect(pos[i][1], pos[i][2], s, s); SetDrawColor(1, 1, 1)
		end
	end
	-- связи: на сайте 38x15 (горизонтальная) и 15x38 (вертикальная) при гнезде 35 px
	local k = s / 35
	local ll, lt = floor(38 * k), max(4, floor(15 * k))
	for i = 1, n - 1 do
		if socks[i].group == socks[i + 1].group then
			local a, b = pos[i], pos[i + 1]
			if a[2] == b[2] then
				local lx = floor((a[1] + b[1] + s - ll) / 2)
				local ly = a[2] + floor((s - lt) / 2)
				if sp then spr(sp, 175, 0, 38, 15, lx, ly, ll, lt)
				elseif sockImg.link_h then DrawImage(sockImg.link_h, lx, ly, ll, lt) end
			else
				local lx = a[1] + floor((s - lt) / 2)
				local ly = floor((a[2] + b[2] + s - ll) / 2)
				if sp then spr(sp, 175, 15, 15, 38, lx, ly, lt, ll)
				elseif sockImg.link_v then DrawImage(sockImg.link_v, lx, ly, lt, ll) end
			end
		end
	end
	return th + 8
end

-- обрезает строку по ширине (по целым символам UTF-8)
local function fitLine(line, fs, w)
	if DrawStringWidth(fs, "VAR", line) <= w then return line end
	local n = #line
	while n > 1 do
		n = n - 1
		while n > 1 and line:byte(n + 1) and line:byte(n + 1) >= 128 and line:byte(n + 1) < 192 do n = n - 1 end
		local cut = line:sub(1, n) .. ".."
		if DrawStringWidth(fs, "VAR", cut) <= w then return cut end
	end
	return line
end
-- parts: список { текст, цветовой код }; рисуется по центру блока, лишнее обрезается
local function drawName(parts, x, y, w, h, fs)
	local lines = { }
	for _, p in ipairs(parts) do
		for _, l in ipairs(main:WrapString(p[1], fs, w - 8)) do lines[#lines + 1] = { l, p[2] } end
	end
	local maxLines = max(1, floor(h / fs))
	local n = min(#lines, maxLines)
	local top = y + max(2, floor((h - n * fs) / 2))
	for i = 1, n do
		local line = fitLine(lines[i][1], fs, w - 6)
		DrawString(x + floor(w / 2), top + (i - 1) * fs, "CENTER_X", fs, "VAR", lines[i][2] .. line)
	end
end

-- подсказка с непрозрачной подложкой (стандартный фон подсказок PoB полупрозрачный)
local function drawTooltip(tt, x, y, w, h, viewPort)
	SetDrawLayer(nil, 100)
	local ok, ttW, ttH = pcall(tt.GetSize, tt)
	if ok and ttW and ttH and ttW > 0 then
		local tx, ty = x + w + 5, y
		if tx + ttW > viewPort.x + viewPort.width then
			tx = max(viewPort.x, x - 5 - ttW)
			if tx + ttW > x then ty = ty + h end
		end
		if ty + ttH > viewPort.y + viewPort.height then ty = max(viewPort.y, y + h - ttH) end
		SetDrawColor(0.02, 0.02, 0.03)
		rect(tx, ty, ttW, ttH)
		SetDrawColor(1, 1, 1)
	end
	tt:Draw(x, y, w, h, viewPort)
	SetDrawLayer(nil, 0)
end

local function drawInventory(self, viewPort, inputEvents)
	local build = self.build
	local vx, vy, vw, vh = viewPort.x, viewPort.y, viewPort.width, viewPort.height
	local cx, cy = GetCursorPos()
	local click, close
	for id, event in pairs(inputEvents) do
		if type(event) == "table" and event.type == "KeyDown" then
			if event.key == "LEFTBUTTON" then click = true
			elseif event.key == "ESCAPE" or (event.key == "b" and IsKeyDown("CTRL")) then close = true end
		end
		inputEvents[id] = nil
	end

	SetDrawLayer(nil, 0)
	SetDrawColor(0.04, 0.04, 0.05); rect(vx, vy, vw, vh)

	local jewels = { }
	if self.sockets and build.spec and build.spec.allocNodes then
		-- в том же порядке, что «Гнездо #N» в списке PoB (по возрастанию номера узла)
		local ids = { }
		for nodeId in pairs(self.sockets) do
			if build.spec.allocNodes[nodeId] then ids[#ids + 1] = nodeId end
		end
		table.sort(ids)
		for n, nodeId in ipairs(ids) do
			jewels[#jewels + 1] = { slot = self.sockets[nodeId], caption = "Д" .. n }
		end
	end
	for _, name in ipairs(ORDER) do
		local slot = slotFor(self, name)
		if slot and slot.abyssalSocketList then
			for i, ab in ipairs(slot.abyssalSocketList) do
				if not ab.inactive and (ab.selItemId or 0) ~= 0 then
					jewels[#jewels + 1] = { slot = ab, caption = "Б" .. i }
				end
			end
		end
	end
	local jCols = GRID_W
	local jRows = math.ceil(#jewels / jCols)
	local head = 40
	local gridH = GRID_H + (jRows > 0 and (jRows + 0.5) or 0)
	local u = floor(min((vh - head - 24) / gridH, (vw - 40) / GRID_W))
	u = max(36, min(u, 96))
	local pw, ph = GRID_W * u, GRID_H * u
	local px = vx + floor((vw - pw) / 2)
	if vw > pw + 700 then px = vx + floor(vw * 0.08) end -- оставить справа место под подсказку
	local py = vy + head

	SetDrawColor(1, 1, 1)
	DrawString(px, vy + 10, "LEFT", 20, "VAR", "^7Инвентарь"
		.. ((self.activeItemSet and self.activeItemSet.useSecondWeaponSet) and "  ^8(набор оружия II)" or ""))

	-- кнопка «К списку»
	local bx, by = px + pw - BTN_W, vy + 8
	local overBtn = inside(cx, cy, bx, by, BTN_W, BTN_H)
	SetDrawColor(0.5, 0.5, 0.5); rect(bx, by, BTN_W, BTN_H)
	SetDrawColor(overBtn and 0.25 or 0.1, overBtn and 0.25 or 0.1, overBtn and 0.25 or 0.1); rect(bx + 1, by + 1, BTN_W - 2, BTN_H - 2)
	SetDrawColor(1, 1, 1)
	DrawString(bx + floor(BTN_W / 2), by + 4, "CENTER_X", 16, "VAR", "^7К списку (Ctrl+B)")
	if (click and overBtn) or close then ru.invOpen = false; return end

	local hover, hoverGem
	local function drawSlot(slot, slotName, label, x, y, w, h, tall, caption)
		local item = slot.selItemId and slot.selItemId ~= 0 and self.items[slot.selItemId] or nil
		local over = inside(cx, cy, x, y, w, h)
		local rc = item and (RARITY_RGB[item.rarity] or RARITY_RGB.NORMAL) or { 0.25, 0.25, 0.28 }
		SetDrawColor(rc[1] * (over and 1 or 0.7), rc[2] * (over and 1 or 0.7), rc[3] * (over and 1 or 0.7))
		rect(x, y, w, h)
		if item then SetDrawColor(0.07, 0.07, 0.16) else SetDrawColor(0.07, 0.07, 0.08) end
		rect(x + 2, y + 2, w - 4, h - 4)
		SetDrawColor(1, 1, 1)
		local fs = (u >= 70 and w >= u * 1.5) and 14 or 12
		if item then
			local okI, icon = pcall(iconFor, item)
			if not okI then logErr("icon: " .. tostring(icon)); icon = nil end
			if icon then drawIcon(icon, x, y, w, h) end
			local sh = 0
			if not caption then
				local gems = slotGems(build, slotName)
				sh = drawSockets(item, x, y, w, h, u, icon ~= nil, gems) or 0
				for _, gm in ipairs(gems) do
					if gm.x and gm.gem.gemData and inside(cx, cy, gm.x, gm.y, gm.s, gm.s) then hoverGem = gm end
				end
			end
			SetDrawColor(1, 1, 1)
			if not icon then
				local rcode = colorCodes[item.rarity] or "^7"
				local parts = { }
				local title = item.title
				if title and title ~= "" and title ~= "New Item" then parts[1] = { title, rcode } end
				local base = item.baseName or item.name
				if base and base ~= "" and (#parts == 0 or item.rarity ~= "UNIQUE" or tall) then
					parts[#parts + 1] = { base, #parts == 0 and rcode or "^8" }
				end
				if #parts == 0 then parts[1] = { item.name or "?", rcode } end
				drawName(parts, x, y + 2, w, h - sh - 4, fs)
			end
			if over then hover = { item = item, slot = slot, slotName = slotName, x = x, y = y, w = w, h = h } end
		else
			drawName({ { label, "^8" } }, x, y + 2, w, h - 4, fs)
		end
		if caption then
			SetDrawColor(0, 0, 0, 0.75); rect(x + 2, y + 2, DrawStringWidth(12, "VAR", caption) + 6, 14)
			SetDrawColor(1, 1, 1)
			DrawString(x + 5, y + 3, "LEFT", 12, "VAR", "^7" .. caption)
		end
	end
	for _, name in ipairs(ORDER) do
		local slot, slotName = slotFor(self, name)
		local L = LAYOUT[name]
		if slot and L and (name:sub(1, 5) ~= "Graft" or (slot.selItemId or 0) ~= 0 or slot:IsShown())
			and (name ~= "Ring 3" or (slot.selItemId or 0) ~= 0 or slot:IsShown()) then
			drawSlot(slot, slotName, slot.label or name, px + floor(L[1] * u), py + floor(L[2] * u),
				floor(L[3] * u) - 4, floor(L[4] * u) - 4, L[4] >= 2)
		end
	end

	-- самоцветы: гнёзда дерева и гнёзда Бездны в предметах
	if #jewels > 0 then
		local jy = py + ph + 8
		SetDrawColor(1, 1, 1)
		DrawString(px, jy, "LEFT", 16, "VAR", "^7Самоцветы:  ^8Д - гнездо дерева, Б - гнездо Бездны в предмете")
		jy = jy + 22
		for i, j in ipairs(jewels) do
			local col = (i - 1) % jCols
			local row = floor((i - 1) / jCols)
			drawSlot(j.slot, j.slot.slotName, j.caption, px + col * u, jy + row * u, u - 4, u - 4, false, j.caption)
		end
		ph = ph + 30 + jRows * u
	end

	SetDrawColor(1, 1, 1)
	DrawString(px, py + ph + 2, "LEFT", 14, "VAR",
		"^8Наведите курсор на предмет - подсказка PoB и камни в нём; на гнездо - подсказка камня.")

	if hoverGem then
		local okG, GT = pcall(require, "Classes.GemTooltip")
		if okG and type(GT) == "table" and GT.AddGemTooltip then
			local tt = ru.invGemTooltip
			if not tt then tt = new("Tooltip"):Tooltip(); ru.invGemTooltip = tt end
			if tt:CheckForUpdate(hoverGem.gem, build.outputRevision) then
				local okT, errT = pcall(GT.AddGemTooltip, tt, build, hoverGem.gem)
				if not okT then logErr("gem tooltip: " .. tostring(errT)) end
			end
			drawTooltip(tt, hoverGem.x, hoverGem.y, hoverGem.s, hoverGem.s, viewPort)
			hover = nil
		end
	end
	if hover then
		local tt = ru.invTooltip
		if not tt then tt = new("Tooltip"):Tooltip(); ru.invTooltip = tt end
		if tt:CheckForUpdate(hover.item, hover.slotName, build.outputRevision, launch.devModeAlt) then
			self:AddItemTooltip(tt, hover.item, hover.slot)
			local gems = gemLines(build, hover.slotName)
			if #gems > 0 then
				tt:AddSeparator(10)
				tt:AddLine(16, "^7Камни в предмете (уровень/качество):")
				for _, g in ipairs(gems) do tt:AddLine(16, g[1] .. g[2]) end
			end
		end
		drawTooltip(tt, hover.x, hover.y, hover.w, hover.h, viewPort)
	end
end

local function drawOpenButton(self, viewPort, inputEvents)
	local bx = viewPort.x + viewPort.width - BTN_W - 26
	local by = viewPort.y + viewPort.height - BTN_H - 24
	local cx, cy = GetCursorPos()
	local over = inside(cx, cy, bx, by, BTN_W, BTN_H)
	local open
	for id, event in pairs(inputEvents) do
		if type(event) == "table" and event.type == "KeyDown" then
			if event.key == "LEFTBUTTON" and over then open = true; inputEvents[id] = nil
			elseif event.key == "b" and IsKeyDown("CTRL") then open = true; inputEvents[id] = nil end
		end
	end
	return bx, by, over, open
end

local function hook(itemsTab)
	local orig = itemsTab.Draw
	itemsTab.ruInvHooked = true
	itemsTab.Draw = function(self, viewPort, inputEvents)
		if ru.enabled and ru.invOpen then
			local ok, err = pcall(drawInventory, self, viewPort, inputEvents)
			if ok then return end
			logErr("inventory: " .. tostring(err))
			ru.invOpen = false
			SetDrawLayer(nil, 0)
		end
		if not ru.enabled then return orig(self, viewPort, inputEvents) end
		local ok, bx, by, over, open = pcall(drawOpenButton, self, viewPort, inputEvents)
		if ok and open then ru.invOpen = true end
		orig(self, viewPort, inputEvents)
		if ok then
			SetDrawLayer(nil, 20)
			SetDrawColor(0.75, 0.62, 0.30); rect(bx, by, BTN_W, BTN_H)
			local c = over and 0.28 or 0.12
			SetDrawColor(c, c, c); rect(bx + 1, by + 1, BTN_W - 2, BTN_H - 2)
			SetDrawColor(1, 1, 1)
			DrawString(bx + floor(BTN_W / 2), by + 4, "CENTER_X", 16, "VAR", "^7Инвентарь (Ctrl+B)")
			SetDrawLayer(nil, 0)
		end
	end
end

-- вызывается каждый кадр: вкладка предметов создаётся заново при открытии каждого билда
return function()
	if type(main) ~= "table" or main.mode ~= "BUILD" or not main.modes then return end
	local build = main.modes["BUILD"]
	local it = build and build.itemsTab
	if build and build.viewMode ~= "ITEMS" then ru.invOpen = false end
	-- кнопка-вкладка «Инвентарь» в ряду режимов (рядом с «Сравнить»)
	local bc = build and build.controls
	if bc and bc.modeCompare and bc.modeItems and not bc.modeInventory and not ru.invBtnFailed then
		local ok, btn = pcall(function()
			return new("ButtonControl"):ButtonControl({ "LEFT", bc.modeCompare, "RIGHT" }, { 4, 0, 84, 20 }, "Инвентарь", function()
				build.viewMode = "ITEMS"
				ru.invOpen = true
			end)
		end)
		if ok and btn then
			btn.locked = function() return build.viewMode == "ITEMS" and ru.invOpen end
			bc.modeInventory = btn
			local itemsBtn = bc.modeItems
			local origClick = itemsBtn.onClick
			itemsBtn.onClick = function(...) ru.invOpen = false; return origClick(...) end
			itemsBtn.locked = function() return build.viewMode == "ITEMS" and not ru.invOpen end
		else
			ru.invBtnFailed = true
			logErr("inventory tab button: " .. tostring(btn))
		end
	end
	if it and not rawget(it, "ruInvHooked") and type(it.Draw) == "function" and it.slots then
		hook(it)
	end
end
