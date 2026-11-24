--[[ P1TEST.lua  -  Telemetrie-Ausgabe auf COM1 (Stecker P1)
  Zweck: pruefen, ob COM1 auf dem DC-16 II funktioniert, und ausgewaehlte
  Telemetrie fuer einen Mitleser (Raspberry Pi, ESP32 ...) ausgeben.

  Installation: Datei nach /Apps/P1TEST.lua auf die SD-Karte des Senders,
  dann Modell -> Applikationen -> Benutzerapplikationen -> "+" -> P1TEST.
  Menue: Applikationen -> "P1 Test - Einstellungen".

  P1: 1 GND, 2 VBAT, 3 COM1 RX, 4 COM1 TX, 5 GND, 6 3V3   (3,3-V-Pegel, 8N1)

  Ausgabeformat (je Zeile, Abschluss "\r\n"):
    CSV : P1,<seq>,<ms>,<txV>,<rx1Q>,<rx1V>,<s1>,<s2>,<s3>
    JSON: {"seq":..,"t":..,"txV":..,"q":..,"rxV":..,"s":[s1,s2,s3]}
  Ungueltige/fehlende Sensorwerte: leer (CSV) bzw. null/false (JSON).

  Loopback-Selbsttest ohne Pi: P1-3 (RX) mit P1-4 (TX) brücken. Dann zaehlt
  "RX Bytes" im Menue hoch und "Letzter Empfang" zeigt die eigene Zeile.

  Hinweis: Nur eine App kann COM1 belegen -> VSpeak glasses dabei deaktivieren.
--]]

local appName = "P1 Test"
local BAUD = 115200

local sid            -- Port-ID von serial.init
local comState = "?" -- Statustext
local seq = 0
local lastSend = 0
local txBytes, rxBytes, txErr = 0, 0, 0
local lastRx = ""

-- Einstellungen (pro Modell gespeichert)
local mode, interval            -- 1 = CSV, 2 = JSON; Intervall in ms
local sId, sPa = {}, {}         -- 3 Sensorplaetze: ID / Parameter

local sensList                  -- nur waehrend das Formular offen ist

----------------------------------------------------------------------
local function fmtVal(id, pa)
  if not id or id == 0 then return nil end
  local s = system.getSensorByID(id, pa)
  if not s or not s.valid or s.type == 5 or s.type == 9 then return nil end
  return string.format("%." .. (s.decimals or 0) .. "f", s.value)
end

local function num(v, dec)
  if type(v) ~= "number" then return "" end
  return string.format("%." .. dec .. "f", v)
end

local function buildLine()
  local t = system.getTxTelemetry() or {}
  local now = system.getTimeCounter()
  local v = { fmtVal(sId[1], sPa[1]), fmtVal(sId[2], sPa[2]), fmtVal(sId[3], sPa[3]) }
  if mode == 2 then
    local js = {}
    local null = json.null or false   -- json.null ist nicht dokumentiert
    for i = 1, 3 do js[i] = v[i] and tonumber(v[i]) or null end
    return json.encode({ seq = seq, t = now,
      txV = t.txVoltage, q = t.rx1Percent, rxV = t.rx1Voltage, s = js }) .. "\r\n"
  end
  return string.format("P1,%d,%d,%s,%s,%s,%s,%s,%s\r\n", seq, now,
    num(t.txVoltage, 2), num(t.rx1Percent, 0), num(t.rx1Voltage, 2),
    v[1] or "", v[2] or "", v[3] or "")
end

local function onRead(data)
  rxBytes = rxBytes + #data
  lastRx = (lastRx .. data):gsub("[\r\n]+", " ")
  if #lastRx > 40 then lastRx = lastRx:sub(-40) end
end

----------------------------------------------------------------------
-- Formular
local function sensorChanged(slot, idx)
  local e = sensList[idx]
  sId[slot], sPa[slot] = e and e.id or 0, e and e.param or 0
  system.pSave("s" .. slot .. "id", sId[slot])
  system.pSave("s" .. slot .. "pa", sPa[slot])
end

local function initForm()
  -- Sensorliste aufbauen (Eintrag 1 = "---")
  sensList = { false }
  local labels = { "---" }
  local sel = { 1, 1, 1 }
  for _, s in ipairs(system.getSensors()) do
    if s.param ~= 0 and s.type ~= 5 and s.type ~= 9 then
      sensList[#sensList + 1] = { id = s.id, param = s.param }
      labels[#labels + 1] = string.format("%s [%s]", s.label, s.unit)
      for k = 1, 3 do
        if s.id == sId[k] and s.param == sPa[k] then sel[k] = #labels end
      end
    end
  end

  local dev = system.getDeviceType() or "?"
  form.addRow(1); form.addLabel({ label = dev .. "  FW " .. (system.getVersion() or "?"), font = FONT_MINI })
  form.addRow(1); form.addLabel({ label = "COM1: " .. comState, font = FONT_BOLD })

  form.addRow(2); form.addLabel({ label = "Format" })
  form.addSelectbox({ "CSV", "JSON" }, mode, false, function(v)
    mode = v; system.pSave("mode", v) end)

  form.addRow(2); form.addLabel({ label = "Intervall [ms]" })
  form.addIntbox(interval, 50, 5000, 500, 0, 50, function(v)
    interval = v; system.pSave("intv", v) end)

  for k = 1, 3 do
    form.addRow(2); form.addLabel({ label = "Sensor " .. k, width = 80 })
    form.addSelectbox(labels, sel[k], true, function(i) sensorChanged(k, i) end, { width = 230 })
  end

  form.addRow(1); form.addLabel({ label = "", font = FONT_MINI })   -- Platz fuer printForm
end

local function printForm()
  lcd.drawText(4, 118, string.format("TX %d B  Fehler %d  RX %d B", txBytes, txErr, rxBytes), FONT_MINI)
  lcd.drawText(4, 132, "Letzter Empfang: " .. lastRx, FONT_MINI)
end

local function closeForm() sensList = nil; collectgarbage() end

-- kleines Desktop-Fenster
local function printTele()
  lcd.drawText(2, 2, "COM1 " .. comState, FONT_MINI)
  lcd.drawText(2, 14, string.format("#%d tx%d rx%d", seq, txBytes, rxBytes), FONT_MINI)
end

----------------------------------------------------------------------
local function init()
  mode = system.pLoad("mode", 1)
  interval = system.pLoad("intv", 500)
  for k = 1, 3 do
    sId[k] = system.pLoad("s" .. k .. "id", 0)
    sPa[k] = system.pLoad("s" .. k .. "pa", 0)
  end

  if not serial then
    comState = "keine serial-Lib (FW?)"
  else
    sid = serial.init("COM1", BAUD)
    if sid then
      local ok, err = serial.onRead(sid, onRead)
      comState = ok and ("OK " .. BAUD) or ("onRead: " .. tostring(err))
    else
      comState = "init fehlgeschlagen"
    end
  end
  print(appName .. ": COM1 " .. comState)

  system.registerForm(1, MENU_APPS, appName .. " - Einstellungen", initForm, nil, printForm, closeForm)
  system.registerTelemetry(1, appName, 1, printTele)
end

local function loop()
  if not sid then return end
  local now = system.getTimeCounter()
  if now - lastSend < interval then return end
  lastSend = now
  seq = seq + 1
  local n, err = serial.write(sid, buildLine())
  if n then
    txBytes = txBytes + n
  else
    txErr = txErr + 1
    comState = "write: " .. tostring(err)
  end
end

local function destroy()
  if sid then serial.onRead(sid, nil); serial.deinit(sid); sid = nil end
end

return { init = init, loop = loop, destroy = destroy, author = "JetiDeck", version = "0.1", name = appName }
