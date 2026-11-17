-- PoB RU: русификатор Path of Building (PoE 1)
-- Ничего не меняет в файлах PoB: перевод подставляется только при выводе текста на экран.
-- Внутри программы все названия остаются английскими, поэтому расчёты, импорт и сохранения не затрагиваются.

local ru = { enabled = true, noTr = false, version = "0.4" }
_G.PoBRU = ru

local BASE = "ru/"
local sfind, ssub, sbyte, sgsub, smatch, schar = string.find, string.sub, string.byte, string.gsub, string.match, string.char
local floor, ceil, max = math.floor, math.ceil, math.max
local concat = table.concat

local nDrawString, nWidth, nCursor = DrawString, DrawStringWidth, DrawStringCursorIndex
local nDrawImage, nSetColor = DrawImage, SetDrawColor
local nScale = GetScreenScale or function() return 1 end
local nScreenSize = GetScreenSize

local function logErr(msg)
	local f = io.open(BASE .. "error.log", "a")
	if f then
		f:write(os.date("%Y-%m-%d %H:%M:%S "), tostring(msg), "\n")
		f:close()
	end
end
ru.logErr = logErr

local function loadTable(name)
	local f, err = loadfile(BASE .. name)
	if not f then
		logErr("load " .. name .. ": " .. tostring(err))
		return { }
	end
	local ok, t = pcall(f)
	if not ok or type(t) ~= "table" then
		logErr("run " .. name .. ": " .. tostring(t))
		return { }
	end
	return t
end

---------------------------------------------------------------------------
-- Словари
---------------------------------------------------------------------------
local D = loadTable("data/names.lua")       -- точные строки: названия из клиента игры
local T = { }                                -- шаблоны с числами: "+# to maximum Life"
for i = 1, 16 do
	local f = io.open(BASE .. "data/stats_" .. i .. ".lua", "r")
	if not f then break end
	f:close()
	for k, v in pairs(loadTable("data/stats_" .. i .. ".lua")) do
		T[k] = v
	end
end
-- Интерфейс PoB (перекрывает игровые названия при совпадении)
local W = { }                                -- шаблоны с произвольной вставкой: "Removing this item from * will give you"
local function addWild(k, v)
	local kinds, n = { }, 0
	local pat = sgsub(k, "[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0")
	local last = #k > 0 and ssub(k, -1) == "*"
	pat = sgsub(pat, "[#%*]", function(c)
		n = n + 1; kinds[n] = c
		return c == "#" and "(%d[%d,%.]*)" or "(.-)"
	end)
	if last then pat = ssub(pat, 1, -5) .. "(.+)" end
	local head = smatch(k, "^([^%*]*)") or ""
	local word = smatch(head, "(%a%a+)") or "*"
	W[word] = W[word] or { }
	table.insert(W[word], { "^" .. pat .. "$", v, kinds })
end
local function addUI(t)
	for k, v in pairs(t) do
		if sfind(k, "*", 1, true) then
			addWild(k, v)
		elseif sfind(k, "#", 1, true) then
			local n = 0
			if not sfind(v, "\1", 1, true) then
				v = sgsub(v, "#", function() n = n + 1; return "\1" .. schar(48 + n) end)
			end
			T[k] = v
		else
			D[k] = v
		end
	end
end
addUI(loadTable("dict_ui.lua"))
local function sortWild()
	for _, list in pairs(W) do
		table.sort(list, function(a, b) return #a[1] > #b[1] end)
	end
end
do -- необязательный пользовательский словарь, не затирается при обновлении русификатора
	local f = io.open(BASE .. "dict_user.lua", "r")
	if f then f:close(); addUI(loadTable("dict_user.lua")) end
end
-- запасной поиск без учёта регистра (в PoB регистр букв иногда отличается от игрового)
local TL = { }
for k, v in pairs(T) do
	local lk = k:lower()
	if lk ~= k and TL[lk] == nil then TL[lk] = v end
end
sortWild()
ru.D, ru.T = D, T

---------------------------------------------------------------------------
-- Перевод строки
---------------------------------------------------------------------------
local function normNums(s)
	-- заменяет числа и диапазоны вида (10-15) на "#", возвращает ключ и список чисел
	local nums, n, out, on, pos, len = { }, 0, { }, 0, 1, #s
	while pos <= len do
		local st = sfind(s, "[%(%d]", pos)
		if not st then break end
		local tok
		if sbyte(s, st) == 40 then
			tok = smatch(s, "^%(%-?%d[%d%.]*%-%-?%d[%d%.]*%)", st)
			if not tok then
				on = on + 1; out[on] = ssub(s, pos, st); pos = st + 1
			end
		else
			tok = smatch(s, "^%d[%d,%.]*", st)
			tok = smatch(tok, "^(.-%d)[,%.]*$") or tok
		end
		if tok then
			on = on + 1; out[on] = ssub(s, pos, st - 1)
			on = on + 1; out[on] = "#"
			n = n + 1; nums[n] = tok
			pos = st + #tok
		end
	end
	on = on + 1; out[on] = ssub(s, pos)
	return concat(out), nums
end

local trChunk
local function trWildList(list, core)
	for i = 1, #list do
		local e = list[i]
		local caps = { smatch(core, e[1]) }
		if caps[1] then
			local kinds, ni, wi, nums, wilds = e[3], 0, 0, { }, { }
			for j = 1, #kinds do
				if kinds[j] == "#" then ni = ni + 1; nums[ni] = caps[j]
				else wi = wi + 1; wilds[wi] = caps[j] end
			end
			ni, wi = 0, 0
			return (sgsub(e[2], "[#%*]", function(c)
				if c == "#" then ni = ni + 1; return nums[ni] or "" end
				wi = wi + 1
				local cap = wilds[wi] or ""
				return D["@" .. cap] or trChunk(cap, 2) or cap
			end))
		end
	end
end
local function trWild(core)
	local word = smatch(core, "(%a%a+)")
	local list = word and W[word]
	local v = list and trWildList(list, core)
	if not v and W["*"] then v = trWildList(W["*"], core) end
	return v
end

local function trCore(core, noWild)
	local v = D[core]
	if v then return v end
	if ssub(core, 1, 5) == "Vaal " then
		v = D[ssub(core, 6)]
		if v then return v .. " ваал" end
	end
	if sfind(core, "%d") then
		local key, nums = normNums(core)
		v = T[key] or TL[key:lower()]
		if v then
			return (sgsub(v, "\1(.)", function(c) return nums[sbyte(c) - 48] or "" end))
		end
	else
		v = T[core] or TL[core:lower()]
		if v then return v end
	end
	if not noWild and #core < 400 then return trWild(core) end
end

function trChunk(chunk, depth)
	local pre, core, post = smatch(chunk, "^(%s*)(.-)(%s*)$")
	if core == "" or not sfind(core, "%a") then return nil end
	local v = trCore(core, true)
	if not v then
		local c2, p2 = smatch(core, "^(.-)(%s*[:%.%?!]+)$")
		if c2 and c2 ~= "" then
			v = trCore(c2, true)
			if v then v = v .. p2 end
		end
	end
	if not v and #core < 400 then
		v = trWild(core)
		if not v then
			local c2, p2 = smatch(core, "^(.-)(%s*[:%.%?!]+)$")
			if c2 and c2 ~= "" then
				v = trWild(c2)
				if v then v = v .. p2 end
			end
		end
	end
	depth = depth or 0
	if not v and depth < 3 then
		local a, sep, b = smatch(core, "^(.-)(:%s+)(.+)$")
		if a and a ~= "" then
			local ta, tb = trCore(a), trChunk(b, depth + 1)
			if ta or tb then v = (ta or a) .. sep .. (tb or b) end
		end
	end
	if not v and depth < 3 then
		local a, b = smatch(core, "^(.-) %((.+)%)$")
		if a and a ~= "" then
			local ta, tb = trChunk(a, depth + 1), trChunk(b, depth + 1)
			if ta or tb then v = (ta or a) .. " (" .. (tb or b) .. ")" end
		end
	end
	if not v and depth < 3 then
		-- строки разницы параметров: "+0.09 Cast Rate (+5.2%)", "-4% Chaos Res. Over Max"
		local num, rest = smatch(core, "^([%+%-]%d[%d,%.]*%%?) (.+)$")
		if num then
			local tr2 = trChunk(rest, depth + 1)
			if tr2 then v = num .. " " .. tr2 end
		end
	end
	if not v and depth < 3 and sfind(core, "; ", 1, true) and #core < 200 then
		-- составные названия: "Glorious Vanity 7365; 86; Mind Over Matter"
		local parts, n, any = { }, 0, false
		for part in (core .. "; "):gmatch("(.-); ") do
			local tp = trCore(part)
			if not tp then
				local name, num = smatch(part, "^(.-) (%d+)$")
				local tn = name and trCore(name)
				if tn then tp = tn .. " " .. num end
			end
			if tp then any = true end
			n = n + 1; parts[n] = tp or part
		end
		if any then v = concat(parts, "; ") end
	end
	if not v and sfind(core, ", ", 1, true) and #core < 200 then
		-- список через запятую («Название, База»): переводим известные элементы
		local parts, n, any = { }, 0, false
		for part in (core .. ", "):gmatch("(.-), ") do
			local tp = trCore(part, true)
			if tp then any = true end
			n = n + 1; parts[n] = tp or part
		end
		if any and n > 1 then v = concat(parts, ", ") end
	end
	if not v and depth < 3 and #core < 120 then
		-- подписи вида «A + B» и «A/B»: только если переводятся все части
		for _, sep in ipairs({ " + ", " / ", "/" }) do
			if not v and sfind(core, sep, 1, true) then
				local parts, n, all = { }, 0, true
				for part in (core .. sep):gmatch("(.-)" .. sgsub(sep, "%p", "%%%0")) do
					local tp = part ~= "" and trCore(part, true)
					if not tp then all = false; break end
					n = n + 1; parts[n] = tp
				end
				if all and n > 1 then v = concat(parts, sep) end
			end
		end
	end
	return v and (pre .. v .. post)
end

-- длина цветового кода (^7 / ^xRRGGBB) в позиции s или 0
local function escLen(text, s)
	local c = sbyte(text, s + 1)
	if c and c >= 48 and c <= 57 then return 2 end
	if (c == 120 or c == 88) and sfind(text, "^%x%x%x%x%x%x", s + 2) then return 8 end
	return 0
end

-- перевод одной строки (без переводов строки): по кускам между цветовыми кодами;
-- если куски не переводятся, а строка целиком известна — берём её целиком с первым цветом
local function trLine(line)
	local out, n, changed, missed, nesc, pos, len = { }, 0, false, false, 0, 1, #line
	local firstEsc
	while pos <= len do
		local s, e
		local from = pos
		while true do
			s = sfind(line, "^", from, true)
			if not s then break end
			local l = escLen(line, s)
			if l > 0 then e = s + l - 1; break end
			from = s + 1
		end
		local chunk = ssub(line, pos, (s or len + 1) - 1)
		if chunk ~= "" then
			local t = trChunk(chunk)
			if t then changed = true; chunk = t
			elseif sfind(chunk, "%a%a%a") then missed = true end
			n = n + 1; out[n] = chunk
		end
		if not s then break end
		nesc = nesc + 1
		if n == 0 and not firstEsc then firstEsc = ssub(line, s, e) end
		n = n + 1; out[n] = ssub(line, s, e)
		pos = e + 1
	end
	if missed and nesc > 0 then
		local plain = sgsub(sgsub(line, "%^[xX]%x%x%x%x%x%x", ""), "%^%d", "")
		local whole = trChunk(plain)
		if whole then return (firstEsc or "") .. whole end
	end
	if changed then return concat(out) end
end

-- Многострочные свойства: первая строка переводится первой частью русского текста,
-- следующие строки — только сразу после неё (в её контексте). Строки никогда не скрываются.
local MM = loadTable("data/multi.lua")
local mparsed, noMulti, noMultiN, cur = { }, { }, 0, nil
local function substNums(v, nums)
	return (sgsub(v, "\1(.)", function(c) return nums[sbyte(c) - 48] or "" end))
end
local function trMulti(text)
	if #text > 400 then cur = nil; return nil end
	-- уже переведённый текст (замеры при переносе строк) не сбрасывает контекст
	if sfind(text, "[\208\209]") then return nil end
	local plain, lead = text, ""
	if sfind(text, "^", 1, true) then
		while sbyte(plain, 1) == 94 do
			local l = escLen(plain, 1)
			if l == 0 then break end
			lead = lead .. ssub(plain, 1, l)
			plain = ssub(plain, l + 1)
		end
		plain = sgsub(sgsub(plain, "%^[xX]%x%x%x%x%x%x", ""), "%^%d", "")
	end
	local pre, core, post = smatch(plain, "^(%s*)(.-)(%s*)$")
	if core == "" then return nil end
	local key, nums = core, nil
	if sfind(core, "%d") then key, nums = normNums(core) end
	if cur then
		local e = cur.expect[key]
		if e then
			cur.nums[e[2]] = nums or { }
			local all, n = { }, 0
			for i = 1, e[2] do
				local t = cur.nums[i]
				if t then for j = 1, #t do n = n + 1; all[n] = t[j] end end
			end
			return lead .. pre .. substNums(e[1], all) .. post
		end
		if core ~= cur.first then cur = nil end
	end
	local mv = MM[key]
	if not mv then
		if not cur then
			if noMultiN > 60000 then noMulti = { }; noMultiN = 0 end
			noMulti[text] = true; noMultiN = noMultiN + 1
		end
		return nil
	end
	local entry = mparsed[key]
	if not entry then
		local piece = smatch(mv, "^([^\2]*)")
		local expect = { }
		for ck, cp, ci in mv:gmatch("\2([^\3]*)\3([^\4]*)\4(%d+)") do
			expect[ck] = { cp, tonumber(ci) }
		end
		entry = { piece, expect }
		mparsed[key] = entry
	end
	cur = { first = core, expect = entry[2], nums = { nums or { } } }
	return lead .. pre .. substNums(entry[1], nums or { }) .. post
end

local cache, cacheN = { }, 0
-- дружелюбная подсказка вместо сухой пометки о неподдерживаемом свойстве
local NS_MARK = "(Not supported in PoB yet)"
local NS_OPT = {
	{ "endurance charge", "Do you use Endurance Charges?", "useEnduranceCharges" },
	{ "frenzy charge", "Do you use Frenzy Charges?", "useFrenzyCharges" },
	{ "power charge", "Do you use Power Charges?", "usePowerCharges" },
	{ "onslaught", "Do you have Onslaught?", "buffOnslaught" },
	{ "arcane surge", "Do you have Arcane Surge?", "buffArcaneSurge" },
}
local NS_KEY = " Ctrl+G - перейти туда.)"
local tr
local function nsTarget(var, specific)
	-- точная цель не затирается общей, если обе строки из одной подсказки
	local now = GetTime and GetTime() or 0
	if specific or not ru.nsSpecific or now - (ru.nsSetT or 0) > 100 then
		ru.nsVar, ru.nsSpecific, ru.nsSetT = var, specific, now
	end
end
local function nsHint(head)
	local l = string.lower(head)
	local gain = sfind(l, "gain", 1, true) or sfind(l, "grant", 1, true) or sfind(l, "lose", 1, true) or sfind(l, "steal", 1, true)
	if gain and not sfind(l, "flask", 1, true) then
		for _, o in ipairs(NS_OPT) do
			if sfind(l, o[1], 1, true) then
				nsTarget(o[3], true)
				return "(PoB не считает, когда это срабатывает. Включите сами: вкладка «" .. tr("Configuration")
					.. "» > раздел «" .. tr("When In Combat") .. "» > «" .. tr(o[2]) .. "»." .. NS_KEY
			end
		end
		if sfind(l, "charge", 1, true) then
			nsTarget("usePowerCharges", true)
			return "(PoB не считает набор зарядов. Включите нужные заряды: вкладка «" .. tr("Configuration")
				.. "» > раздел «" .. tr("When In Combat") .. "»." .. NS_KEY
		end
	end
	nsTarget(nil, false)
	return "(PoB это не считает. Если влияет на цифры, задайте вручную: вкладка «" .. tr("Configuration")
		.. "» > раздел «" .. tr("Custom Modifiers") .. "»." .. NS_KEY
end
local function trNS(text, p)
	local head = ssub(text, 1, p - 1)
	local tail = ssub(text, p + #NS_MARK)
	return tr(head) .. nsHint(head) .. (tail ~= "" and tr(tail) or "")
end
tr = function(text)
	if ru.noTr or not ru.enabled then return text end
	if #text < 600 then
		local p = sfind(text, NS_MARK, 1, true)
		if p and p > 6 and not D[text] and ssub(text, 1, 5) ~= "Show " and not sfind(text, "\n", 1, true) then return trNS(text, p) end
	end
	if (cur or not noMulti[text]) and not sfind(text, "\n", 1, true) then
		local r = trMulti(text)
		if r then return r end
	end
	local hit = cache[text]
	if hit ~= nil then return hit or text end
	local res = false
	local len = #text
	if len > 0 and len < 6000 and sfind(text, "%a") then
		local v = D[text]
		if v then
			res = v
		elseif not sfind(text, "\n", 1, true) then
			res = trLine(text) or false
		else
			local out, n, changed = { }, 0, false
			for line in (text .. "\n"):gmatch("(.-)\n") do
				local t = line ~= "" and trLine(line)
				if t then changed = true; line = t end
				n = n + 1; out[n] = line
			end
			if changed then res = concat(out, "\n") end
		end
	end
	if cacheN > 40000 then cache = { }; cacheN = 0 end
	cache[text] = res
	cacheN = cacheN + 1
	return res or text
end
ru.tr = tr

---------------------------------------------------------------------------
-- Вывод кириллицы: буквы рисуются из собственных атласов через DrawImage
---------------------------------------------------------------------------
local M = loadTable("fonts/metrics.lua")
local HLIST = { 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 40, 48, 56, 64 }
local HMAP = { }
do
	local maxH = HLIST[#HLIST]
	for h = 0, maxH do HMAP[h] = 1 end
	for i, gh in ipairs(HLIST) do
		for h = gh, maxH do HMAP[h] = i end
		if i > 1 then
			local lim = floor((gh - HLIST[i - 1] - 1) / 2)
			for b = 0, lim - 1 do HMAP[gh - b - 1] = i end
		end
	end
end
local SUPPORTED = { }
if M["VAR"] then
	for cp in pairs(M["VAR"].heights[16] or { }) do SUPPORTED[cp] = true end
end
local haveFonts = next(SUPPORTED) ~= nil

local function fontFor(font)
	local f = M[font] or M["VAR"]
	if f and f.tex == nil then
		local ok, h = pcall(function()
			local h = NewImageHandle()
			h:Load(BASE .. "fonts/" .. f.file, "CLAMP")
			return h
		end)
		if ok and h then
			f.tex = h
		else
			f.tex = false
			logErr("font load " .. tostring(f.file) .. ": " .. tostring(h))
		end
	end
	return f
end

-- разбор строки на куски: 1 = обычный текст (рисует движок), 2 = цветовой код, 3 = кириллица (массив кодов)
local segCache, segN = { }, 0
local function parseLine(line)
	local segs = segCache[line]
	if segs then return segs end
	segs = { }
	local n, pos, len, runStart = 0, 1, #line, 1
	local cps
	local function flushNative(upto)
		if upto >= runStart then
			n = n + 1; segs[n] = { 1, ssub(line, runStart, upto) }
		end
	end
	while pos <= len do
		local b = sbyte(line, pos)
		if b < 128 then
			local escLen = 0
			if b == 94 then
				local c = sbyte(line, pos + 1)
				if c and c >= 48 and c <= 57 then
					escLen = 2
				elseif (c == 120 or c == 88) and sfind(line, "^%x%x%x%x%x%x", pos + 2) then
					escLen = 8
				end
			end
			if escLen > 0 then
				if cps then cps = nil else flushNative(pos - 1) end
				n = n + 1; segs[n] = { 2, ssub(line, pos, pos + escLen - 1) }
				pos = pos + escLen
				runStart = pos
			else
				if cps then cps = nil; runStart = pos end
				pos = pos + 1
			end
		else
			local cp, size
			if b >= 240 then
				cp, size = 0, 4
			elseif b >= 224 then
				local b2, b3 = sbyte(line, pos + 1, pos + 2)
				cp = (b2 and b3) and ((b - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)) or 0
				size = 3
			elseif b >= 192 then
				local b2 = sbyte(line, pos + 1)
				cp = b2 and ((b - 192) * 64 + (b2 - 128)) or 0
				size = 2
			else
				cp, size = 0, 1
			end
			if SUPPORTED[cp] then
				if not cps then
					flushNative(pos - 1)
					cps = { }
					n = n + 1; segs[n] = { 3, cps }
				end
				cps[#cps + 1] = cp
				pos = pos + size
				runStart = pos
			else
				if cps then cps = nil; runStart = pos end
				pos = pos + size
			end
		end
	end
	if not cps then flushNative(len) end
	if segN > 20000 then segCache = { }; segN = 0 end
	segCache[line] = segs
	segN = segN + 1
	return segs
end

local function scaled(height)
	local s = nScale()
	local H = floor(height * s + 0.5)
	if H <= 1 then H = 1 else H = H + 1; H = H - H % 2 end
	return s, H
end

local function glyphSet(font, H)
	local f = fontFor(font)
	local fh = HLIST[H > 64 and #HLIST or HMAP[H < 0 and 0 or H]]
	return f, f.heights[fh], fh, H / fh
end

local function lineWidth(segs, height, font, s, glyphs, scale)
	local w = 0
	for i = 1, #segs do
		local seg = segs[i]
		local kind = seg[1]
		if kind == 1 then
			w = w + floor(nWidth(height, font, seg[2]) * s + 0.5)
		elseif kind == 3 then
			local cps = seg[2]
			for j = 1, #cps do
				local g = glyphs[cps[j]]
				if g then w = w + ceil(g[5] * scale - 0.001) end
			end
		end
	end
	return w
end

local function drawLine(line, left, y, align, height, font, s, H)
	local segs = parseLine(line)
	local f, glyphs, fh, scale = glyphSet(font, H)
	local x
	if align == "LEFT" or align == nil then
		x = floor(left * s + 0.5)
	else
		local w = lineWidth(segs, height, font, s, glyphs, scale)
		if align == "CENTER" then
			x = floor((nScreenSize() * s - w) / 2 + left * s)
		elseif align == "RIGHT" then
			x = floor(nScreenSize() * s - w - left * s)
		elseif align == "CENTER_X" then
			x = floor(left * s - w / 2)
		elseif align == "RIGHT_X" then
			x = floor(left * s - w)
		else
			x = floor(left * s + 0.5)
		end
		x = floor(x + 0.5)
	end
	local tex = f.tex
	local tw, th = f.w, f.h
	local yl = (y + 0.5) / s
	for i = 1, #segs do
		local seg = segs[i]
		local kind = seg[1]
		if kind == 1 then
			local str = seg[2]
			nDrawString(x / s, yl, "LEFT", height, font, str)
			x = x + floor(nWidth(height, font, str) * s + 0.5)
		elseif kind == 2 then
			nSetColor(seg[2])
		else
			local cps = seg[2]
			for j = 1, #cps do
				local g = glyphs[cps[j]]
				if g then
					if tex then
						nDrawImage(tex, (x + g[4] * scale) / s, y / s, g[3] * scale / s, H / s,
							g[1] / tw, g[2] / th, (g[1] + g[3]) / tw, (g[2] + fh) / th)
					end
					x = x + ceil(g[5] * scale - 0.001)
				end
			end
		end
	end
end

local function drawString(left, top, align, height, font, text)
	local s, H = scaled(height)
	local y = floor(top * s)
	local pos, len = 1, #text
	while pos <= len + 1 do
		local nl = sfind(text, "\n", pos, true)
		local line = ssub(text, pos, (nl or len + 1) - 1)
		if line ~= "" then
			if sfind(line, "[\128-\255]") then
				drawLine(line, left, y, align, height, font, s, H)
			else
				nDrawString(left, (y + 0.5) / s, align, height, font, line)
			end
		end
		y = y + H
		if not nl then break end
		pos = nl + 1
	end
end

local function stringWidth(height, font, text)
	local s, H = scaled(height)
	local _, glyphs, _, scale = glyphSet(font, H)
	local best = 0
	local pos, len = 1, #text
	while pos <= len do
		local nl = sfind(text, "\n", pos, true)
		local line = ssub(text, pos, (nl or len + 1) - 1)
		if line ~= "" then
			local w
			if sfind(line, "[\128-\255]") then
				w = lineWidth(parseLine(line), height, font, s, glyphs, scale)
			else
				w = nWidth(height, font, line) * s
			end
			if w > best then best = w end
		end
		if not nl then break end
		pos = nl + 1
	end
	return best / s
end

local function cursorIndex(height, font, text, curX, curY)
	local s, H = scaled(height)
	local _, glyphs, _, scale = glyphSet(font, H)
	local cx, cy = floor(curX * s + 0.5), floor(curY * s + 0.5)
	local pos, len, lineY = 1, #text, H
	while true do
		local nl = sfind(text, "\n", pos, true)
		local lineEnd = (nl or len + 1) - 1
		if cy <= lineY or not nl then
			-- идём по символам строки
			local x, p = 0, pos
			while p <= lineEnd do
				local b = sbyte(text, p)
				local size, w = 1, 0
				local esc = 0
				if b == 94 then
					local c = sbyte(text, p + 1)
					if c and c >= 48 and c <= 57 then esc = 2
					elseif (c == 120 or c == 88) and sfind(text, "^%x%x%x%x%x%x", p + 2) then esc = 8 end
				end
				if esc > 0 then
					p = p + esc
				else
					if b >= 240 then size = 4 elseif b >= 224 then size = 3 elseif b >= 192 then size = 2 end
					local ch = ssub(text, p, p + size - 1)
					if size == 1 then
						w = floor(nWidth(height, font, ch) * s + 0.5)
					else
						local cp = 0
						if size == 2 then
							cp = (b - 192) * 64 + ((sbyte(text, p + 1) or 128) - 128)
						elseif size == 3 then
							local b2, b3 = sbyte(text, p + 1, p + 2)
							cp = (b - 224) * 4096 + ((b2 or 128) - 128) * 64 + ((b3 or 128) - 128)
						end
						local g = glyphs[cp]
						if g then w = ceil(g[5] * scale - 0.001) else w = floor(nWidth(height, font, ch) * s + 0.5) end
					end
					x = x + w
					if cx <= x then return p end
					p = p + size
				end
			end
			return lineEnd + 1
		end
		pos = nl + 1
		lineY = lineY + H
	end
end

---------------------------------------------------------------------------
-- Подмена функций движка
---------------------------------------------------------------------------
local failed = 0
local function guard(err)
	failed = failed + 1
	if failed <= 20 then logErr(debug.traceback(tostring(err), 2)) end
	if failed > 200 then ru.enabled = false end
end

-- Подгонка: если перевод длиннее отведённого места (кнопка, подпись слева от поля), уменьшаем шрифт
local function fit(left, top, align, height, font, text)
	local avail
	if align == "CENTER_X" then
		avail = ru.fitW
	elseif align == "RIGHT_X" and ru.fitR then
		avail = ru.fitR
	elseif align == "RIGHT_X" and left >= 16 then
		avail = left - 1
	end
	if avail and avail > 20 and height > 10 then
		local w = stringWidth(height, font, text)
		if w > avail then
			local h = floor(height * avail / w)
			if h < 10 then h = 10 end
			if h < height * 0.62 then h = floor(height * 0.62) end
			h = h - h % 2
			if h < 10 then h = 10 end
			return top + (height - h) / 2, h
		end
	end
	return top, height
end

function DrawString(left, top, align, height, font, text)
	if type(text) == "string" and ru.enabled then
		if sfind(text, "Ctrl+G", 1, true) then ru.nsSeenT = GetTime() end
		local ok, t = pcall(tr, text)
		if ok then
			if t ~= text and type(left) == "number" and type(height) == "number" then
				local ok3, nt, nh = pcall(fit, left, top, align, height, font, t)
				if ok3 then top, height = nt, nh end
			end
			text = t
		else
			guard(t)
		end
		if haveFonts and sfind(text, "[\128-\255]") then
			local ok2, err = pcall(drawString, left, top, align, height, font, text)
			if ok2 then return end
			guard(err)
		end
	end
	return nDrawString(left, top, align, height, font, text)
end

function DrawStringWidth(height, font, text)
	if type(text) == "string" and ru.enabled then
		local ok, t = pcall(tr, text)
		if ok then text = t else guard(t) end
		if haveFonts and sfind(text, "[\128-\255]") then
			local ok2, w = pcall(stringWidth, height, font, text)
			if ok2 then return w end
			guard(w)
		end
	end
	return nWidth(height, font, text)
end

function DrawStringCursorIndex(height, font, text, curX, curY)
	if type(text) == "string" and ru.enabled and haveFonts and sfind(text, "[\128-\255]") then
		local ok, idx = pcall(cursorIndex, height, font, text, curX, curY)
		if ok then return idx end
		guard(idx)
	end
	return nCursor(height, font, text, curX, curY)
end

---------------------------------------------------------------------------
-- Точечные правки классов PoB (применяются после их загрузки)
---------------------------------------------------------------------------
local utf8ok, utf8 = pcall(require, "lua-utf8")
local function lower(s)
	if utf8ok and utf8.lower then return utf8.lower(s) end
	return s:lower()
end

local function replaceMethod(className, key, makeNew)
	local classes = common and common.classes
	local class = classes and classes[className]
	local orig = class and rawget(class, key)
	if type(orig) ~= "function" then return false end
	local new = makeNew(orig)
	for _, c in pairs(classes) do
		if rawget(c, key) == orig then rawset(c, key, new) end
	end
	return true
end

local pending = { }

-- Поля ввода: пока поле в фокусе (идёт набор) и в полях с пользовательским текстом перевод не подставляется,
-- иначе курсор и выделение разъедутся. Название камня в неактивном поле показывается по-русски.
pending.EditDraw = function()
	return replaceMethod("EditControl", "Draw", function(orig)
		return function(self, viewPort, noTooltip)
			local prompt, placeholder = self.prompt, self.placeholder
			if type(prompt) == "string" then self.prompt = tr(prompt) end
			if type(placeholder) == "string" then self.placeholder = tr(placeholder) end
			local prev = ru.noTr
			ru.noTr = self.hasFocus or self.gems == nil
			local ok, err = pcall(orig, self, viewPort, noTooltip)
			ru.noTr = prev
			self.prompt, self.placeholder = prompt, placeholder
			if not ok then error(err, 0) end
		end
	end)
end

-- Ввод кириллицы: PoB по умолчанию пропускает в поля только латиницу.
-- Разрешаем русские буквы в поле названия камня (поиск) и в многострочных полях (заметки).
local function allowCyr(key)
	return function(orig)
		return function(self, text, ...)
			if type(text) == "string" and (self.gems or self.lineHeight) and sfind(text, "[\128-\255]") then
				local fp = self.filterPattern
				self.filterPattern = "[%c]"
				local ok, r = pcall(orig, self, text, ...)
				self.filterPattern = fp
				if not ok then error(r, 0) end
				return r
			end
			return orig(self, text, ...)
		end
	end
end
pending.EditInsert = function() return replaceMethod("EditControl", "Insert", allowCyr("Insert")) end
pending.EditReplaceSel = function() return replaceMethod("EditControl", "ReplaceSel", allowCyr("ReplaceSel")) end

-- Набор русских букв с клавиатуры. Движок PoB передаёт в программу только латиницу,
-- а любую другую букву превращает в "?". Восстанавливаем букву по нажатой клавише (раскладка ЙЦУКЕН).
local LAYOUT = { q="й", w="ц", e="у", r="к", t="е", y="н", u="г", i="ш", o="щ", p="з", ["["]="х", ["]"]="ъ",
	a="ф", s="ы", d="в", f="а", g="п", h="р", j="о", k="л", l="д", [";"]="ж", ["'"]="э",
	z="я", x="ч", c="с", v="м", b="и", n="т", m="ь", [","]="б", ["."]="ю", ["`"]="ё" }
local UPPER = { ["й"]="Й", ["ц"]="Ц", ["у"]="У", ["к"]="К", ["е"]="Е", ["н"]="Н", ["г"]="Г", ["ш"]="Ш", ["щ"]="Щ", ["з"]="З", ["х"]="Х", ["ъ"]="Ъ",
	["ф"]="Ф", ["ы"]="Ы", ["в"]="В", ["а"]="А", ["п"]="П", ["р"]="Р", ["о"]="О", ["л"]="Л", ["д"]="Д", ["ж"]="Ж", ["э"]="Э",
	["я"]="Я", ["ч"]="Ч", ["с"]="С", ["м"]="М", ["и"]="И", ["т"]="Т", ["ь"]="Ь", ["б"]="Б", ["ю"]="Ю", ["ё"]="Ё" }
pending.Input = function()
	if type(launch) ~= "table" or type(launch.OnKeyDown) ~= "function" or type(launch.OnChar) ~= "function" then return false end
	local keyDown, onChar = launch.OnKeyDown, launch.OnChar
	local last, lastT
	launch.OnKeyDown = function(self, key, doubleClick)
		if key == "g" and IsKeyDown("CTRL") and (ru.nsBack or (ru.nsSeenT and GetTime() - ru.nsSeenT < 400)) then
			local ok, err = pcall(ru.nsBack and ru.nsReturn or ru.nsGo)
			if not ok then logErr("nsGo: " .. tostring(err)) end
			return
		end
		if type(key) == "string" and LAYOUT[key] then
			last, lastT = key, GetTime()
		else
			last = nil
		end
		return keyDown(self, key, doubleClick)
	end
	launch.OnChar = function(self, key, ...)
		if key == "?" and last and GetTime() - lastT < 300 then
			local ch = LAYOUT[last]
			if IsKeyDown("SHIFT") then ch = UPPER[ch] or ch end
			last = nil
			return onChar(self, ch, ...)
		end
		return onChar(self, key, ...)
	end
	return true
end

-- Поиск камней по русскому названию
pending.GemSearch = function()
	return replaceMethod("GemSelectControl", "BuildList", function(orig)
		return function(self, buf)
			if type(buf) == "string" and sfind(buf, "[\208-\209]") then
				orig(self, "")
				local needle = lower(buf)
				local list, n = { }, 0
				for _, gemId in ipairs(self.list) do
					local gemData = self.gems[gemId]
					local name = gemData and D[gemData.name]
					if name and sfind(lower(name), needle, 1, true) then
						n = n + 1; list[n] = gemId
					end
				end
				self.list = list
				self.searchStr = buf
				return
			end
			return orig(self, buf)
		end
	end)
end

-- Кнопки: сообщаем ширину кнопки, чтобы длинная подпись ужималась
pending.ButtonDraw = function()
	return replaceMethod("ButtonControl", "Draw", function(orig)
		return function(self, viewPort, noTooltip)
			local prev = ru.fitW
			local okS, w = pcall(self.GetSize, self)
			ru.fitW = (okS and type(w) == "number") and (w - 4) or nil
			local ok, err = pcall(orig, self, viewPort, noTooltip)
			ru.fitW = prev
			if not ok then error(err, 0) end
		end
	end)
end

-- Вкладка «Расчёты»: подписи строк стоят в колонке фиксированной ширины
pending.CalcDraw = function()
	return replaceMethod("CalcSectionControl", "DrawContent", function(orig)
		return function(self, ...)
			local prev = ru.fitR
			ru.fitR = 128
			local res = { pcall(orig, self, ...) }
			ru.fitR = prev
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2)
		end
	end)
end

-- Перенос длинных подсказок: сначала перевод, потом разбивка на строки
pending.Wrap = function()
	if type(main) ~= "table" or type(main.WrapString) ~= "function" then return false end
	local orig = main.WrapString
	main.WrapString = function(self, str, height, width)
		if type(str) == "string" then str = tr(str) end
		return orig(self, str, height, width)
	end
	return true
end

-- Ctrl+G из подсказки о неучтённом свойстве: открыть «Конфигурацию» на нужном пункте
local function nsControl()
	local build = type(main) == "table" and main.mode == "BUILD" and main.modes and main.modes["BUILD"]
	local ct = build and build.configTab
	if not ct then return nil end
	local c = ru.nsJumpVar and ct.varControls and ct.varControls[ru.nsJumpVar]
	if not c then c = ct.controls and ct.controls.customModsAddBlock end
	return c, ct, build
end
function ru.nsGo()
	ru.nsJumpVar = ru.nsVar
	local c, ct, build = nsControl()
	if not build or build.viewMode == "CONFIG" then return end
	ru.nsBack = build.viewMode
	build.viewMode = "CONFIG"
	ru.nsJumpN = 3
end
-- повторный Ctrl+G: вернуться на вкладку, с которой пришли
function ru.nsReturn()
	local c, ct, build = nsControl()
	local back = ru.nsBack
	ru.nsBack, ru.nsHiT, ru.nsJumpN = nil, nil, nil
	if build and back and build.viewMode == "CONFIG" then build.viewMode = back end
end
local function nsFrame()
	local c, ct, build = nsControl()
	if not c or build.viewMode ~= "CONFIG" then
		-- ушли с вкладки сами: возврат больше не нужен
		if not ru.nsJumpN or not build then ru.nsBack, ru.nsHiT, ru.nsJumpN = nil, nil, nil end
		if not c then return end
	end
	if ru.nsJumpN then
		ru.nsJumpN = ru.nsJumpN - 1
		if ru.nsJumpN <= 0 then
			ru.nsJumpN = nil
			if ct.controls.scrollBar then
				local _, y = c:GetPos()
				local sb = ct.controls.scrollBar
				local _, sbY = sb:GetPos()
				sb:SetOffset(sb.offset + (y - sbY) - 120)
				ru.nsHiT = GetTime() + 5000
			end
		end
		return
	end
	if not ru.nsBack then return end
	local x, y = c:GetPos()
	local w, h = c:GetSize()
	local x1, y1, x2, y2 = x - 300, y - 4, x + w + 6, y + h + 4
	if c == ct.controls.customModsAddBlock then x1, x2 = x - 6, x + 620 end
	SetDrawLayer(nil, 50)
	if ru.nsHiT and GetTime() < ru.nsHiT then
		SetDrawColor(1, 0.75, 0.1)
		DrawImage(nil, x1, y1, x2 - x1, 2); DrawImage(nil, x1, y2 - 2, x2 - x1, 2)
		DrawImage(nil, x1, y1, 2, y2 - y1); DrawImage(nil, x2 - 2, y1, 2, y2 - y1)
	end
	local msg = "Ctrl+G - вернуться назад"
	local mw = DrawStringWidth(16, "VAR", msg)
	SetDrawColor(0, 0, 0, 0.85)
	DrawImage(nil, x1, y1 - 22, mw + 12, 20)
	SetDrawColor(1, 0.75, 0.1)
	DrawString(x1 + 6, y1 - 20, "LEFT", 16, "VAR", msg)
	SetDrawLayer(nil, 0)
end

local invTick
do
	local f, e = loadfile(BASE .. "inventory.lua")
	if f then
		local ok, r = pcall(f, ru, logErr)
		if ok and type(r) == "function" then invTick = r else logErr("inventory load: " .. tostring(r)) end
	else
		logErr("inventory: " .. tostring(e))
	end
end

function ru.frame()
	if invTick then
		local ok, err = pcall(invTick)
		if not ok then logErr("invTick: " .. tostring(err)); invTick = nil end
	end
	if ru.nsJumpN or ru.nsBack then
		local ok, err = pcall(nsFrame)
		if not ok then logErr("nsFrame: " .. tostring(err)); ru.nsJumpN, ru.nsHiT, ru.nsBack = nil, nil, nil end
	end
	if next(pending) then
		for name, fn in pairs(pending) do
			local ok, done = pcall(fn)
			if not ok then logErr("patch " .. name .. ": " .. tostring(done)); pending[name] = nil
			elseif done then pending[name] = nil end
		end
	end
end

return ru
