--[[ VSGL2.lua  -  robuste Ersatz-App fuer "VSpeak glasses" (gleiches Protokoll)

  Unterschied zum Original (V1.0/V1.1):
  Das Original beantwortet eine Anfrage des Moduls nur, wenn serial.onRead
  GENAU 36 Zeichen in einem Stueck liefert. Zerstueckelte oder zusammengeklebte
  Anfragen werden still verworfen -> keine Antwort -> Werte auf der Brille frieren ein.
  Diese App sammelt die Bytes in einem Puffer, setzt Anfragen wieder zusammen,
  synchronisiert sich neu und zaehlt alles mit (Diagnose im Telemetriefenster).

  Installation: /Apps/VSGL2.lua, im Modell statt "VSpeak glasses" aktivieren
  (nur eine App darf COM1 belegen!). Menue: Applikationen -> "VSpeak glasses 2".
  Diagnose: Telemetrie-Anzeige "VSGL2 Diagnose" auf den Desktop legen.

  Ab 0.3: je Seite waehlbare Quelle "Sensoren" / "XC-Flight 1" (Strecke, Ø, Flugzeit) /
  "XC-Flight 2" (Hoehe, Einflug-Timer, ENL). Die Werte kommen fertig formatiert aus
  package.loaded["xcshare"] (von XC-Flight ab 2.10.0); veraltet (> 3 s) oder fehlend -> "-//-".

  Protokoll (aus VS_glass.lc rekonstruiert, 115200 8N1):
    Modul -> Sender: 36 Zeichen  [1-17 Adresse][18][19-31 Name][32][33-36 ...]
                     Zeichen 3 = ':' -> Brille verbunden, ' ' -> keine Brille
    Sender -> Modul: je Anfrage ein JSON ohne Zeilenende:
      {"res_addr":0|1,"ble_On":0|1,"minus":1..3,"units":0|1,"page":1..3,
       "value":[v1,v2,v3],"unit":[u1,u2,u3],"font":[f1,f2,f3]}
--]]

local appName = "VSpeak glasses 2"
local FRAME = 36

-- Einstellungen
local swPage, swBle            -- Geber fuer Seite / BLE
local minus, unitsOn           -- 1..3 / bool
local sid, sPa, sFo = {}, {}, {} -- 9 Plaetze: Sensor-ID, Parameter, Font (1..3)
local sDec, sUnit = {}, {}       -- Cache: Nachkommastellen / Einheit je Platz
local src = { 1, 1, 1 }          -- Quelle je Seite: 1 Sensoren, 2 XC-Flight 1, 3 XC-Flight 2
local SRC = { "Sensoren", "XC-Flight 1", "XC-Flight 2" }
local XCLBL = { { "Strecke", "Ø Geschw.", "Flugzeit" }, { "Höhe", "Einflug-Timer", "ENL" } }

-- Laufzeit
local sidPort
local rxBuf, rxPieces, rxFirst = "", 0, 0
local pending = false
local resAddr = 0
local gAddr, gName, gInfo, gState = "", "", "", " "
local lastFrame = ""
local page = 2
local editPage = 1
local formOpen = false
local sensIdx                  -- nur bei offenem Formular

-- Diagnose
local d = { ok = 0, frag = 0, merged = 0, junk = 0, sent = 0, err = 0,
            lastReq = 0, maxGap = 0, gaps = 0, mem = 0, memMax = 0 }

-- wiederverwendete Tabellen fuer die Antwort (kein Neuanlegen pro Anfrage)
local val, uni, fnt = { "", "", "" }, { "", "", "" }, { 3, 3, 3 }
local msg = { value = val, unit = uni, font = fnt }

local FONTS = { "small", "middle", "large" }

----------------------------------------------------------------------
local function readPage()
  local v = swPage and system.getInputsVal(swPage)
  if not v then return 2 end
  v = v * 4096
  if v > 1000 then return 3 elseif v < -1000 then return 1 end
  return 2
end

local function readBle()
  local v = swBle and system.getInputsVal(swBle)
  return (v and v > 0) and 1 or 0
end

local FMT = { [0] = "%d", "%.1f", "%.2f", "%.3f" }

local function fmtSlot(i)
  local id = sid[i]
  if not id or id == 0 then return "/", "" end
  -- Nachkommastellen/Einheit einmalig holen (volle Sensortabelle ist teuer)
  if not sDec[i] then
    local s = system.getSensorByID(id, sPa[i])
    if not s then return "-//-", "" end
    sDec[i], sUnit[i] = s.decimals or 0, s.unit or ""
  end
  local s = system.getSensorValueByID(id, sPa[i])
  if not s or not s.valid then return "-//-", "" end
  local dec = sDec[i]
  local v = s.value
  if dec < 1 or dec > 3 then dec = 0; v = math.floor(v + 0.0) end
  return string.format(FMT[dec], v), unitsOn and sUnit[i] or ""
end

-- Antwort fuer die aktuelle Seite zusammenstellen
local function build()
  local b = (page - 1) * 3
  local sr = src[page] or 1
  local X = sr > 1 and package.loaded["xcshare"]
  local fresh = X and type(X) == "table" and X.t and system.getTimeCounter() - X.t < 3000
  for k = 1, 3 do
    if sr == 1 then
      val[k], uni[k] = fmtSlot(b + k)
    elseif fresh then
      local j = (sr - 2) * 3 + k                 -- XC 1 -> 1..3, XC 2 -> 4..6
      val[k], uni[k] = X.v[j], unitsOn and X.u[j] or ""
    else
      val[k], uni[k] = "-//-", ""                -- XC-Flight nicht aktiv
    end
    fnt[k] = sFo[b + k] or 3
  end
end

local function send()
  build()
  msg.res_addr, msg.ble_On, msg.minus = resAddr, readBle(), minus
  msg.units, msg.page = unitsOn and 1 or 0, page
  local n = serial.write(sidPort, json.encode(msg))
  if n then d.sent = d.sent + 1 else d.err = d.err + 1 end
end

----------------------------------------------------------------------
-- Empfang: Puffer + Resynchronisation
local COLON, SPACE = 58, 32   -- Bytewerte ':' und ' ' (string.byte erzeugt keine Strings)

local function plausible(f)
  local c = f:byte(3)
  if c ~= COLON and c ~= SPACE then return false end
  -- alle Trenner der Adresse XX:XX:XX:XX:XX:XX pruefen (verhindert Versatz um 3)
  for p = 6, 15, 3 do
    if f:byte(p) ~= c then return false end
  end
  return true
end

local function handleFrame(f)
  if f ~= lastFrame then        -- Teilstrings nur bei Aenderung ausschneiden
    lastFrame = f
    gAddr, gName, gInfo = f:sub(1, 17), f:sub(19, 31), f:sub(33, 36)
    gState = f:byte(3) == COLON and ":" or " "
  end
  if gState == " " then resAddr = 0 end
  local now = system.getTimeCounter()
  if d.lastReq > 0 then
    local gap = now - d.lastReq
    if gap > d.maxGap then d.maxGap = gap end
    if gap > 1000 then d.gaps = d.gaps + 1 end
  end
  d.lastReq = now
  d.ok = d.ok + 1
  pending = true
end

local function onRead(data)
  if not data or #data == 0 then return end
  if #rxBuf == 0 then rxPieces, rxFirst = 0, #data end
  rxPieces = rxPieces + 1
  rxBuf = (#rxBuf == 0) and data or (rxBuf .. data)
  if #data > FRAME then d.merged = d.merged + 1 end

  while #rxBuf >= FRAME do
    local f = rxBuf:sub(1, FRAME)
    local c3 = f:byte(3)
    -- Rueckfall wie im Original: Puffer geht in 36er-Bloecken auf und Zeichen 3 passt
    if plausible(f) or (#rxBuf % FRAME == 0 and (c3 == COLON or c3 == SPACE)) then
      if rxPieces > 1 and rxFirst < FRAME then d.frag = d.frag + 1 end
      handleFrame(f)
      rxBuf = rxBuf:sub(FRAME + 1)
      rxPieces, rxFirst = 1, #rxBuf
    else
      -- ein Byte verwerfen und neu synchronisieren
      rxBuf = rxBuf:sub(2)
      d.junk = d.junk + 1
    end
  end
  if #rxBuf == 0 then rxPieces = 0 end
  if #rxBuf > 4 * FRAME then rxBuf = "" end
end

----------------------------------------------------------------------
-- Formular
local function save(k, v) system.pSave(k, v) end

-- je Platz ein Parameter "ID,Param,Font" (Jeti empfiehlt max. 30 Parameter pro App)
local function saveSlot(i)
  save("s" .. i, string.format("%d,%d,%d", sid[i] or 0, sPa[i] or 0, sFo[i] or 3))
end

local function slotChanged(slot, idx)
  local e = sensIdx[idx]
  sid[slot], sPa[slot] = e and e.id or 0, e and e.param or 0
  sDec[slot], sUnit[slot] = nil, nil
  saveSlot(slot)
end

local function initForm()
  if not formOpen then editPage = page end   -- beim Oeffnen: aktuelle Schalterseite
  formOpen = true
  sensIdx = { false }
  local labels = { "..." }
  local sel = { 1, 1, 1 }
  local b = (editPage - 1) * 3
  for _, s in ipairs(system.getSensors()) do
    if s.param ~= 0 and s.type ~= 5 and s.type ~= 9 then
      sensIdx[#sensIdx + 1] = { id = s.id, param = s.param }
      labels[#labels + 1] = string.format("%s: %s [%s]", s.sensorName or "", s.label, s.unit)
      for k = 1, 3 do
        if s.id == sid[b + k] and s.param == sPa[b + k] then sel[k] = #labels end
      end
    end
  end

  form.addRow(1)
  form.addLabel({ label = gState == ":" and ("Brille: " .. gName .. " " .. gInfo)
    or "Brille: nicht gefunden", font = FONT_MINI })

  form.addRow(2); form.addLabel({ label = "Seiten-Schalter", width = 200 })
  form.addInputbox(swPage, true, function(v) swPage = v; save("swPage", v) end)
  form.addRow(2); form.addLabel({ label = "BLE (On/Off)", width = 200 })
  form.addInputbox(swBle, false, function(v) swBle = v; save("swBle", v) end)
  form.addRow(2); form.addLabel({ label = "Minus signs", width = 200 })
  form.addIntbox(minus, 1, 3, 1, 0, 1, function(v) minus = v; save("minus", v) end)
  form.addRow(2); form.addLabel({ label = "Einheiten anzeigen", width = 270 })
  -- wie im Original: Callback liefert den alten Zustand, App schaltet selbst um
  local cb
  cb = form.addCheckbox(unitsOn, function(v)
    unitsOn = not v; save("units", unitsOn and 1 or 0); form.setValue(cb, unitsOn) end)

  form.addRow(2); form.addLabel({ label = "Seite bearbeiten", font = FONT_BOLD, width = 200 })
  form.addSelectbox({ "1", "2", "3" }, editPage, false, function(v)
    editPage = v; form.reinit(1) end)
  form.addRow(2); form.addLabel({ label = "Quelle", width = 150 })
  form.addSelectbox(SRC, src[editPage], false, function(v)
    src[editPage] = v; save("src" .. editPage, v); form.reinit(1) end, { width = 170 })

  local xl = XCLBL[src[editPage] - 1]
  for k = 1, 3 do
    local slot = b + k
    form.addRow(2)
    if xl then form.addLabel({ label = xl[k], width = 220 })      -- Werte kommen von XC-Flight
    else form.addSelectbox(labels, sel[k], true, function(i) slotChanged(slot, i) end, { width = 220 }) end
    form.addSelectbox(FONTS, sFo[slot] or 3, false, function(v)
      sFo[slot] = v; saveSlot(slot) end, { width = 90 })
  end

  form.addRow(1)
  form.addLabel({ label = "Taste 1 = Brille vergessen", font = FONT_MINI })
  form.setButton(1, ":delete", gState == ":" and ENABLED or DISABLED)
end

local function keyForm(key)
  if key == KEY_1 and gState == ":" then resAddr = 1 end
end

local function closeForm() formOpen = false; sensIdx = nil; collectgarbage() end

-- Diagnosefenster (Desktop)
-- Zelle: Bezeichnung links, Wert rechtsbuendig
local function cell(x, y, w, label, value)
  lcd.drawText(x, y, label, FONT_MINI)
  local s = tostring(value)
  lcd.drawText(x + w - lcd.getTextWidth(FONT_MINI, s), y, s, FONT_MINI)
end

-- Layout-Zustand auf Modulebene: beim Zeichnen keine Tabellen/Closures erzeugen
local PAD, GAP = 2, 6
local ry, rlh, rh, rcw, rx2 = 0, 10, 70, 70, 80

local function row(l1, v1, l2, v2)
  if ry + rlh > rh then return end
  cell(PAD, ry, rcw, l1, v1); cell(rx2, ry, rcw, l2, v2)
  ry = ry + rlh
end

local function printDiag(w, h)
  if not sidPort then lcd.drawText(2, 2, "COM1 nicht offen", FONT_MINI); return end
  local age = d.lastReq > 0 and (system.getTimeCounter() - d.lastReq) or 0
  if age > 99999 then age = 99999 end
  rh, rlh = h or 70, lcd.getTextHeight(FONT_MINI)
  rcw = math.floor(((w or 150) - 2 * PAD - GAP) / 2)
  rx2, ry = PAD + rcw + GAP, 0
  row("Anfr", d.ok, "Antw", d.sent)
  row("zerst", d.frag, "gekl", d.merged)
  row("Muell", d.junk, "Err", d.err)
  row("Max", d.maxGap .. "ms", ">1s", d.gaps)
  row("Letzte", age .. "ms", "Mem", string.format("%.0f/%.0fk", d.mem, d.memMax))
  if ry + rlh <= rh then
    lcd.drawText(PAD, ry, (gState == ":" and gName or "Brille: -") .. "  S" .. page, FONT_MINI)
  end
end

----------------------------------------------------------------------
local function init()
  swPage = system.pLoad("swPage")
  swBle = system.pLoad("swBle")
  minus = system.pLoad("minus", 1)
  unitsOn = system.pLoad("units", 1) == 1
  for i = 1, 9 do
    local v = system.pLoad("s" .. i)
    if v then
      local a, b, c = string.match(v, "(-?%d+),(-?%d+),(%d+)")
      sid[i], sPa[i], sFo[i] = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 3
    else
      -- Uebernahme aus Version 0.1 (3 Parameter je Platz), danach alte loeschen
      sid[i] = system.pLoad("id" .. i, 0)
      sPa[i] = system.pLoad("pa" .. i, 0)
      sFo[i] = system.pLoad("fo" .. i, 3)
      saveSlot(i)
      save("id" .. i, nil); save("pa" .. i, nil); save("fo" .. i, nil)
    end
  end
  for p = 1, 3 do src[p] = system.pLoad("src" .. p, 1) end
  page = readPage()

  system.registerForm(1, MENU_APPS, appName, initForm, keyForm, nil, closeForm)
  system.registerTelemetry(1, "VSGL2 Diagnose", 2, printDiag)

  sidPort = serial and serial.init("COM1", 115200)
  if sidPort then
    local ok, err = serial.onRead(sidPort, onRead)
    if not ok then print("VSGL2 onRead: " .. tostring(err)) end
  else
    print("VSGL2: Error opening COM1")
  end
end

local function loop()
  local p = readPage()
  if p ~= page then
    page = p
    -- Seitenschalter blaettert auch im offenen Menue (wie im Original)
    if formOpen and editPage ~= p then editPage = p; form.reinit(1) end
  end
  if pending and sidPort then
    pending = false
    send()
  end
  -- Speicherstand (KB, gesamter Lua-Speicher) fuer die Diagnose
  d.mem = collectgarbage("count")
  if d.mem > d.memMax then d.memMax = d.mem end
end

local function destroy()
  if sidPort then serial.onRead(sidPort, nil); serial.deinit(sidPort); sidPort = nil end
end

return { init = init, loop = loop, destroy = destroy, author = "JetiDeck", version = "0.3", name = appName }
