--[[ xcsim.lua  -  Log-Simulator fuer XC-Flight (Modul, liegt in /Apps/lib/)
  Spielt ein Jeti-Telemetrie-Log (CSV wie in /Log auf der SD-Karte) in Echtzeit ab,
  damit XC-Flight im Emulator ohne echte Sensoren getestet werden kann.
  Wird von XC-Flight nur geladen, wenn "Log-Simulation" eingeschaltet ist.

  Log-Format (Jeti):
    Kopf:   0;SensorID;Param;Name;Einheit          (Param 0 = Sensorname)
    Daten:  Zeit_ms;SensorID;{Param;Typ;Dezimalen;Wert}...
    Typ 9 = GPS: Wert = (Grad << 16) | (Minuten * 1000); Dezimalen 0=N 1=E 2=S 3=W

  Sensor-IDs bleiben Text: sie passen oft nicht in die 32-bit-Ganzzahlen von Jeti-Lua.
--]]

local M = {}

local PATH = "Apps/XCFLIGHT/sim.log"
-- Jeti 6.x begrenzt die Rechenzeit je Aufruf: wenig Arbeit pro Aufruf!
local SCAN_LINES = 50         -- Datenzeilen zum Erkennen der GPS-Kanaele beim Oeffnen
local MAX_LINES_PER_TICK = 20 -- Logzeilen je loop()

local f                       -- offene Datei
local vals = {}               -- vals[id][param] = Zahl (GPS als Dezimalgrad)
local pendT, pendLine         -- naechste noch nicht faellige Datenzeile
local t0 = 0                  -- Systemzeit beim Start der Wiedergabe
local ended = false
local byKey = {}              -- "id:param" -> Eintrag (zum Nachtragen von GPS)
M.entries = nil               -- { {id=,param=,label=,unit=,gps=} } aus dem Log-Kopf
M.error = nil

-- Iterator ueber die ;-getrennten Felder einer Zeile.
-- (string.gmatch steht in Jeti-Lua nicht zur Verfuegung -> string.find)
local function fields(line)
  local pos, len = 1, #line
  return function()
    if pos > len + 1 then return nil end
    local e = string.find(line, ";", pos, true)
    local v
    if e then v = string.sub(line, pos, e - 1); pos = e + 1
    else v = string.sub(line, pos); pos = len + 2 end
    return v
  end
end

local function decode(typ, dec, raw)
  if typ == 9 then
    local deg = (raw >> 16) & 0xFF
    local min = (raw & 0xFFFF) / 1000
    local v = deg + min / 60
    if dec == 2 or dec == 3 then v = -v end
    return v
  end
  if dec > 0 then return raw / (10 ^ dec) end
  return raw
end

-- Datenzeile anwenden
local function apply(line)
  local it = fields(line)
  it()                                  -- Zeit
  local id = it()
  local t = vals[id]
  if not t then t = {}; vals[id] = t end
  while true do
    local p = it(); if not p or p == "" then break end
    local typ, dec, raw = tonumber(it()), tonumber(it()), tonumber(it())
    if not raw then break end
    if typ == 9 then
      local e = byKey[id .. ":" .. p]
      if e then e.gps = true end
    end
    t[tonumber(p)] = decode(typ, dec, raw)
  end
end

-- naechste Datenzeile holen (Kopfzeilen ueberspringen)
local function readNext()
  while true do
    local line = io.readline(f, true)
    if not line then return nil end
    local ts = string.match(line, "^(%d+);")
    local t = ts and tonumber(ts)
    if t and t > 0 then return t, line end
  end
end

-- Log oeffnen: Kopf lesen, GPS-Kanaele erkennen; true oder false, Fehlertext
function M.open()
  M.close()
  local h = io.open(PATH, "r")
  if not h then M.error = "fehlt: " .. PATH; return false, M.error end
  local entries, index, gpsSet = {}, {}, {}
  local n = 0
  while true do
    local line = io.readline(h, true)
    if not line then break end
    if string.sub(line, 1, 1) ~= "#" then
      local it = fields(line)
      local t = tonumber(it())
      if t == 0 then
        local id, p, name, unit = it(), tonumber(it()), it(), it()
        if p and p > 0 then
          local e = { id = id, param = p, label = name, unit = unit or "" }
          entries[#entries + 1] = e
          index[id .. ":" .. p] = e
        elseif p == 0 then
          index[id] = name                       -- Sensorname
        end
      elseif t then
        n = n + 1
        local id = it()
        while true do
          local p = it(); if not p or p == "" then break end
          local typ = it(); it(); it()
          if typ == "9" then gpsSet[id .. ":" .. p] = true end
        end
        if n >= SCAN_LINES then break end
      end
    end
  end
  io.close(h)
  for _, e in ipairs(entries) do
    e.gps = gpsSet[e.id .. ":" .. e.param] or false
    e.sensorName = index[e.id] or e.id
  end
  byKey = index
  M.entries = entries
  M.error = nil
  return true
end

-- Wiedergabe (neu) starten
function M.start(now)
  if f then io.close(f) end
  f = io.open(PATH, "r")
  vals, ended, t0 = {}, false, now
  if not f then M.error = "fehlt: " .. PATH; ended = true; return end
  pendT, pendLine = readNext()
  if not pendT then ended = true end
end

-- faellige Zeilen anwenden
function M.tick(now)
  if not f or ended then return end
  local t = now - t0
  local n = 0
  while pendT and pendT <= t and n < MAX_LINES_PER_TICK do
    apply(pendLine)
    pendT, pendLine = readNext()
    n = n + 1
  end
  if not pendT then ended = true; io.close(f); f = nil end
end

function M.value(id, param)
  local t = vals[id]
  return t and t[param] or nil
end

-- GpsPoint aus zwei Simulationskanaelen
function M.point(lat, lon)
  local a, b = M.value(lat.id, lat.param), M.value(lon.id, lon.param)
  if a and b and not (a == 0 and b == 0) then return gps.newPoint(a, b) end
  return nil
end

function M.status(now)
  if M.error then return "SIM " .. M.error end
  if ended then return "SIM Ende" end
  local s = math.floor((now - t0) / 1000)
  return string.format("SIM %d:%02d", s // 60, s % 60)
end

function M.close()
  if f then io.close(f); f = nil end
  vals, ended = {}, false
end

return M
