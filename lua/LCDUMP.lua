--[[ LCDUMP.lua  -  kompiliert Lua-Apps im JETI-Studio-Emulator zu .lc
  Nur fuer den Emulator gedacht, NICHT auf den Sender kopieren.

  Benutzung: LCDUMP.lua und die zu kompilierenden .lua-Dateien in den
  Emulator-Ordner Apps legen, im Emulator LCDUMP als Benutzerapplikation
  hinzufuegen. Beim Start wird jede Datei aus FILES kompiliert;
  das Ergebnis steht in der Lua-Konsole und im Menue "LCDUMP".
--]]

local FILES = { "VSGL2" }   -- ohne Endung
local STRIP = true          -- Debug-Infos entfernen (kleiner, wie VSpeak)

local report = {}

local function log(s)
  print("LCDUMP: " .. s)
  report[#report + 1] = s
end

local function compile(name)
  local src = "Apps/" .. name .. ".lua"
  local dst = "Apps/" .. name .. ".lc"
  if not string.dump then return log("string.dump fehlt") end
  if not load then return log("load fehlt") end
  local text = io.readall(src)
  if not text then return log(src .. " nicht lesbar") end
  local fn, err = load(text, "=" .. name)
  if not fn then return log("Syntaxfehler: " .. tostring(err)) end
  local ok, bc = pcall(string.dump, fn, STRIP)
  if not ok then return log("dump: " .. tostring(bc)) end
  local f = io.open(dst, "wb")
  if not f then return log(dst .. " nicht schreibbar") end
  io.write(f, bc)
  io.close(f)
  log(string.format("%s.lc OK, %d Bytes (Quelle %d)", name, #bc, #text))
end

local function initForm()
  for _, s in ipairs(report) do
    form.addRow(1); form.addLabel({ label = s, font = FONT_MINI })
  end
end

local function init()
  for _, n in ipairs(FILES) do
    local ok, e = pcall(compile, n)
    if not ok then log(n .. ": " .. tostring(e)) end
  end
  system.registerForm(1, MENU_APPS, "LCDUMP", initForm)
end

return { init = init, author = "JetiDeck", version = "0.1", name = "LCDUMP" }
