#@ SimpleGraphic
-- Path of Building RU: запуск с русификатором.
-- Сначала подключается русификатор (папка ru), затем обычный Launch.lua. Файлы PoB не изменяются.
local ok, err = pcall(dofile, "ru/init.lua")
if not ok then
	local f = io.open("ru/error.log", "a")
	if f then f:write(os.date("%Y-%m-%d %H:%M:%S "), "init: ", tostring(err), "\n"); f:close() end
end
dofile("Launch.lua")
if ok and PoBRU and type(launch) == "table" and type(launch.OnFrame) == "function" then
	local onFrame = launch.OnFrame
	launch.OnFrame = function(self, ...)
		PoBRU.frame()
		return onFrame(self, ...)
	end
end
