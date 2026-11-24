# JetiDeck

Lua-Apps für Jeti-Sender (DS-12, DC/DS-24) rund um Segelflug-Wettbewerbe und die ENGO-2-Brille.

## Installation über Jeti Studio

Diese App-Quelle in Jeti Studio unter **Datei > Konfiguration > App-Quellen** eintragen:

```
https://eichmyve.github.io/JetiDeck/repository/apps.json
```

Danach lassen sich **XC-Flight** und **VSpeak glasses 2** im App-Manager von Jeti Studio
installieren und aktualisieren. Hilfeseiten: [XC-Flight](https://eichmyve.github.io/JetiDeck/repository/doc/XCFlight-de.html),
[VSpeak glasses 2](https://eichmyve.github.io/JetiDeck/repository/doc/VSGL2-de.html).

Nach einer neuen `.lc`: `python tools/build_repo.py` erzeugt `repository/apps.json` neu
(Größe und SHA-1 je Datei), dann committen und pushen.

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
auf der XC-Flight aufbaut). XC-Flight baut auf „Free Glide League“ von
[LeonAirRC/Jeti-Lua-Apps](https://github.com/LeonAirRC/Jeti-Lua-Apps) auf (MIT, Hinweis in LICENSE).

## Lizenz

MIT, siehe [LICENSE](LICENSE). Nutzung auf eigene Gefahr; die Apps ersetzen nicht die
Auswertung nach Reglement (gewertet wird aus der IGC-Datei).
