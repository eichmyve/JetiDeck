# JetiDeck

Lua-Apps für Jeti-Sender (DS-12, DC/DS-24) rund um Segelflug-Wettbewerbe und die ENGO-2-Brille.

| App | Zweck |
|---|---|
| `lua/XCFLIGHT.lua` | **XC-Flight**: Start-Erkennung und Wertungsflug nach dem Reglement der Free Glide League (Einflugzeit, Höhen-/ENL-/Motorregeln, Strecke, Ø-Geschwindigkeit, Zeitwertungen). Testfassung mit Log-Simulation. |
| `lua/flug/XCFLIGHT.lc` | Flugfassung von XC-Flight für den Sender (ohne Simulation, kompiliert). |
| `lua/VSGL2.lua` | Robuster Ersatz für die „VSpeak glasses“-App (ENGO 2 über das VSpeak-Modul an P1), mit Diagnose und Brillenseiten aus XC-Flight. |
| `lua/LCDUMP.lua` | Hilfs-App für den JETI-Studio-Emulator: kompiliert Apps zu `.lc`. |
| `lua/P1TEST.lua` | Test der seriellen Schnittstelle P1/COM1. |

Werkzeuge in `tools/`: Log-Generator für die Simulation (`simlog.py`), Bau der Flugfassung
(`build_flight.py`), Disassembler für Jeti-Lua-5.3-Bytecode (`luadis53.py`).

Dokumentation: `analyse/xc-flight/ANALYSE.md` (XC-Flight, Reglement-Abgleich, Speicher) und
`claude/P1-Schnittstelle-Notizen.md` (P1, VSpeak-Protokoll, Emulator).

Nicht enthalten sind Dateien Dritter (Jeti-API-Dokumentation, VSpeak-App, die Original-App,
auf der XC-Flight aufbaut).

## Lizenz

MIT, siehe [LICENSE](LICENSE). Nutzung auf eigene Gefahr; die Apps ersetzen nicht die
Auswertung nach Reglement (gewertet wird aus der IGC-Datei).
