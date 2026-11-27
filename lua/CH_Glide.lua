--[[
  CH_Glide – Steuersignal fuer das Tablet (liest den Kanal am EX Bus mit)
  Nachfolger von TabSig 1.2

  Ausgabe ueber Lua-Geber 1 ("CH_Glide", Kurzname "CHG").
  Standardwerte (im App-Menue je Punkt einstellbar, pro Modell gespeichert):

    Punkt                   Wert    Art
    Start/Neustart          +80 %   Impuls 2,0 s   (frueher Start)
    Thermik-Seite           -60 %   Halten         (frueher Thermik)
    Gleiten-Seite           -40 %   Halten         (frueher Strecke)
    Start-Seite             -80 %   Halten         (neu)
    Info-Seite             -100 %   Halten         (frueher Info)
    Vario stummschalten     +20 %   Halten         (neu)
    Navbox-Wert Ansage 1    +40 %   Impuls 1,0 s   (neu)
    Navbox-Wert Ansage 2    +50 %   Impuls 1,0 s   (neu)
    Navbox-Wert Ansage 3    +60 %   Impuls 1,0 s   (neu)
    keiner                    0 %
    FEHLER                 +100 %   (interner Fehler in der App - Signal ungueltig)

  Art "Halten": Wert liegt an, solange der Schalter an ist.
  Art "Impuls": Einschalt-Flanke loest den Wert fuer die eingestellte Dauer
                (0,5..10,0 s) aus; beim Einschalten des Senders kein Impuls.

  Vorrang: laufender Impuls (der zuletzt ausgeloeste gewinnt), danach der
  zuletzt eingeschaltete aktive "Halten"-Punkt (ab 1.1; vorher: oberster der
  Liste - dadurch kamen Info/Vario nie durch, solange eine Seite an war).
  Wird er ausgeschaltet, gilt wieder der vorher aktive. Sind beim Einschalten
  des Senders mehrere an, gewinnt der obere der Liste. Sonst 0 %.

  Werte frei waehlbar -100..+100 % (ab 1.1 keine Sperren mehr). Achtung:
  +100 % ist auch der Fehlerwert, 0 % heisst "kein Signal".
  Geaenderte Werte muessen auch am Tablet nachgezogen werden.
  Detailseite zeigt live: Schalter AKTIV/aus und Rohwert (ab 1.1).

  Absicherung:
    - Berechnung in pcall: bei Lua-Fehler +100 %, bis es wieder klappt.
    - Lebenszeichen (HEARTBEAT): Wert wechselt jede Sekunde um 1 % Richtung 0.
      Tablet mit Toleranz +/-2 % auswerten.
    - App entfernt/gestoppt: Kanal faellt auf 0 %.

  Einrichten am Sender:
    1. Anwendungen > Benutzerapplikationen: CH_Glide hinzufuegen,
       im App-Menue je Punkt Schalter (und ggf. Wert/Art/Dauer) einstellen.
    2. Modell > Funktionszuordnung: Funktion mit Geber = Lua-Geber "CHG".
    3. Modell > Servozuordnung: Funktion auf den Kanal legen, den das Tablet liest.
    4. Servoeinstellung dieses Kanals: Weg +/-100 %, Mitte 0, keine Kurve/Expo.
]]

local appName = "CH_Glide"
local CTRL = 1            -- Nummer des Lua-Gebers (1..10)
local DUR_MIN, DUR_MAX = 5, 100   -- Impulsdauer 0,5 .. 10,0 s (in 0,1 s)
local DEBUG = false       -- true: jede Wertaenderung in der Lua-Konsole ausgeben
local ERROR_VALUE = 1.0   -- Ausgabe bei internem Fehler (+100 %)
local HEARTBEAT = true    -- Lebenszeichen 1 % im Sekundentakt
local HB_STEP = 0.01
local HB_MS = 1000
local IDLE_VALUE = 0.0

local MODES = { "Halten", "Impuls" }
local HOLD, PULSE = 1, 2

-- Liste = Anzeigereihenfolge
local items = {
  { key = "start",   label = "Start/Neustart",       pct = 80,   mode = PULSE, dur = 20 },
  { key = "thermik", label = "Thermik-Seite",        pct = -60,  mode = HOLD,  dur = 20 },
  { key = "gleiten", label = "Gleiten-Seite",        pct = -40,  mode = HOLD,  dur = 20 },
  { key = "sseite",  label = "Start-Seite",          pct = -80,  mode = HOLD,  dur = 20 },
  { key = "info",    label = "Info-Seite",           pct = -100, mode = HOLD,  dur = 20 },
  { key = "vario",   label = "Vario stummschalten",  pct = 20,   mode = HOLD,  dur = 20 },
  { key = "nav1",    label = "Navbox-Wert Ansage 1", pct = 40,   mode = PULSE, dur = 10 },
  { key = "nav2",    label = "Navbox-Wert Ansage 2", pct = 50,   mode = PULSE, dur = 10 },
  { key = "nav3",    label = "Navbox-Wert Ansage 3", pct = 60,   mode = PULSE, dur = 10 },
}

local lastOut = nil
local lastErr = nil
local curForm = 1
local backRow = 1         -- Zeile, auf die das Hauptmenue nach "Zurueck" springt

-- Liefert aktiv (bool) und Rohwert. Normal liefert ein zugeordneter Schalter
-- +1 (aktiv) / -1. Ist er proportional ausgewertet ("Prop."), kommt die
-- Rohstellung (-1/0/+1); dann zaehlt die bei der Zuordnung gewaehlte Stellung.
local function swState(sw)
  if not sw then return false, nil end
  local v = system.getInputsVal(sw)
  if v == nil then return false, nil end
  local ok, info = pcall(system.getSwitchInfo, sw)
  if ok and info and info.proportional then
    local target = info.activeOn or 1
    return math.abs(v - target) < 0.25, v
  end
  return v > 0.5, v
end

local function isOn(sw)
  local on = swState(sw)
  return on
end

-- Flankenspeicher setzen, damit Zuordnen/Einschalten keinen Impuls ausloest
local function prime(item)
  item.wasOn = isOn(item.sw)
  item.untilT = 0
  item.onT = -(item.idx or 0)   -- schon beim Start an: oberer Listenpunkt gewinnt
end

local function fmtPct(p)
  if p > 0 then return "+" .. p .. " %" end
  return p .. " %"
end

local function swName(sw)
  if not sw then return "--" end
  local ok, info = pcall(system.getSwitchInfo, sw)
  if ok and info and info.assigned and info.label then return info.label end
  return "--"
end

----------------------------------------------------------------------
-- Menue
local function mainForm()
  form.setTitle(appName)
  for i, item in ipairs(items) do
    form.addRow(2)
    form.addLink(function() backRow = i; form.reinit(i + 1) end,
      { label = item.label .. " >>", width = 210 })
    local m = item.mode == PULSE and "I" or "H"
    form.addLabel({ label = swName(item.sw) .. " " .. fmtPct(item.pct) .. " " .. m,
      width = 100, alignRight = true, font = FONT_MINI })
  end
  form.addRow(1)
  form.addLabel({ label = "H = Halten, I = Impuls. 0 % = kein Signal", font = FONT_MINI })
  form.addRow(1)
  form.addLabel({ label = "Werte auch am Tablet anpassen! Geber: CHG", font = FONT_MINI })
  form.setFocusedRow(backRow)
end

local function itemForm(item, sub)
  form.setTitle(item.label)

  form.addRow(2)
  form.addLabel({ label = "Schalter", width = 200 })
  form.addInputbox(item.sw, false, function(x)
    item.sw = x
    system.pSave(item.key, x)
    prime(item)
  end)

  form.addRow(2)
  form.addLabel({ label = "Ausgabewert", width = 200 })
  form.addIntbox(item.pct, -100, 100, item.def, 0, 1, function(x)
    item.pct = x
    system.pSave("v_" .. item.key, x)
    lastOut = nil
  end, { label = "%" })

  form.addRow(2)
  form.addLabel({ label = "Art", width = 200 })
  form.addSelectbox(MODES, item.mode, false, function(x)
    item.mode = x
    system.pSave("m_" .. item.key, x)
    prime(item)
    form.reinit(sub)            -- Zeile Dauer ein-/ausblenden
  end)

  if item.mode == PULSE then
    form.addRow(2)
    form.addLabel({ label = "Dauer Impuls", width = 200 })
    form.addIntbox(item.dur, DUR_MIN, DUR_MAX, item.ddef, 1, 1, function(x)
      item.dur = x
      system.pSave("d_" .. item.key, x)
    end, { label = "s" })
  end

  form.addRow(1)
  form.addLink(function() form.reinit(1) end, { label = "<< Zurueck" })
  form.setFocusedRow(1)
end

local function initForm(sub)
  curForm = sub or 1
  local item = items[curForm - 1]
  if item then itemForm(item, curForm) else curForm = 1; mainForm() end
end

-- Live-Anzeige auf der Detailseite: Schalterzustand und Rohwert
local function printForm(w, h)
  local item = items[curForm - 1]
  if not item then return end
  local on, v = swState(item.sw)
  local txt
  if not item.sw then txt = "Schalter: nicht zugeordnet"
  elseif v == nil then txt = "Schalter: nicht vorhanden"
  else txt = string.format("Schalter: %s  (Roh %d %%)", on and "AKTIV" or "aus", math.floor(v * 100 + 0.5)) end
  lcd.drawText(4, h - 18, txt, FONT_MINI)
end

local function keyForm(key)
  if curForm > 1 and key == KEY_ESC then
    form.preventDefault()
    form.reinit(1)
  end
end

----------------------------------------------------------------------
-- Laufzeit
local function compute(now)
  local best, bestStart = nil, -1
  for _, it in ipairs(items) do
    if it.mode == PULSE then
      local on = isOn(it.sw)
      if on and not it.wasOn then
        it.startT = now
        it.untilT = now + it.dur * 100
      end
      it.wasOn = on
      if now < it.untilT and it.startT > bestStart then
        best, bestStart = it, it.startT
      end
    end
  end
  if best then return best.pct / 100 end
  -- Halten: der zuletzt eingeschaltete aktive Punkt gewinnt
  local hold, holdT = nil, nil
  for _, it in ipairs(items) do
    if it.mode == HOLD then
      local on = isOn(it.sw)
      if on and not it.wasOn then it.onT = now end
      it.wasOn = on
      if on and (holdT == nil or it.onT > holdT) then hold, holdT = it, it.onT end
    end
  end
  if hold then return hold.pct / 100 end
  return IDLE_VALUE
end

-- Lebenszeichen: jede zweite Sekunde 1 % Richtung Mitte (bleibt im Bereich -1..1)
local function heartbeat(v, now)
  if not HEARTBEAT or (now // HB_MS) % 2 == 0 then return v end
  if v > 0 then return v - HB_STEP end
  return v + HB_STEP
end

local function loop()
  local now = system.getTimeCounter()
  local ok, res = pcall(compute, now)
  local out
  if ok then
    out = res
    if lastErr then print(appName .. ": wieder ok"); lastErr = nil end
  else
    out = ERROR_VALUE
    if res ~= lastErr then print(appName .. " FEHLER: " .. tostring(res)); lastErr = res end
  end
  out = heartbeat(out, now)
  if out ~= lastOut then
    pcall(system.setControl, CTRL, out, 0)
    lastOut = out
    if DEBUG then print(string.format("CHG %d ms: %d %%", now, math.floor(out * 100 + 0.5))) end
  end
end

local function init()
  for i, it in ipairs(items) do
    it.idx = i
    it.def, it.ddef = it.pct, it.dur
    it.sw   = system.pLoad(it.key)
    it.pct  = system.pLoad("v_" .. it.key, it.pct)
    it.mode = system.pLoad("m_" .. it.key, it.mode)
    it.dur  = system.pLoad("d_" .. it.key, it.dur)
    it.startT = 0
    prime(it)
  end
  system.registerControl(CTRL, appName, "CHG")
  system.registerForm(1, MENU_APPS, appName, initForm, keyForm, printForm)
end

local function destroy()
  system.unregisterControl(CTRL)
end

return { init = init, loop = loop, destroy = destroy,
         author = "", version = "1.1", name = appName }
