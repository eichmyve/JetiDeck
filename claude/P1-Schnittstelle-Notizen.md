# Jeti P1 / VSpeak glasses – Notizen

Stand: 2026-11-24. Sprache im Projekt: Deutsch.

## Ziel
Aussetzer (eingefrorene Werte) der VSpeak-glasses-Anzeige beheben – mit dem vorhandenen
VSpeak-Modul an P1 (COM1) und einer eigenen, robusteren Lua-App auf dem Sender.

**Entscheidung 2026-11-24: Raspberry Pi und externe UART-Adapter sind ausgeschlossen.**
Diagnose und Tests laufen nur auf dem Sender selbst (Diagnosefenster, Loopback-Brücke).

## Hardware
- Sender: Jeti DC-16 II, Platine „DC24-CONT-3“, mit TX-MSW-1.
- TX-MSW-1 hängt elektrisch an T1 (Trainer-Port), nutzt P1 nur mechanisch → P1 elektrisch frei.
- Zum Test angeschlossen: Jeti DS-12, FW 5.08 (USB-Laufwerk, SD unter `D:\`).
- Engo-Brille (ActiveLook) über VSpeak-glasses-Modul.

## P1-Pinbelegung (API-Doku 1.7, S. 162, Stecker Würth 690367280676)
| Pin | Funktion |
|---|---|
| P1-1 | GND |
| P1-2 | VBAT (max. 400 mA) |
| P1-3 | COM1 RX (in den Sender) |
| P1-4 | COM1 TX (aus dem Sender) |
| P1-5 | GND |
| P1-6 | 3V3 (max. 200 mA) |

UART: 3,3 V, 8N1 fest, kein Flow-Control, nur Baudrate wählbar (`serial.setBaudRate`).
Puffer je ~10 KiB, DMA. Nur **eine** App kann COM1 belegen.

## Gerätesupport (offener Punkt 1)
- Doku: `serial`/`gpio` „Since V5.00, only DC/DS-24, DS-12, since V6.05 on DC/DS-24II“.
  DC-16 II wird nicht erwähnt.
- Die DC/DS-16-Einschränkungen (2 Apps, 50 kB Lua-Speicher) beziehen sich auf den alten DC/DS-16.
- Indiz für Support: Platine „DC24-CONT-3“ (DC-24-Plattform); VSpeak bietet die App für Duplex-Sender an
  und gibt bei Fehler „COM1 failure -> update <Gerät> (V <FW> is obsolete)“ aus → COM1 hängt
  offenbar an der Firmwareversion, nicht am Modell.
- **Test:** `lua/P1TEST.lua` installieren. Im Menü steht „COM1: OK 115200“, „init fehlgeschlagen“
  oder „keine serial-Lib (FW?)“. Mit Brücke P1-3↔P1-4 (Loopback) zählt „RX Bytes“ hoch → COM1 geht
  in beide Richtungen, ganz ohne Pi.

## VSpeak glasses V1.1 – Protokoll (aus Bytecode rekonstruiert, `tools/luadis53.py`)
Bytecode: Lua 5.3, Header 1B 4C 75 61 53 00 …, int/size_t/Instruction/Integer/Number je 4 Byte.
Debug-Infos (Namen lokaler Variablen, Zeilennummern) sind entfernt.
**Jeti-Abweichung:** Konstanten-Typ-Tags sind gegenüber Standard-Lua 5.3 um 2 verschoben
(String kurz 0x06 statt 0x04, lang 0x16 statt 0x14, Integer 0x15 statt 0x13, Kommazahl 0x05 statt
0x03, Bool 0x01 gleich; bestätigt an VS_glass.lc und an der Original-App, die XC-Flight zugrunde liegt).
→ Ein Standard-`luac` (auch mit LUA_32BITS) erzeugt **keine** auf dem Sender ladbare `.lc`.

## JETI-Studio-Emulator
- Programm: `C:\Program Files (x86)\JETI Studio\dc-sim.exe` (meldet FW 6.00) und `dc-sim2.exe`.
- Daten-/SD-Ordner: `%LOCALAPPDATA%\JETI-Studio\Emulator` (Apps in `Apps\`,
  Modelle in `Model\`, Logs in `Log\`) – entspricht der SD-Karte des Senders.
- Kein `serial`-Port zum PC getestet; `string.dump` vorhanden (siehe unten).
- Startet auch ohne JETI Studio. „Start transmitter?“ sofort mit F5 bestätigen, sonst schließt er.
- Tasten: Leertaste = Menu, Enter/→ = Enter, Esc/← = Esc, ↑/↓ = Drehrad, 1–5 = F1–F5,
  A–J = Schalter Sa–Sj rechts, Shift+A–J = links. Tasten ~0,4 s halten, sonst gehen sie teils verloren.

## .lc kompilieren (2026-11-24): möglich über den Emulator
- Der Emulator **hat** `string.dump` (erster Versuch lief nur nicht, weil LCDUMP nicht aktiv war).
- Weg: `lua/LCDUMP.lua` + Quelle in `Emulator\Apps`, LCDUMP im Emulator-Modell aktiv → beim Laden
  entsteht `Apps\<Name>.lc` (Debug-Infos entfernt).
- Ergebnis VSGL2 0.2: `VSGL2.lc` 8430 Bytes (Quelle 11884), Header identisch mit `VS_glass.lc`,
  Jeti-Typ-Tags, 27 Funktionen, mit `tools/luadis53.py` fehlerfrei lesbar.
- Offen: auf der DS-12 (FW 5.08; Emulator meldet 6.00) noch nicht getestet; unklar, welche Datei
  der Sender lädt, wenn `.lua` und `.lc` gleichnamig nebeneinander liegen.
- Ein Standard-`luac` bleibt ungeeignet (andere Typ-Tags).

## Dateien
- `lua/P1TEST.lua` – Test-App: CSV oder JSON auf COM1, Intervall einstellbar, 3 Sensorplätze,
  RX-Zähler für Loopback.
- `pi/p1_reader.py` – Pi-Mitleser, **nicht mehr verwendet** (Pi ausgeschlossen).
- `tools/luadis53.py` – Disassembler für Jeti-Lua-5.3-Bytecode.
- `lua/VSGL2.lua` – Ersatz für VS_glass mit gleichem Protokoll, aber gepuffertem Empfang
  (setzt zerstückelte/geklebte Anfragen zusammen) und Diagnosefenster (Anfragen, Antworten,
  zerstückelt, geklebt, Müllbytes, längste Lücke). Einstellungen sind eigene, nicht die von VS_glass.
  Status: läuft auf der DS-12 (FW 5.08); Diagnosefenster zweispaltig, vom User bestätigt (2026-11-24).

## Symptom (2026-11-24)
Werte auf der Brille frieren im Betrieb zeitweise ein (DS-12, FW 5.08, VS_glass V1.0).

**Offizielle Bestätigung:** Versionshistorie der VSpeak-Anleitung (Jeti, V1.1):
„1.1 – 07.2024 – gelegentliches ‚Einfrieren‘ der Daten im Brillendisplay behoben“.
Auf der DS-12 liegt V1.0 → erster Schritt: offizielle V1.1 einspielen. Die einzige echte
Logikänderung V1.0→V1.1 ist, dass `serial.onRead` nicht mehr in jedem `loop()` neu registriert wird.
Die 36-Zeichen-Prüfung ist in V1.1 aber weiterhin drin → VSGL2 bleibt als Reserve.

**Messung mit VSGL2 auf der DS-12 (2026-11-24, Brille ENGO 2, am Tisch):**
Anfragen 4839, Antworten 4806, Fehler 0, **zerstückelt 232 (~4,8 %)**, **geklebt 27**, Müll 2,
längste Lücke zwischen Anfragen 159 ms, Lücken > 1 s: 0.
→ Ursache bestätigt: Das Modul fragt lückenlos an, aber ~5 % der Anfragen kommen nicht als genau
36 Zeichen an und würden vom Original verworfen. VSGL2 beantwortet sie.
Antworten < Anfragen ist erwartbar: Kommen zwei Anfragen vor dem nächsten `loop()`, geht nur eine Antwort raus.

## VSpeak-Anleitung (Jeti) – Fakten
Quelle: https://www.vspeak-modell.de/de/glasses-module → „ausführliche Bedienanleitung“ (Jeti).
- Versorgung des Moduls: **3,3 V vom Sender** (→ P1-6), 4-poliges Kabel an P1 (roter 6-pol. Stecker).
- Nur für Jeti-Sender mit Farbdisplay.
- LED: 10-s-Blitz = App nicht aktiv (<0,5 mA); 1-s-Blitz = BLE aus (<5 mA) bzw. BLE an, Brille nicht
  verbunden (~60 mA); 1-s-Doppelblitz = Brille verbunden (~70 mA).
- BLE aus → Brille schaltet ab („sich schließendes Auge“); vor dem vollständigen Schließen zurück mit BLE an.
- Funktionstaste löscht gespeicherte Brillendaten im Modul (nötig bei Brillenwechsel) = `res_addr` 1.

## Werte zwischen Apps teilen (Test 2026-11-25, Emulator FW 6.00)
Idee: XC-Flight-Werte (Strecke, Ø-Geschw., Flugzeit) als eigene Seite über VSGL2 auf die ENGO 2.
Test mit zwei Mini-Apps und `Apps/lib/xcshare.lua` (`return {}`): beide `require("xcshare")`,
A schreibt alle 3 s, B liest → B sieht jeden Wert von A, auch nach „Reload Lua“.
Beide Apps melden dieselbe `package`-Tabelle, dasselbe `_G` und dieselbe Tabellenadresse →
alle Apps laufen in **einer** Lua-Umgebung, `package.loaded` ist gemeinsam.
Offen: auf der DS-12 (FW 5.08) nicht geprüft. Die Test-Apps sind wieder gelöscht.
Die PC-Skripte in `Documents\GlasDeck\engo2` (BLE/ActiveLook direkt) gehen vom Sender aus nicht;
Weg dort: VSpeak-Modul, je Seite 3 Werte + Einheiten + Schriftgrößen, keine Beschriftungen.
Vorgabe User (2026-11-25): Ø-Geschwindigkeit in der Brille reicht alle 2 s (Strecke und Flugzeit 1 s).
Brillenseiten XC-Flight (umgesetzt 2026-11-25: XC-Flight 2.10.0 + VSGL2 0.3):
- Anzeige 1: Strecke (m, ab 1 km km), Ø-Geschwindigkeit (km/h, alle 2 s), Flugzeit (h:mm:ss)
- Anzeige 2: Höhe (m), Einflug-Timer (Bereit „--“, 10…1 s, Flug „OK“, ungültig „X“,
  Motor nach 30 min „END“), ENL 0..1000
- VSGL2: je Seite „Quelle“ = Sensoren / XC-Flight 1 / XC-Flight 2 (Parameter `src1..3`);
  Schriftgröße je Platz bleibt einstellbar. XC-Daten älter als 3 s oder XC-Flight nicht aktiv → „-//-“.
- XC-Flight aktualisiert die Tabelle alle 0,5 s (`publish`), Ø nur alle 2 s.
- Emulator-Test (Testkopie VSGL2T gibt die Antwort jede Sekunde in der Konsole aus, kein Modul):
  XC 1 im Flug „45 m | 43.4 km/h | 0:00:03“ … Ø wechselt im 2-s-Takt; XC 2 Steigflug
  „229 m | -- | 993“, Einflugzeit „395 m | 10 s | 36“ … „2 s“, danach „OK“. Quelle bleibt nach Reload.
- Nicht getestet: echte Brille/Modul, DS-12 (FW 5.08), Zustände „X“/„END“, Schriftbreite der Flugzeit
  in „large“ auf der ENGO 2.
- Dateien: `lua/VSGL2.lua`/`.lc` (9346 B), `lua/flug/XCFLIGHT.lua`/`.lc` (19338 B).

## Offene Punkte
1. COM1 auf DC-16 II: mit P1TEST prüfen (siehe oben).
2. ~~Plus-Pin des Moduls~~ → geklärt: 3,3 V (P1-6), laut Anleitung.
3. VSGL2 auf der DS-12 testen: Diagnosefenster beim nächsten Einfrieren ablesen.
