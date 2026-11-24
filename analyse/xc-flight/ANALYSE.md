# XC-Flight – Analyse der Original-App und eigene Neufassung

Stand: 2026-11-24. Teil 1 analysiert die **Original-App von LeonAir RC** (Version 1.2.0), die auf der
DS-12 liegt; ihre Dateien liegen inhaltlich unverändert in `original/` (`app.lc`, `lang.jsn`).
Disassembliert mit `tools/luadis53.py` → `original/app.dis.txt`. Teil 2 beschreibt die eigene
Neufassung **XC-Flight**.
Rekonstruiert aus Bytecode (Debug-Infos entfernt) – Variablennamen sind meine.

## Steckbrief
| | |
|---|---|
| Name / Version | Original-App, Version 1.2.0 |
| Autor | LeonAir RC |
| Größe | 24 Funktionen, ~400 Quellzeilen |
| Sprachen | en, de (aus einer eigenen `lang.jsn` im App-Ordner; fehlt die Datei → `assert`-Abbruch) |
| Benutzt | `getSensorValueByID`, `gps.getPosition`, `gps.getDistance`, `playFile`, `playNumber`, `playBeep` |
| Benutzt **nicht** | COM1/serial, GPIO → keine Konkurrenz zu VSGL2 |
| Telemetrie | ein Vollbild-Fenster ohne Statusleiste (Größe 4), 4 Zeilen à 24 px |

## Zweck
Wettbewerbs-Helfer für einen Segelflug-Streckenwettbewerb: Nach dem Startschalter läuft eine
**Einflugzeit** (Countdown), in der Motor aus und kein Steigen erlaubt ist. Danach misst die App
**GPS-Strecke**, **Ø-Geschwindigkeit** und **Flugzeit** und sagt sie an.

## Einstellungen der Original-App
| Parameter (pSave) | Bedeutung |
|---|---|
| `enl` | ENL-Sensor (Motorlärm; > 300 = Motor läuft) |
| `alt` | Höhensensor |
| `lat`, `lon` | GPS-Breite/-Länge (nur Sensoren vom Typ 9) |
| `startsw`, `resetsw` | Start- / Reset-Schalter |
| `avgspeedsw` | Schalter „Ansage Ø Geschwindigkeit“ |
| `enlalarm`, `climbalarm`, `startSound` | Audiodateien |
| `countdownStart` | Countdown-Ansage: Aus / Stimme / Beep |
| `entrytime` | Einflugzeit 1–60 s, Standard 10 s |

13 Parameter – unter Jetis Grenze von 30. Einstellungen werden **nur im Ruhezustand** gespeichert.

## Ablauf (Zustandsautomat in `loop()`)
Schalter werden flankengesteuert gelesen (nur der Wechsel auf Wert 1 zählt).

1. **Ruhe (0):** Startschalter → Startzeit merken, Strecke = 0 → Zustand 1.
   Resetschalter setzt aus jedem Zustand alles zurück.
2. **Einflugzeit (1):**
   - ENL > 300 → ENL-Alarm.
   - Höhe **höher als beim vorigen Durchlauf** → Steig-Alarm und **Einflugzeit beginnt neu**.
   - Letzte 5 Sekunden: Countdown als Zahl (Stimme) oder Piep (4186 Hz, 200 ms).
   - Einflugzeit abgelaufen → GPS-Startpunkt setzen, Startsound → Zustand 2.
3. **Flug (2):**
   - ENL > 300 länger als 5 s → ENL-Alarm, danach alle 5 s wieder.
   - Jede Sekunde: GPS-Position lesen, Abstand zur letzten Position zur Strecke addieren.
   - Jeder volle Kilometer ab 5 km wird angesagt („x km Strecke“).
   - Ø-Schalter → Ansage Strecke·3600 / Flugzeit in km/h.

**Anzeige:** Strecke [m], Ø-Geschwindigkeit [km/h], Höhe [m], Zeit (im Flug h:mm:ss, in der
Einflugzeit die Restsekunden).

## Auffälligkeiten
| # | Befund | Wirkung | Schwere |
|---|---|---|---|
| 1 | **ENL-Alarm in der Einflugzeit ohne Sperrzeit:** `playFile(…, AUDIO_IMMEDIATE)` wird bei ENL > 300 in **jedem** `loop()` (alle 20–30 ms) aufgerufen. Laut Doku stoppt IMMEDIATE die vorige Wiedergabe. | Alarm „stottert“ bzw. startet ständig neu, solange der Motor läuft. Im Flug ist es korrekt mit 5-s-Takt gelöst. | mittel |
| 2 | **Sensoren werden als Listenposition gespeichert**, nicht als Sensor-ID. | Ändert sich die Sensorliste (anderer/zusätzlicher Sensor, andere Reihenfolge), zeigt die Auswahl unbemerkt auf einen **falschen** Sensor. Nur wenn die Position außerhalb der Liste liegt, wird sie auf „…“ zurückgesetzt. | mittel |
| 3 | **Steig-Erkennung gegen den letzten Messwert** ohne Schwelle. | Schon +1 m Rauschen des Höhensensors löst Alarm aus und startet die Einflugzeit neu. Je nach Regelwerk gewollt – praktisch empfindlich. | gering–mittel |
| 4 | **Strecke = Summe der 1-s-GPS-Abstände**. | GPS-Zittern addiert sich mit; die Strecke wird eher zu lang (v. a. langsam/kreisend). | gering |
| 5 | Sensorlisten mit allen Beschriftungen werden beim Start gebaut und **dauerhaft** gehalten (nur fürs Menü nötig). | Ein paar KB Lua-Speicher dauerhaft belegt. | gering |
| 6 | Änderungen im Menü während Einflugzeit/Flug werden angezeigt, aber **nicht übernommen** (Callback kehrt zurück). | Verwirrend: Menü zeigt anderen Wert als aktiv ist. | gering |
| 7 | Ø-Geschwindigkeit direkt nach Start: Division durch ~0. | Kurz `inf`/sehr großer Wert in der Anzeige. | kosmetisch |
| 8 | `"%d"` mit Kommazahlen (Zeit, Strecke) – funktioniert nur, weil Jeti-Lua mit `LUA_FLOORN2I` abrundet. | Auf Standard-Lua wäre das ein Fehler; auf dem Sender ok. | keine |

## Speicher
Insgesamt sparsam: `getSensorValueByID` statt voller Sensortabellen, Sprachdatei wird nach dem
Auswählen der Sprache freigegeben, am Ende des Ladens `collectgarbage()`. Einziger Dauerposten
sind die Sensorlisten (Punkt 5).

## Eigene Neufassung: `lua/XCFLIGHT.lua` („XC-Flight“, ab 2.0.0)
Behebt die Punkte 1–7 oben, dazu:
- `playNumber` bekommt die englischen Beschriftungen „Distance“/„Speed“ (laut API nur diese
  werden gesprochen; das Original übergab auf Deutsch „Strecke“).
- Schalter, die beim Laden des Modells schon EIN stehen, starten keine Messung.
- Einstellbar: ENL-Schwelle, Steig-Schwelle, km-Ansage ab. Texte de/en eingebaut (keine `lang.jsn`).
- Eigene Parameter-Namen → läuft unabhängig neben dem Original; Einstellungen neu vornehmen.

### Startregeln (ab 2.1.0, Vorgaben des Users)
Höhe = Sensor relativ zum Startplatz (Annahme). Alle Werte im Menü „Startregeln“ einstellbar.

| Regel | Umsetzung |
|---|---|
| R1 Einflugzeit mind. 5 m über Grund | Höhe < 5 m → Höhen-Alarm, Einflugzeit neu |
| R2 Start unter 400 m – schon vor der Einflugzeit | Startschalter bei ≥ 400 m oder ohne gültige Höhe → Alarm, **kein Start**; während der Einflugzeit ≥ 400 m → Alarm, Einflugzeit neu |
| R3 ENL unter 30 % (< 300) | ENL ≥ 300 → ENL-Alarm, Einflugzeit neu |
| R4 mind. 10 s Sinken | Einflugzeit min. 10 s (Menü-Untergrenze); Höhe über tiefstem Wert der Einflugzeit (+ Toleranz, Standard 1 m gegen Sensorrauschen) → Steig-Alarm, Einflugzeit neu |
| R4b Sinken muss messbar sein (ab 2.2.0) | Am Ende der Einflugzeit muss die Höhe mind. 1 m (Mindest-Sinken, einstellbar 0–10 m) **tiefer** sein als zu Beginn, sonst kein Start: Alarm „kein Sinken“, Einflugzeit neu |

Alarme je Art höchstens alle 5 s; ohne Audiodatei Doppelpiep. Statuszeile zeigt den letzten
Verstoß 10 s lang („! zu tief“ / „! zu hoch“ / „! ENL“ / „! Steigen“ / „! kein Sinken“). Ohne Höhensensor sind
R1/R2/R4 aus (Hinweis in der Statuszeile). Im Flug ist ENL nur noch Hinweis (Regeln gelten für den Start).

Vergleich Original 1.2.0: R1/R2 fehlen, R3 nur Alarm (Start gilt trotzdem, 300 gilt als ok),
R4 nur „höher als letzter Messwert“, Einflugzeit ab 1 s einstellbar.

### Abgleich mit dem Reglement (ab 2.8.0)
Grundlage: FREE-GLIDE-LEAGUE-Reglement, deutsche Fassung 1.0.6 (gültig seit 01.01.2024, Stand
01.01.2025). Das Reglement wertet nur die IGC-Datei; XC-Flight ist eine Hilfe für den Piloten.

| Nr | Reglement | Umsetzung 2.8.0 |
|---|---|---|
| 1 | B.3.1, 2.3.2: über 750 m AGL = Flug ungültig, ohne Toleranz | Vorwarnhöhe (700 m) → Höhen-Alarm alle 5 s, Statuszeile „! Höhe … m“; Höhe **> 750 m** (roh) → „UNGÜLTIG: über 750 m“, Werte eingefroren bis Reset; beide Werte einstellbar |
| 2 | 2.1.2: ununterbrochener Höhenverlust, „auch sehr minimal“, ≥ 10 s | Mindest-Sinken Standard **0** (Ende tiefer als Beginn), Steig-Toleranz **0,3 m**, beide in 0,1-m-Schritten; Höhe für R4/R4b geglättet (Zeitkonstante 0,5 s); R1/R2 weiter roh |
| 3 | 2.2.1.1: Motor an = ENL > 30 % und Steigen > 1 m/s länger als 8 s (auch ENL-Spitze + danach Steigen) | Steigrate im 1-s-Takt aus der geglätteten Höhe; Motor = > 8 s am Stück > 1 m/s und ENL > Grenze in dieser Steigphase oder bis 5 s davor; reine ENL-Spitze → kurzer Hinweiston (2000 Hz) |
| 4 | 2.2.1.3–2.2.1.5: Motor vor 30 min Segelflug → ungültig; danach Rückfall auf letzte Zeitwertung; Multistart verboten | vor 30 min → „UNGÜLTIG: Motor vor 30 min“; sonst „Motor: Wertung bis …“, Strecke/Zeit = Wert der letzten Zeitstufe; eingefroren bis Reset, kein neuer Start im selben Versuch |
| 5 | 1.2: Zeitwertungen 30 min, 1 h, 2 h, 3 h | Strecke bei jeder Stufe gemerkt, in der Statuszeile („30' 6.2  1h 11.8“) und als Ansage „Distance … km“ |
| 6 | 1.2, 2.3: Wertungsflug erst ab 5 km | unter 5 km Strecke grau mit „< 5 km“; bei 5 km drei hohe Pieps (1800 Hz) |

Test 2026-11-24 im Emulator (Log-Simulation):
- `sim_regel.log`: Start mit 0,05 m/s Sinken gültig (Wertung ab 0:25) ✅ · ENL-Spitze im Sturzflug ohne Folgen ✅ ·
  Motorstart (Steigen 3 m/s, ENL 900) → „UNGÜLTIG: Motor vor 30 min“, eingefroren (1,37 km, 1:07) ✅
- `sim_hoch.log`: Vorwarnung „! Höhe 700 m“ ✅ · 5,24 km schwarz/gültig ✅ · „UNGÜLTIG: über 750 m“, eingefroren
  (5,54 km, 3:46) ✅
- Testkopie (nur Emulator) mit Zeitstufen 30 s/1 min und 30-min-Grenze 45 s: Stufen „0.5' 0.5  1' 1.1“ ✅ ·
  Motor danach → „Motor: Wertung bis 1 min“, Werte = Stufe (1,10 km, 1:00) ✅

Bekannte Kleinigkeit: Bei „UNGÜLTIG: Motor“ enthält die eingefrorene Strecke die ~8 s Motorsteigflug bis zur
Erkennung, die Zeit nicht (Ø-Geschwindigkeit dadurch leicht zu hoch) – ohne Bedeutung, da ungültig.
Nicht umgesetzt (Vorschläge 7–10): Entfernung zum Startplatz, Startzeitpunkt Anfang/Ende wählbar, AGL statt
Höhe über Startplatz, genauere Streckenmessung. Audio nicht gehört; am Sender noch nicht getestet.

### Ø-Geschwindigkeit (ab 2.3.0)
Kein Schalter mehr: Im Flug wird die Ø-Geschwindigkeit automatisch im Raster ab Flugbeginn
angesagt („Ansage Ø Geschw. alle“, Standard 10 s, 5-s-Schritte bis 300 s, 0 = aus).
Ein bis 2.2.0 gespeicherter Schalter `swAvg` wird beim Laden gelöscht.

### Ganzseitige Anzeige (ab 2.4.0)
Einrichten: Timers/Sensors → Displayed Telemetry → „+“ → Lua → „XC-Flight“.
| Zustand | Inhalt |
|---|---|
| Bereit | „Bereit“ + aktuelle Höhe, Statuszeile mit Hinweisen |
| Einflugzeit | großer Countdown (FONT_MAXI) + Höhe, Statuszeile mit letztem Verstoß |
| Flug | Strecke, Ø-Geschwindigkeit, Flugdauer – je 1/3 der Fläche, Werte in FONT_MAXI |
Keine automatische Seitenumschaltung (vom User nicht gewünscht).

Ab 2.7.0: **ENL-Balken am rechten Rand** in allen Zuständen (nur wenn ein ENL-Sensor gewählt ist):
0–1000 von unten nach oben, **grün unter der ENL-Grenze, rot ab der Grenze**, waagrechter Strich =
ENL-Grenze (Standard 300). Der übrige Inhalt rückt um ~22 px nach links. Getestet im Emulator mit
`sim_400.log`: Motor (ENL 1000) voll/rot, Gleiten (ENL ~40) kurz/grün.
Hinweis: `lcd.getFgColor()` liefert nicht die Textfarbe – nach farbigem Zeichnen wird die Schrift
abhängig vom Hintergrund (`lcd.getBgColor()`) auf Schwarz bzw. Weiß zurückgesetzt.

2.4.1: Start-/Reset-Schalter, die im Menü zugewiesen werden, während sie schon auf EIN stehen,
lösen keinen Start mehr aus (Schalterstand wird beim Zuweisen übernommen).

Test 2026-11-24 im Emulator (ohne Sensoren): Bereit-, Einflugzeit- (Countdown) und Flugansicht
(0 m / 0.0 km/h / 0:00:08) dargestellt; Start per Sa: Mitte → nichts, rechts → Einflugzeit;
nach 10 s automatisch Flug.

### Ansagen und Töne (Stand 2.7.1)
| Auslöser | Ausgabe | Ohne Audiodatei |
|---|---|---|
| Startschalter ≥ 400 m / keine Höhe; Einflugzeit < 5 m oder ≥ 400 m | Höhen-Alarm, max. alle 5 s | Piep 880 Hz, 0,3 s |
| Einflugzeit ENL ≥ Grenze | ENL-Alarm, max. alle 5 s | Piep 880 Hz, 0,3 s |
| Einflugzeit Steigen / am Ende kein Sinken | Steig-Alarm, max. alle 5 s | Piep 880 Hz, 0,3 s |
| letzte 5 s der Einflugzeit | Zahl (Stimme) oder Piep 4186 Hz, 0,2 s oder aus | – |
| gültiger Start | Start-Sound | **ab 2.7.1: 2 Pieps 1500 Hz, 0,15 s** |
| Flug: ENL ≥ Grenze > 1 s | ENL-Alarm, dann alle 5 s | **ab 2.7.1: Piep 880 Hz, 0,3 s** |
| Flug: Ø-Geschwindigkeit | „Speed … km/h“, Raster 10 s (0 = aus) | – |
| Flug: volle km ab „km-Ansage ab“ | „Distance … km“ | – |
Alarme spielen sofort (unterbrechen), Zahlen-Ansagen reihen sich in die Warteschlange.
Ton im Emulator nicht geprüft (nur fehlerfreie Ausführung).

### Log-Simulation (ab 2.5.0)
Zum Testen im Emulator ohne echte Sensoren. Dateien:
- `lua/lib/xcsim.lua` → `/Apps/lib/xcsim.lua` (Modul, nur bei aktiver Simulation geladen)
- Log → `/Apps/XCFLIGHT/sim.log` (Jeti-Log-Format wie in `/Log`; eigenes oder `tools/simlog.py`)
- Menü XC-Flight → „Simulation“ → „Log-Simulation“ ein. Sensoren im Sim-Modus kommen aus dem Log-Kopf
  und werden getrennt gespeichert (`s_enl`, `s_alt`, `s_lat`, `s_lon`) – echte Zuweisungen bleiben.
- Reset-Schalter im Zustand „Bereit“ startet das Log neu; Statuszeile zeigt „SIM m:ss“.

Test 2026-11-24 mit `lua/sim/sim.log` (synthetisch, `tools/simlog.py`):
| SIM-Zeit | Phase im Log | Anzeige XC-Flight | Regel |
|---|---|---|---|
| 0:09 | am Boden, 0 m | Entry „! too low“, Countdown hängt | R1 ✅ |
| 0:33 | Motor, ENL 850 | Entry „! ENL“, Countdown hängt bei 10 s | R3 ✅ |
| 0:52 | nach Ausschweben 120→122 m | Entry „! climb“, dann Countdown läuft beim Sinken | R4 ✅ |
| ~0:55 | 10 s gesunken | Flug startet | R4b ✅ |
| 1:29 | Gleiten 18 m/s | 611 m in 34 s, Ø 63,8 km/h (Soll 64,8) | Strecke/Ø ✅ |

Test 2026-11-24 mit `lua/sim/sim_400.log` (Szenario „400“: 10 s Steigen auf 410 m mit ENL 1000,
Motor aus, Gleiten unter 400 m ab ~20,5 s, Landung 32–42 s):
| Lauf | Startschalter | Anzeige XC-Flight | Ergebnis |
|---|---|---|---|
| A | bei 0:04 (Steigflug, 82 m) | Entry „! ENL“ → ab 410 m „! too high“ → Countdown ab Unterschreiten 400 m (0:22: 8 s, 397 m) → **Wertung ab ~0:31** → Landeabstieg 0:38: 110 m, Ø 52,6 km/h | R2 in der Einflugzeit + R3 ✅ |
| B | bei ~0:20 (400 m) | **„Ready ! too high“, kein Start**; auch nach Absinken unter 400 m kein Selbststart | R2 vor der Einflugzeit ✅ |
| B | erneut bei ~0:31 (355 m, Landeabstieg) | Einflugzeit 0:31–0:41 (sinkend, > 5 m) → Wertung → gelandet, „SIM Ende“ | ✅ (Start später als geplant: Tasten kamen ~9 s verzögert an) |

### Speicher 2.8.0 (Messung 2026-11-24, Emulator, als .lua)
Grundlast leere Lua-Umgebung 25,5 kB. Quelltext 33,5 kB (`XCFLIGHT.lua`) + 5,5 kB (`xcsim.lua`).
| Zustand | Gesamt | Anteil XC-Flight |
|---|---|---|
| ohne Simulation, nach init | 78,4 kB | ≈ 53 kB |
| ohne Simulation, Bereit (mehrere Messungen) | 78,6 kB, kein Anstieg | ≈ 53 kB |
| ohne Simulation, Wertungsflug | 78,8–78,9 kB | ≈ 53 kB |
| mit Log-Simulation (Modul geladen) | 88,5 kB, kein Anstieg | ≈ 63 kB (Simulator ≈ 10 kB) |

Gegenüber 2.4.1 (≈ 38 kB) +15 kB durch Simulator-Anbindung, Regeln W1–W5 und weitere Texte.
Menü-Spitze nicht neu gemessen (2.4.1: +1 kB, mit echten Sensorlisten etwas mehr). Im Flugbetrieb
ist die Simulation aus, das Modul wird dann nicht geladen. Auf DC/DS-16/14 (50-kB-Grenze für die ganze
Lua-Umgebung) läuft XC-Flight nicht. Einsparmöglichkeiten: als gestripte .lc laden, nur eine Sprache
behalten, Simulator-Anbindung in eine Testfassung auslagern.

### 2.10.0: Werte für die Brille (2026-11-25)
XC-Flight legt alle 0,5 s sechs fertige Anzeigewerte in `package.loaded["xcshare"]` (alle Apps teilen
eine Lua-Umgebung, im Emulator geprüft). VSGL2 0.3 zeigt sie als Seite „XC-Flight 1“ (Strecke, Ø alle 2 s,
Flugzeit) oder „XC-Flight 2“ (Höhe, Einflug-Timer, ENL). Einzelheiten und Test:
`claude/P1-Schnittstelle-Notizen.md`. Flug-.lc 2.10.0: 19 338 B (2.9.0: 18 203 B).

### 2.9.0: Speicher-Optimierung, Test- und Flugfassung (Messung 2026-11-25, Emulator)
Änderungen (Verhalten unverändert):
- Nicht gewählte Sprachtabelle nach `init` freigegeben (`T = nil`).
- Simulator-Teile markiert (`--@sim`, `--@sim{ … --@sim}`, `--@flight`). `tools/build_flight.py`
  erzeugt daraus `lua/flug/XCFLIGHT.lua` ohne Simulation (prüft, dass kein Sim-Bezug übrig bleibt).
- Menü über Helfer `intRow`/`audioRow`/`switchRow`, Piep-Tabellen und doppelte Farblogik
  zusammengefasst, Aufräumzeilen für Entwicklungs-Parameter (bis 2.7.x) entfernt.

| Fassung | Datei | RAM-Anteil |
|---|---|---|
| 2.8.0 Test, .lua mit Sim | 33 517 B | ≈ 63 kB (88,6 kB gesamt) |
| 2.9.0 Test, .lua mit Sim | 33 186 B | ≈ 59 kB (84,6 kB gesamt, −4 kB) |
| 2.8.0 .lc (alles drin) | 20 912 B | ≈ 30,2 kB |
| **2.9.0 Flug, .lc** | **18 203 B** | **≈ 26,2 kB** (110,8 − 84,6 kB) |

Vom Ausgangspunkt 2.8.0 .lua ohne Sim (≈ 53 kB) auf ≈ 26 kB, also halbiert. Menü offen: +3,4 kB
(Sensorlisten, werden beim Schliessen freigegeben). Getestet: Testfassung Menü komplett (Werte,
Einheiten, Simulation), Flugfassung Menü ohne Simulations-Abschnitt, Szenario `400`: Start bei
400 m abgelehnt („zu hoch“), Start darunter gültig, Flug läuft.

Ablauf für eine neue Flug-.lc: `python tools/build_flight.py` → `lua/flug/XCFLIGHT.lua` als
`Apps/XCFLIGHT.lua` in den Emulator → `LCDUMP.lua` (FILES = XCFLIGHT) als User-App hinzufügen →
`Apps/XCFLIGHT.lc` nach `lua/flug/` kopieren → LCDUMP entfernen, Testfassung zurücklegen.
Auf den Sender gehört nur `lua/flug/XCFLIGHT.lc` (kein `lib/xcsim.lua` nötig).

### .lc gegen .lua (Messung 2026-11-24, Emulator, XC-Flight 2.8.0)
`XCFLIGHT.lc` (2.8.0) mit `LCDUMP.lua` im Emulator erzeugt (`string.dump`, gestrippt, Kopf wie VS_glass.lc);
durch die Flug-.lc 2.9.0 in `lua/flug/` ersetzt.
Messung: Mess-.lc als zweite User-App neben der laufenden .lua (mit Simulation), Differenz = Anteil .lc
(ohne Simulation, keine Sensoren gewählt).
| | .lua | .lc |
|---|---|---|
| Dateigröße | 33 517 B | 20 912 B (−38 %) |
| RAM ohne Simulation | ≈ 53 kB | ≈ 30 kB (118,8 − 88,6 kB) |
| RAM mit Simulation | ≈ 63 kB | ≈ 40 kB (geschätzt, Simulator-Modul bleibt .lua) |

Die .lc spart ≈ 23 kB RAM (−43 %): kein Parser-/Compiler-Lauf, keine Debug-Infos (Zeilennummern,
lokale Namen). Nachteil: Fehlermeldungen ohne Zeilennummer; pSave-Einstellungen hängen am
Dateinamen. Ob `XCFLIGHT.lc` die Werte von `XCFLIGHT.lua` übernimmt, ist nicht getestet
(Messung lief unter anderem Namen), nach dem Wechsel Einstellungen prüfen. Die .lc muss nach jeder Änderung an der .lua neu erzeugt
werden (Emulator: LCDUMP als User-App hinzufügen, danach wieder entfernen).

### Speicher (Messung 2026-11-24, Emulator, XC-Flight 2.4.1 als .lua)
`collectgarbage("count")` = ganze Lua-Umgebung; Grundlast mit leerer App 25,5 kB.
| Zeitpunkt | Gesamt | Anteil XC-Flight |
|---|---|---|
| nach init | 62,6 kB | ≈ 37 kB |
| Betrieb (mehrere Messungen) | 62,9–64,1 kB, kein Anstieg | ≈ 38 kB |
| Menü offen | 64,1 kB | +1 kB (Emulator ohne Sensoren; mit echten Sensoren etwas mehr) |
| Menü zu | 63,9 → 63,0 kB | wieder freigegeben |

Jeti-Regeln: 19 gespeicherte Parameter (< 30), 1 Formular + 1 Telemetriefenster (je max. 2),
keine Tabellen/Closures in `loop()`/Anzeige → kein Speicherwachstum. Die 50-kB-Grenze gilt laut Doku
nur für DC/DS-16 und DC/DS-14 (alte Generation) – dort wäre XC-Flight als .lua mit ~63 kB Gesamt zu groß.
DS-12/DC-24: gemeinsamer Speicher, keine feste Grenze dokumentiert.
Größter Posten ist der Code selbst (aus Quelltext geladen, mit Debug-Infos); Einsparpotenzial:
als gestripte .lc laden, nicht benötigte Sprache verwerfen.

Test 2026-11-24 im Emulator (dc-sim, FW 6.00): 2.0.0 bis 2.4.1 laden ohne Fehler, Menü
vollständig inkl. „Startregeln“. **Nicht getestet:** Ablauf mit Schaltern, Regelverstöße, GPS-Strecke,
Ansagen, Anzeige – und auf der DS-12.

## Verträglichkeit mit VSGL2
Kein Konflikt: Die Original-App nutzt weder COM1 noch GPIO. Beide teilen sich nur Lua-Speicher und
Rechenzeit; die Original-App macht pro `loop()` höchstens 2 Sensorabfragen + 1 GPS-Abfrage pro Sekunde.

