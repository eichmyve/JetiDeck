--[[ XCFLIGHT.lua  -  "XC-Flight"
  Verbesserte Neufassung einer Original-App von LeonAir RC (Version 1.2.0),
  gleiches Bedienprinzip, Fehler aus analyse/xc-flight/ANALYSE.md behoben.

  Ablauf:  Startschalter -> Einflugzeit (Motor aus, kein Steigen) -> Flugmessung
           (GPS-Strecke, Ø-Geschwindigkeit, Zeit). Resetschalter -> zurueck in Bereitschaft.

  Aenderungen gegenueber dem Original:
   1. ENL-Alarm in der Einflugzeit nicht mehr in jedem loop() (Stottern):
      hoechstens alle 5 s; ENL >= Grenze startet die Einflugzeit neu (Regel R3).
   2. Sensoren als ID+Parameter gespeichert statt als Listenposition
      (Auswahl bleibt richtig, wenn sich die Sensorliste aendert).
   3. Steig-Erkennung gegenueber dem tiefsten Punkt der Einflugzeit statt
      "hoeher als letzter Messwert" (Toleranz einstellbar, Standard 1 m gegen Sensorrauschen).
   4. GPS-Strecke mit Mindestschritt (10 m): Zittern im Stand zaehlt nicht mit.
   5. Sensorlisten nur bei offenem Menue im Speicher.
   6. Menue waehrend Einflugzeit/Flug gesperrt (statt Werte anzuzeigen,
      die nicht uebernommen werden).
   7. Keine Division durch 0 bei der Ø-Geschwindigkeit direkt nach dem Start.
   8. Zahlen werden ausdruecklich gerundet (kein Verlass auf LUA_FLOORN2I).
   9. Ansage-Beschriftungen englisch ("Distance"/"Speed"), wie es playNumber
      verlangt - im Original wurde die deutsche Beschriftung nicht gesprochen.
  10. Einstellbar: ENL-Schwelle, Steig-Schwelle, km-Ansage ab.
  11. Sprachtexte eingebaut (de/en) - keine Zusatzdatei noetig.
  12. Schalter, der beim Laden des Modells schon EIN steht, startet nicht sofort.
  13. Anzeige: Statuszeile (Bereit/Einflugzeit/Flug), Strecke ab 1 km in km.
      Ab 2.7.0 ENL-Balken am rechten Rand (gruen < Grenze, rot >= Grenze, Strich = Grenze).
  14. Ø-Geschwindigkeit ohne Schalter: automatische Ansage im Raster ab Flugbeginn
      (Parameter "Ansage Ø Geschw. alle", Standard 10 s, 0 = aus).

  Zwei Fassungen (ab 2.9.0): diese Datei = Testfassung mit Log-Simulation. Die Flugfassung
  fuer den Sender erzeugt tools/build_flight.py nach lua/flug/XCFLIGHT.lua: Zeilen mit
  "--@sim" und Bloecke "--@sim{" ... "--@sim}" fallen weg, "--@flight " wird zu Code.

  Brille (ab 2.10.0): XC-Flight legt 6 fertige Anzeigewerte in package.loaded["xcshare"];
  VSGL2 (ab 0.3) zeigt sie als Seite "XC-Flight 1" (Strecke, Ø, Zeit) oder
  "XC-Flight 2" (Hoehe, Einflug-Timer, ENL) auf der ENGO 2 an.

  Startregeln (Reglement 1.0.6, Abschnitt 2.1) - Hoehe = Sensor relativ zum Startplatz:
   R1  waehrend der Einflugzeit mind. 5 m ueber Grund
   R2  unter 400 m ueber Grund - schon beim Betaetigen des Startschalters und bis zum Start
   R3  waehrend der Einflugzeit ENL unter 30 % (< 300 bei Skala 0..1000)
   R4  mind. 10 s ununterbrochenes Sinken: geglaettete Hoehe darf nicht ueber den tiefsten
       Wert der Einflugzeit steigen (Toleranz gegen Sensorrauschen, Standard 0,3 m)
   R4b am Ende der Einflugzeit tiefer als zu Beginn ("auch sehr minimal"; Mindest-Sinken
       einstellbar, Standard 0), sonst kein Start: Alarm "kein Sinken", Einflugzeit neu

  Wertungsflug (ab 2.8.0, Reglement B.3.1, 1.2, 2.2.1, 2.3):
   W1  Hoehe ueber Vorwarnhoehe (700 m) -> Hoehen-Alarm alle 5 s; ueber 750 m -> UNGUELTIG,
       Werte eingefroren bis Reset
   W2  Motor an = Steigen > 1 m/s laenger als 8 s mit ENL > Grenze in dieser Steigphase oder
       bis 5 s davor; reine ENL-Spitze (Sturzflug) = nur kurzer Hinweiston
   W3  Motor an vor 30 min Segelflug -> UNGUELTIG; danach -> Wertung faellt auf die letzte
       erreichte Zeitstufe zurueck, Werte eingefroren; kein neuer Start (Multistart verboten)
   W4  Zeitwertungen: Strecke bei 30 min, 1 h, 2 h, 3 h gemerkt, angezeigt und angesagt
   W5  Wertung erst ab 5 km gueltig: darunter Strecke grau mit "< 5 km", bei 5 km Signal
  Verstoss waehrend der Einflugzeit -> Alarm (max. alle 5 s je Art) und Einflugzeit beginnt neu.
  Startschalter bei >= 400 m oder ohne gueltige Hoehe -> Alarm, kein Start.
  Ohne zugewiesenen Hoehensensor werden R1/R2/R4 nicht geprueft (Hinweis in der Anzeige).
--]]

local appName = "XC-Flight"

-- feste Werte
local GPS_MIN_STEP = 10      -- m: kleinere GPS-Spruenge zaehlen nicht
local ENL_DELAY    = 1000    -- ms: im Flug muss ENL so lange ueber der Schwelle sein
local ALARM_REPEAT = 5000    -- ms: Mindestabstand gleicher Alarme
local MIN_ENTRY    = 10      -- s: Regel R4
local ALT_TAU      = 500     -- ms: Glaettung der Hoehe (gegen Sensorrauschen)
local MOTOR_VZ     = 1.0     -- m/s: Steigen, das zusammen mit ENL als Motor zaehlt (2.2.1.1)
local MOTOR_SEC    = 8       -- s: so lange muss gestiegen werden (> 8 s)
local MOTOR_ENL_PRE = 5000   -- ms: ENL darf bis so lange vor der Steigphase gewesen sein
local GLIDE_MIN    = 30 * 60 -- s: Motor vor dieser Segelflugzeit = ungueltig (2.2.1.3)
local MIN_DIST     = 5000    -- m: Wertungsflug erst ab 5 km (1.2, 2.3)
local CLASSES      = { 30, 60, 120, 180 }  -- min: Zeitwertungen (1.2)
local IDLE, ENTRY, FLIGHT = 0, 1, 2

----------------------------------------------------------------------
-- Texte
local T = {
  de = { sensors = "Sensoren", enl = "ENL Sensor", alt = "Höhe Sensor",
         lat = "GPS Breitengrad", lon = "GPS Längengrad", switches = "Schalter",
         start = "Start Schalter", reset = "Reset Schalter", avg = "Ansage Ø Geschw. alle",
         audio = "Audio und Alarme", aEnl = "ENL Alarm", aClimb = "Steigen Alarm", aAlt = "Höhen Alarm",
         aStart = "Start Sound", cd = "Start Countdown", cdModes = { "Aus", "Stimme", "Beep" },
         params = "Weitere Parameter", entry = "Einflugzeit", climbThr = "Steig-Toleranz (Rauschen)",
         enlThr = "ENL-Grenze (30 % = 300)", kmFrom = "km-Ansage ab",
         rules = "Startregeln", minAlt = "Mindesthöhe", maxAlt = "Höchsthöhe",
         noAlt = "kein Höhensensor: Regeln 1/2/4 aus",
         vLow = "zu tief", vHigh = "zu hoch", vEnl = "ENL", vClimb = "Steigen", vNoAlt = "keine Höhe",
         minSink = "Mindest-Sinken", vNoSink = "kein Sinken",
         flight = "Wertungsflug", warnAlt = "Vorwarnhöhe", maxScore = "Max. Wertungshöhe",
         vWarn = "Höhe", inv750 = "UNGÜLTIG: über", invMotor = "UNGÜLTIG: Motor vor 30 min",
         motorBack = "Motor: Wertung bis", lt5 = "< 5 km",
         locked = "Messung läuft – Einstellungen gesperrt.", lockHint = "Reset-Schalter beendet die Messung.",
         dist = "Strecke", speed = "Ø Geschw.", altitude = "Höhe", time = "Zeit",
         sIdle = "Bereit", sEntry = "Einflugzeit", sFlight = "Flug",
       },
  en = { sensors = "Sensors", enl = "ENL Sensor", alt = "Altitude Sensor",
         lat = "GPS Latitude", lon = "GPS Longitude", switches = "Switches",
         start = "Start Switch", reset = "Reset Switch", avg = "Announce Ø speed every",
         audio = "Audio and Alarms", aEnl = "ENL Alarm", aClimb = "Climb Alarm", aAlt = "Altitude Alarm",
         aStart = "Start Sound", cd = "Start countdown", cdModes = { "Off", "Voice", "Beep" },
         params = "Other Parameters", entry = "Entry time", climbThr = "Climb tolerance (noise)",
         enlThr = "ENL limit (30 % = 300)", kmFrom = "Announce km from",
         rules = "Start rules", minAlt = "Minimum altitude", maxAlt = "Maximum altitude",
         noAlt = "no altitude sensor: rules 1/2/4 off",
         vLow = "too low", vHigh = "too high", vEnl = "ENL", vClimb = "climb", vNoAlt = "no altitude",
         minSink = "Minimum sink", vNoSink = "no sink",
         flight = "Scoring flight", warnAlt = "Warning altitude", maxScore = "Max. scoring altitude",
         vWarn = "altitude", inv750 = "INVALID: above", invMotor = "INVALID: motor before 30 min",
         motorBack = "Motor: scored up to", lt5 = "< 5 km",
         locked = "Measurement running – settings locked.", lockHint = "Reset switch ends the measurement.",
         dist = "Distance", speed = "Ø Speed", altitude = "Altitude", time = "Time",
         sIdle = "Ready", sEntry = "Entry", sFlight = "Flight",
       },
}   -- nach init nur noch die gewaehlte Sprache im Speicher (T = nil)
local L

----------------------------------------------------------------------
-- Einstellungen
local sEnl, sAlt, sLat, sLon            -- { id = , param = } oder nil
local swStart, swReset
local avgEvery            -- s: Raster der Ø-Ansage (0 = aus)
local aEnl, aClimb, aStart, aAlt
local cdMode, entryTime, climbThr, enlThr, kmFrom, minAlt, maxAlt, minSink  -- climbThr/minSink in m
local warnAlt, maxScore   -- m: Vorwarnhoehe und maximale Wertungshoehe im Flug

-- Laufzeit
local state = IDLE
local tStart = 0          -- ms: Beginn Einflugzeit bzw. Flug
local dist = 0            -- m
local lastPt              -- letzter gezaehlter GPS-Punkt
local nextGps = 0
local lastKm = 0
local nextAvg = 0        -- ms: naechste Ø-Ansage
local refAlt              -- tiefste Hoehe der Einflugzeit
local entryAlt            -- Hoehe zu Beginn der Einflugzeit (fuer Mindest-Sinken)
local lastSec = -1
local enlNext             -- ms: naechster ENL-Alarm im Flug (nil = ENL unter Schwelle)
local alarmNext = {}      -- ms je Alarmart: Mindestabstand
local lastViol, lastViolT = nil, 0   -- letzter Regelverstoss (fuer die Anzeige)
local prev = {}           -- vorige Schalterzustaende
local lcdW = 320           -- Breite des Anzeigefensters (fuer Zentrierung)
local altS, altT          -- geglaettete Hoehe [m] und Zeitpunkt der letzten Glaettung
local result              -- nil = Wertung laeuft; sonst Text des Endzustands (eingefroren)
local resultOk            -- Endzustand mit Wertung (Motor nach 30 min) statt ungueltig
local frozenDist, frozenEl -- eingefrorene Strecke [m] und Flugzeit [s]
local classDist = {}      -- [Minuten] = Strecke [m] bei Erreichen der Zeitwertung
local lastClass           -- zuletzt erreichte Zeitwertung [min]
local valid5              -- 5 km erreicht
local altPrevSec          -- geglaettete Hoehe vor 1 s (fuer Steigrate)
local climbSec, climbStartT = 0, 0   -- Sekunden mit Steigen > 1 m/s am Stueck, Beginn
local enlLastT            -- Zeitpunkt der letzten ENL ueber der Grenze

-- Menue
local list, gpsList       -- nur bei offenem Menue

----------------------------------------------------------------------
-- Hilfsfunktionen
local function packSensor(s) return s and string.format("%s,%d", tostring(s.id), s.param) or nil end

local function unpackSensor(v)
  if type(v) ~= "string" then return nil end
  local a, b = string.match(v, "(-?%d+),(-?%d+)")
  if not a then return nil end
  return { id = a, param = tonumber(b) }      -- ID bleibt Text (32-bit-Grenze)
end

local function readSensor(s)
  if not s then return nil end
  local v = system.getSensorValueByID(tonumber(s.id), s.param)
  if v and v.valid then return v.value end
  return nil
end

local function getPos()
  if not (sLat and sLon) then return nil end
  return gps.getPosition(tonumber(sLat.id), sLat.param, sLon.param)
end

-- Parametername; im Sim-Modus mit Praefix "s_" (Sim-Sensoren getrennt gespeichert)
local function sKey(k) return k end

local function loadSensors()
  sEnl = unpackSensor(system.pLoad(sKey("enl")))
  sAlt = unpackSensor(system.pLoad(sKey("alt")))
  sLat = unpackSensor(system.pLoad(sKey("lat")))
  sLon = unpackSensor(system.pLoad(sKey("lon")))
end


-- Audiodatei abspielen; ohne gewaehlte Datei ersatzweise Piep (Anzahl, Frequenz Hz, Dauer ms)
local function playOrBeep(file, n, freq, ms)
  if file and file ~= "" then system.playFile(file, AUDIO_IMMEDIATE) else system.playBeep(n, freq, ms) end
end

-- Alarm je Art hoechstens alle ALARM_REPEAT ms; Ersatzton: ein tiefer, langer Piep
local function alarm(kind, file, now)
  if alarmNext[kind] and now < alarmNext[kind] then return end
  alarmNext[kind] = now + ALARM_REPEAT
  playOrBeep(file, 1, 880, 300)
end

-- aktuellen Schalterstand merken, ohne Flanke auszuloesen (z. B. nach Neuzuweisung im Menue)
local function prime(sw, key)
  local v = sw and system.getInputsVal(sw)
  prev[key] = (v ~= nil and v > 0.5)
end

-- steigende Flanke eines Schalters
local function edge(sw, key)
  local v = sw and system.getInputsVal(sw)
  local on = (v ~= nil and v > 0.5)
  local rising = on and not prev[key]
  prev[key] = on
  return rising
end

-- Hoehe glaetten (exponentiell, Zeitkonstante ALT_TAU) - jede Schleife aufrufen
local function updateAlt(now)
  local a = readSensor(sAlt)
  if not a then altS = nil; return nil end
  if not altS then altS, altT = a, now; return a end
  local k = (now - altT) / ALT_TAU
  if k > 1 then k = 1 end
  altS, altT = altS + (a - altS) * k, now
  return a
end

-- Flugzeit [s] und Strecke [m] - eingefroren, sobald ein Endzustand vorliegt
local function flightEl(now) return frozenEl or math.floor((now - tStart) / 1000) end
local function flightDist() return frozenDist or dist end

local function avgSpeed(now)
  local el = frozenEl or (now - tStart) / 1000
  if state ~= FLIGHT or el < 1 then return nil end
  return flightDist() / el * 3.6
end

----------------------------------------------------------------------
-- Ablauf
local function reset()
  state, dist, lastPt, refAlt, enlNext, lastSec, lastKm = IDLE, 0, nil, nil, nil, -1, 0
  lastViol, result, frozenDist, frozenEl = nil, nil, nil, nil
end

local function startEntry(now)
  state, tStart, dist, refAlt, lastSec, enlNext = ENTRY, now, 0, nil, -1, nil
  entryAlt = nil
end

-- Verstoss: Alarm, Grund merken, Einflugzeit neu
local function violation(kind, file, text, now, alt)
  alarm(kind, file, now)
  lastViol, lastViolT = text, now
  startEntry(now)
  refAlt = alt
end

local function startFlight(now)
  state, tStart, dist, lastKm = FLIGHT, now, 0, 0
  result, frozenDist, frozenEl, classDist, lastClass, valid5 = nil, nil, nil, {}, nil, false
  altPrevSec, climbSec, enlLastT = altS, 0, nil
  nextAvg = now + (avgEvery or 0) * 1000
  lastPt, nextGps = getPos(), now + 1000
  playOrBeep(aStart, 2, 1500, 150)              -- Ersatzton: zwei kurze, hohe Pieps
end

-- ENL im Flug: nur Hinweis (W2). Eine ENL-Spitze ohne Steigen ist erlaubt (Sturzflug),
-- deshalb hier nur ein kurzer Ton; "Motor an" entscheidet checkMotor.
local function checkEnlFlight(now)
  local v = readSensor(sEnl)
  if v and v >= enlThr then
    enlLastT = now
    if not enlNext then enlNext = now + ENL_DELAY
    elseif now >= enlNext then system.playBeep(1, 2000, 60); enlNext = now + ALARM_REPEAT end
  else
    enlNext = nil
  end
end

-- Endzustand: Werte einfrieren, Alarm, Grund in der Statuszeile (bis Reset)
-- scored = true: Wertung bleibt (Motor nach 30 min), sonst ungueltig
local function finish(text, now, d, el, scored)
  if result then return end
  result, frozenDist, frozenEl = text, d or dist, el or math.floor((now - tStart) / 1000)
  resultOk = scored or false
  alarmNext["result"] = nil
  alarm("result", aAlt, now)
end

-- W2/W3: Motor an = Steigen > 1 m/s laenger als 8 s mit ENL > Grenze (ab 5 s vorher)
local function checkMotor(now)
  if not altS then climbSec = 0; return end
  local vz = altPrevSec and (altS - altPrevSec) or 0      -- m pro Sekunde (1-s-Takt)
  altPrevSec = altS
  if vz > MOTOR_VZ then
    if climbSec == 0 then climbStartT = now end
    climbSec = climbSec + 1
  else
    climbSec = 0
  end
  if climbSec > MOTOR_SEC and enlLastT and enlLastT >= climbStartT - MOTOR_ENL_PRE then
    local el = math.floor((climbStartT - tStart) / 1000)  -- reine Segelflugzeit bis Motor
    if el < GLIDE_MIN or not lastClass then
      finish(L.invMotor, now, dist, el)
    else
      finish(string.format("%s %s", L.motorBack, lastClass >= 60 and (lastClass // 60 .. " h") or (lastClass .. " min")),
        now, classDist[lastClass], lastClass * 60, true)
    end
  end
end

-- Regeln R1-R4 waehrend der Einflugzeit; true = Verstoss (Einflugzeit neu gestartet)
local function checkRules(now)
  local e = readSensor(sEnl)
  if e and e >= enlThr then                                    -- R3
    violation("enl", aEnl, L.vEnl, now, readSensor(sAlt)); return true
  end
  if not sAlt then return false end
  local a = readSensor(sAlt)
  if not a then violation("alt", aAlt, L.vNoAlt, now, nil); return true end
  local g = altS or a                                          -- geglaettet fuer R4/R4b
  if not entryAlt then entryAlt = g end                         -- Bezug fuer R4b
  if a < minAlt then violation("alt", aAlt, L.vLow, now, g); return true end   -- R1 (roh)
  if a >= maxAlt then violation("alt", aAlt, L.vHigh, now, g); return true end -- R2 (roh)
  if not refAlt or g < refAlt then
    refAlt = g                                                 -- tiefster Punkt
  elseif g > refAlt + climbThr then                            -- R4
    violation("climb", aClimb, L.vClimb, now, g); return true
  end
  return false
end

local function tickEntry(now)
  if checkRules(now) then return end
  local remaining = entryTime - math.floor((now - tStart) / 1000)
  if remaining >= 1 and remaining <= 5 and remaining ~= lastSec then
    lastSec = remaining
    if cdMode == 2 then system.playNumber(remaining, 0)
    elseif cdMode == 3 then system.playBeep(1, 4186, 200) end
  end
  if now - tStart >= entryTime * 1000 then
    -- R4b: am Ende tiefer als zu Beginn (mehr als minSink, Standard 0 = "auch sehr minimal")
    if sAlt then
      local g = altS
      if not g or not entryAlt or entryAlt - g <= minSink then
        violation("climb", aClimb, L.vNoSink, now, g)
        return
      end
    end
    startFlight(now)
  end
end

local function tickFlight(now)
  -- W1: Hoehe im Wertungsflug (roh, ohne Toleranz - Reglement B.3.1)
  local a = readSensor(sAlt)
  if a and not result then
    if a > maxScore then finish(string.format("%s %d m", L.inv750, maxScore), now)
    elseif a > warnAlt then alarm("warn", aAlt, now); lastViol, lastViolT = string.format("%s %d m", L.vWarn, math.floor(a)), now end
  end
  if result then return end                                    -- eingefroren bis Reset
  checkEnlFlight(now)
  if now >= nextGps then
    nextGps = (now - nextGps > 1000) and now + 1000 or nextGps + 1000
    checkMotor(now)
    if result then return end
    local p = getPos()
    if p then
      if lastPt then
        local d = gps.getDistance(lastPt, p)
        if d >= GPS_MIN_STEP then dist = dist + d; lastPt = p end
      else
        lastPt = p
      end
      local km = math.floor(dist / 1000)
      if km > lastKm then
        lastKm = km
        if km >= kmFrom then system.playNumber(km, 0, "km", "Distance") end
      end
      -- W5: 5 km erreicht -> Wertungsflug gueltig, drei hohe Pieps
      if not valid5 and dist >= MIN_DIST then valid5 = true; system.playBeep(3, 1800, 100) end
    end
    -- W4: Zeitwertungen 30 min, 1 h, 2 h, 3 h
    local el = math.floor((now - tStart) / 1000)
    for _, m in ipairs(CLASSES) do
      if not classDist[m] and el >= m * 60 then
        classDist[m], lastClass = dist, m
        system.playNumber(dist / 1000, 1, "km", "Distance")
      end
    end
  end
  -- Ø-Geschwindigkeit im festen Raster ab Flugbeginn (avgEvery s, 0 = aus)
  if avgEvery > 0 and now >= nextAvg then
    nextAvg = nextAvg + avgEvery * 1000
    if nextAvg <= now then nextAvg = now + avgEvery * 1000 end
    local v = avgSpeed(now)
    if v then system.playNumber(v, 0, "km/h", "Speed") end
  end
end

----------------------------------------------------------------------
-- Brille: Werte fuer andere Apps (VSGL2, Seitenquelle "XC-Flight 1/2")
-- Alle Apps teilen eine Lua-Umgebung; die Tabelle liegt in package.loaded["xcshare"].
--  v/u[1..3] = Anzeige 1: Strecke, Ø-Geschwindigkeit (alle 2 s), Flugzeit
--  v/u[4..6] = Anzeige 2: Hoehe, Einflug-Timer (-- / 10..1 / OK / END / X), ENL
--  t = Zeitpunkt der letzten Aktualisierung [ms] (Leser zeigt "-//-", wenn veraltet)
local share = { v = { "--", "--", "--", "--", "--", "--" }, u = { "", "km/h", "", "m", "", "" }, t = 0 }
local nextPub, nextPubAvg = 0, 0

local function publish(now)
  if now < nextPub then return end
  nextPub = now + 500
  local v, u = share.v, share.u
  if state == FLIGHT then
    local d = flightDist()
    if d >= 1000 then v[1], u[1] = string.format("%.2f", d / 1000), "km"
    else v[1], u[1] = string.format("%d", math.floor(d)), "m" end
    if now >= nextPubAvg then
      nextPubAvg = now + 2000
      local sp = avgSpeed(now)
      v[2] = sp and string.format("%.1f", sp) or "--"
    end
    local el = flightEl(now)
    v[3] = string.format("%d:%02d:%02d", el // 3600, (el // 60) % 60, el % 60)
  else
    v[1], u[1], v[2], v[3] = "--", "", "--", "--"
    nextPubAvg = 0
  end
  local a = readSensor(sAlt)
  v[4] = a and string.format("%d", math.floor(a + 0.5)) or "--"
  if state == ENTRY then
    v[5], u[5] = string.format("%d", math.max(0, entryTime - math.floor((now - tStart) / 1000))), "s"
  elseif state == FLIGHT then
    v[5], u[5] = result and (resultOk and "END" or "X") or "OK", ""
  else
    v[5], u[5] = "--", ""
  end
  local e = readSensor(sEnl)
  v[6] = e and string.format("%d", math.floor(e + 0.5)) or "--"
  share.t = now
end

local primed = false

local function loop()
  local now = system.getTimeCounter()
  local s, r = edge(swStart, "s"), edge(swReset, "r")
  -- erster Durchlauf: nur Schalterstand merken (Schalter schon EIN beim Laden = kein Start)
  if not primed then primed = true; return end
  updateAlt(now)
  if r then
    reset()
  elseif state == IDLE then
    if s then
      -- R2 schon beim Startschalter: Hoehe gueltig und unter der Hoechsthoehe
      local alt = sAlt and readSensor(sAlt)
      if sAlt and not alt then alarm("alt", aAlt, now); lastViol, lastViolT = L.vNoAlt, now
      elseif alt and alt >= maxAlt then alarm("alt", aAlt, now); lastViol, lastViolT = L.vHigh, now
      else lastViol = nil; startEntry(now); refAlt = alt end
    end
  elseif state == ENTRY then tickEntry(now)
  else tickFlight(now) end
  publish(now)
end

----------------------------------------------------------------------
-- Anzeige (ganzseitig, ohne Statusleiste)
--  Flug:        Strecke, Ø-Geschwindigkeit, Flugdauer - je 1/3 der Hoehe, FONT_MAXI
--  Einflugzeit: grosser Countdown, Hoehe, letzter Regelverstoss
--  Bereit:      Status, Hoehe, Hinweise
--  rechts am Rand (falls ENL-Sensor gewaehlt): ENL-Balken 0..1000 mit Markierung der ENL-Grenze
local BAR_W = 14          -- Breite ENL-Balken [px]

-- Schriftfarbe abhaengig vom Hintergrund (lcd.getFgColor liefert nicht die Textfarbe)
local function inkColor()
  local r, g, b = lcd.getBgColor()
  if r + g + b < 384 then lcd.setColor(255, 255, 255) else lcd.setColor(0, 0, 0) end
end

-- ENL-Balken: gruen unter der Grenze, rot ab der Grenze; Strich = ENL-Grenze
local function enlBar(x, y, bw, bh)
  local lh = lcd.getTextHeight(FONT_MINI)
  local tw = lcd.getTextWidth(FONT_MINI, "ENL")
  lcd.drawText(x + math.floor((bw - tw) / 2), y, "ENL", FONT_MINI)
  local by, bhh = y + lh + 1, bh - lh - 3
  lcd.drawRectangle(x, by, bw, bhh)
  local v = readSensor(sEnl)
  if v then
    if v < 0 then v = 0 elseif v > 1000 then v = 1000 end
    local fh = math.floor((bhh - 2) * v / 1000 + 0.5)
    if fh > 0 then
      if v >= enlThr then lcd.setColor(220, 0, 0) else lcd.setColor(0, 160, 0) end
      lcd.drawFilledRectangle(x + 1, by + bhh - 1 - fh, bw - 2, fh)
      inkColor()                                               -- Schriftfarbe zurueck
    end
  end
  -- Markierung der ENL-Grenze (ragt seitlich ueber den Balken)
  local ty = by + bhh - 1 - math.floor((bhh - 2) * enlThr / 1000 + 0.5)
  lcd.drawLine(x - 2, ty, x + bw + 1, ty)
end

local function centerText(y, text, font)
  lcd.drawText(math.floor((lcdW - lcd.getTextWidth(font, text)) / 2), y, text, font)
end

-- eine Wertzeile: Bezeichnung oben links, Wert gross rechtsbuendig, Einheit daneben
local function bigRow(y, rh, w, label, value, unit, grey)
  local mh = lcd.getTextHeight(FONT_MAXI)
  local nh = lcd.getTextHeight(FONT_NORMAL)
  local uw = lcd.getTextWidth(FONT_NORMAL, "km/h")
  lcd.drawText(6, y + 2, label, FONT_NORMAL)
  value = value or "-"
  local vy = y + math.max(nh, math.floor((rh - mh) / 2))
  if vy + mh > y + rh then vy = y + rh - mh end
  if grey then lcd.setColor(150, 150, 150) end              -- W5: noch keine 5 km
  lcd.drawText(w - uw - 12 - lcd.getTextWidth(FONT_MAXI, value), vy, value, FONT_MAXI)
  if unit then lcd.drawText(w - uw - 6, vy + mh - nh - 2, unit, FONT_NORMAL) end
  if grey then inkColor() end
  lcd.drawLine(4, y + rh - 1, w - 4, y + rh - 1)
end

local function statusLine(now)
  local st = state == IDLE and L.sIdle or (state == ENTRY and L.sEntry or L.sFlight)
  if not sAlt then st = st .. "  (" .. L.noAlt .. ")"
  elseif result then st = st .. "  ! " .. result
  elseif lastViol and now - lastViolT < 10000 then st = st .. "  ! " .. lastViol end
  if state == FLIGHT then                                      -- W4: erreichte Zeitwertungen
    for _, m in ipairs(CLASSES) do
      local d = classDist[m]
      if d then st = st .. string.format("  %s %.1f", m >= 60 and (m // 60 .. "h") or (m .. "'"), d / 1000) end
    end
  end
  lcd.drawText(6, 0, st, FONT_MINI)
  return lcd.getTextHeight(FONT_MINI) + 2
end

local function altText()
  local a = readSensor(sAlt)
  return a and string.format("%s %d m", L.altitude, math.floor(a + 0.5)) or (L.altitude .. " -")
end

local function printTele(w, h)
  w, h = w or 320, h or 240
  local now = system.getTimeCounter()
  local hh = statusLine(now)
  -- ENL-Balken rechts; Inhalt bekommt die Restbreite
  if sEnl then
    enlBar(w - BAR_W - 3, hh, BAR_W, h - hh)
    w = w - BAR_W - 8
  end
  lcdW = w

  if state == FLIGHT then
    local rh = math.floor((h - hh) / 3)
    local y = hh
    local dv, du
    local d = flightDist()
    if d >= 1000 then dv, du = string.format("%.2f", d / 1000), "km"
    else dv, du = string.format("%d", math.floor(d)), "m" end
    local under5 = d < MIN_DIST
    bigRow(y, rh, w, under5 and (L.dist .. "  " .. L.lt5) or L.dist, dv, du, under5); y = y + rh
    local sp = avgSpeed(now)
    bigRow(y, rh, w, L.speed, sp and string.format("%.1f", sp) or nil, "km/h"); y = y + rh
    local el = flightEl(now)
    bigRow(y, rh, w, L.time, string.format("%d:%02d:%02d", el // 3600, (el // 60) % 60, el % 60), nil)

  elseif state == ENTRY then
    local el = math.floor((now - tStart) / 1000)
    local rest = math.max(0, entryTime - el)
    local mh = lcd.getTextHeight(FONT_MAXI)
    local bh = lcd.getTextHeight(FONT_BIG)
    local y = hh + math.floor((h - hh - mh - bh - 8) / 2)
    centerText(y, string.format("%d s", rest), FONT_MAXI)
    centerText(y + mh + 8, altText(), FONT_BIG)

  else
    local bh = lcd.getTextHeight(FONT_BIG)
    local y = hh + math.floor((h - hh - 2 * bh - 8) / 2)
    centerText(y, L.sIdle, FONT_BIG)
    centerText(y + bh + 8, altText(), FONT_BIG)
  end
end

----------------------------------------------------------------------
-- Menue
local function save(k, v) system.pSave(k, v) end

local function buildLists()
  list, gpsList = { { label = "..." } }, { { label = "..." } }
  for _, s in ipairs(system.getSensors()) do
    if s.param ~= 0 then
      if s.type == 9 then
        gpsList[#gpsList + 1] = { id = s.id, param = s.param,
          label = string.format("%s: %s", s.sensorName or "", s.label) }
      elseif s.type ~= 5 then
        list[#list + 1] = { id = s.id, param = s.param,
          label = string.format("%s: %s [%s]", s.sensorName or "", s.label, s.unit) }
      end
    end
  end
end

-- Auswahlbox fuer einen Sensor; Speicherung als "ID,Param"
local function sensorBox(caption, lst, cur, key, setter)
  local labels, sel = {}, 1
  for i, e in ipairs(lst) do
    labels[i] = e.label
    if cur and e.id and tostring(e.id) == cur.id and e.param == cur.param then sel = i end
  end
  form.addRow(2)
  form.addLabel({ label = caption, width = 150 })
  form.addSelectbox(labels, sel, true, function(i)
    local e = lst[i]
    local v = (e and e.id) and { id = tostring(e.id), param = e.param } or nil
    setter(v); save(sKey(key), packSensor(v))
  end, { width = 170 })
end

local function header(t)
  form.addRow(1); form.addLabel({ label = t, font = FONT_BOLD })
end

-- Menuezeilen: Bezeichnung + Eingabefeld; set(x) uebernimmt den Wert, gespeichert wird x unter key
local function intRow(label, v, min, max, def, dec, step, key, set, unit)
  form.addRow(2); form.addLabel({ label = label, width = 220 })
  local f = function(x) set(x); save(key, x) end
  if unit then form.addIntbox(v, min, max, def, dec, step, f, { label = unit })
  else form.addIntbox(v, min, max, def, dec, step, f) end
end

local function audioRow(label, v, key, set)
  form.addRow(2); form.addLabel({ label = label, width = 150 })
  form.addAudioFilebox(v, function(x) set(x); save(key, x) end, { width = 170 })
end

local function switchRow(label, v, key, pk, set)
  form.addRow(2); form.addLabel({ label = label, width = 220 })
  form.addInputbox(v, false, function(x) set(x); save(key, x); prime(x, pk) end)
end

local function initForm()
  form.setTitle(appName)
  if state ~= IDLE then
    form.addRow(1); form.addLabel({ label = L.locked })
    form.addRow(1); form.addLabel({ label = L.lockHint, font = FONT_MINI })
    return
  end
  buildLists()

  header(L.sensors)
  sensorBox(L.enl, list, sEnl, "enl", function(v) sEnl = v end)
  sensorBox(L.alt, list, sAlt, "alt", function(v) sAlt = v end)
  sensorBox(L.lat, gpsList, sLat, "lat", function(v) sLat = v end)
  sensorBox(L.lon, gpsList, sLon, "lon", function(v) sLon = v end)

  header(L.switches)
  switchRow(L.start, swStart, "swStart", "s", function(x) swStart = x end)
  switchRow(L.reset, swReset, "swReset", "r", function(x) swReset = x end)

  header(L.audio)
  intRow(L.avg, avgEvery, 0, 300, 10, 0, 5, "avgEvery", function(x) avgEvery = x end, "s")
  audioRow(L.aEnl, aEnl, "aEnl", function(x) aEnl = x end)
  audioRow(L.aClimb, aClimb, "aClimb", function(x) aClimb = x end)
  audioRow(L.aAlt, aAlt, "aAlt", function(x) aAlt = x end)
  audioRow(L.aStart, aStart, "aStart", function(x) aStart = x end)
  form.addRow(2); form.addLabel({ label = L.cd, width = 200 })
  form.addSelectbox(L.cdModes, cdMode, false, function(v) cdMode = v; save("cd", v) end)

  header(L.rules)
  intRow(L.entry, entryTime, MIN_ENTRY, 60, MIN_ENTRY, 0, 1, "entry", function(x) entryTime = x end, "s")
  intRow(L.minAlt, minAlt, 0, 100, 5, 0, 1, "minAlt", function(x) minAlt = x end, "m")
  intRow(L.maxAlt, maxAlt, 50, 2000, 400, 0, 10, "maxAlt", function(x) maxAlt = x end, "m")
  intRow(L.enlThr, enlThr, 0, 1000, 300, 0, 10, "enlThr", function(x) enlThr = x end)
  -- Werte in 0,1 m (Intbox mit 1 Nachkommastelle)
  intRow(L.minSink, math.floor(minSink * 10 + 0.5), 0, 100, 0, 1, 1, "sinkDm", function(x) minSink = x / 10 end, "m")
  intRow(L.climbThr, math.floor(climbThr * 10 + 0.5), 0, 50, 3, 1, 1, "climbDm", function(x) climbThr = x / 10 end, "m")

  header(L.flight)
  intRow(L.warnAlt, warnAlt, 100, 2000, 700, 0, 10, "warnAlt", function(x) warnAlt = x end, "m")
  intRow(L.maxScore, maxScore, 100, 2000, 750, 0, 10, "maxScore", function(x) maxScore = x end, "m")

  header(L.params)
  intRow(L.kmFrom, kmFrom, 1, 50, 5, 0, 1, "kmFrom", function(x) kmFrom = x end, "km")

end

local function closeForm() list, gpsList = nil, nil; collectgarbage() end

----------------------------------------------------------------------
local function init()
  L = T[system.getLocale()] or T.en
  T = nil                                                          -- andere Sprache freigeben
  loadSensors()
  swStart, swReset = system.pLoad("swStart"), system.pLoad("swReset")
  avgEvery  = system.pLoad("avgEvery", 10)
  aEnl, aClimb, aStart = system.pLoad("aEnl", ""), system.pLoad("aClimb", ""), system.pLoad("aStart", "")
  aAlt      = system.pLoad("aAlt", "")
  cdMode    = system.pLoad("cd", 2)
  entryTime = math.max(MIN_ENTRY, system.pLoad("entry", MIN_ENTRY))
  climbThr  = system.pLoad("climbDm", 3) / 10      -- 0,3 m (Reglement: ununterbrochenes Sinken)
  minAlt    = system.pLoad("minAlt", 5)
  minSink   = system.pLoad("sinkDm", 0) / 10        -- 0 = "auch sehr minimal"
  warnAlt   = system.pLoad("warnAlt", 700)
  maxScore  = system.pLoad("maxScore", 750)
  maxAlt    = system.pLoad("maxAlt", 400)
  enlThr    = system.pLoad("enlThr", 300)
  kmFrom    = system.pLoad("kmFrom", 5)

  package.loaded["xcshare"] = share                -- fuer VSGL2 (Brille)
  system.registerForm(1, MENU_APPS, appName, initForm, nil, nil, closeForm)
  system.registerTelemetry(1, appName, 4, printTele)
  collectgarbage()
end

local function destroy()
  system.unregisterTelemetry(1)
  if package.loaded["xcshare"] == share then package.loaded["xcshare"] = nil end
end

return { init = init, loop = loop, destroy = destroy,
         author = "JetiDeck (nach LeonAir RC)", version = "2.10.0", name = appName }
