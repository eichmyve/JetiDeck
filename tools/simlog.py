#!/usr/bin/env python3
"""Erzeugt ein synthetisches Jeti-Telemetrie-Log fuer die XC-Flight-Log-Simulation.

Szenario "standard" - Ablauf (Sekunden):
    0-10    am Boden, Hoehe 0, ENL 30
   10-40    Motorsteigflug 4 m/s auf 120 m, ENL 850
   40-45    Motor aus (ENL 40), Ausschweben: Hoehe steigt noch 120 -> 122 m
   45-100   Gleiten, Sinken 1,0 m/s (mit Rauschen)
  100-160   Thermik, Steigen 1,5 m/s, Kreisen
  160-400   Gleiten, Sinken 0,5 m/s, 18 m/s nach Osten
  400-420   Landeanflug auf 0 m

Szenario "400" (Vorgabe des Users 2026-11-24) - Ablauf (Sekunden):
    0-2     am Boden, Hoehe 0, ENL 30
    2-12    Steigen in 10 s auf 410 m, ENL 1000
   12-22    Motor aus (ENL 40 < 300), Gleiten 410 -> 398 m (unter 400 m ab ~20 s)
   22-32    weiter Gleiten 398 -> 386 m (= Einflugzeit bei Start um 22 s)
   32-42    Abstieg bis zur Landung 386 -> 0 m
   42-47    gelandet

Szenario "regel" (Reglement-Test XC-Flight 2.8, ~145 s):
    0-2 Boden; 2-12 Motor auf 300 m (ENL 1000); 12-14 Motor aus, Hoehe gleich
   14-60   minimales Sinken 0,05 m/s (gueltiger Start trotz < 1 m in 10 s)
   60-62   Sturzflug 5 m/s mit ENL 800 (ENL-Spitze ohne Steigen = erlaubt)
   62-90   Gleiten 0,5 m/s
   90-105  Motor wieder an: Steigen 3 m/s, ENL 900 (> 8 s) -> ungueltig vor 30 min
  105-145  Gleiten und Landung

Szenario "hoch" (Reglement-Test XC-Flight 2.8, ~260 s):
    0-2 Boden; 2-12 Motor auf 300 m; 12-14 Motor aus
   14-40   Gleiten 0,5 m/s
   40-260  Streckenflug 25 m/s mit Steigen 2,2 m/s: ~5 km bei ~220 s,
           700 m bei ~227 s (Vorwarnung), ueber 750 m bei ~250 s (ungueltig)

Kanaele:
  SimVario (1000000001): 1 Rel. altit [m, 1 Dez.], 2 ENL [0..1000]
  SimGPS   (1000000002): 1 Latitude, 2 Longitude (Typ 9), 3 Speed [km/h]

Aufruf:  python simlog.py [ausgabe.log] [szenario]
         Standard: lua/sim/sim.log, Szenario "standard"; z. B.
         python simlog.py lua/sim/sim_400.log 400
"""
import math
import random
import sys

random.seed(42)
OUT = sys.argv[1] if len(sys.argv) > 1 else "lua/sim/sim.log"
SCENARIO = sys.argv[2] if len(sys.argv) > 2 else "standard"

VARIO, GPS = "1000000001", "1000000002"
LAT0, LON0 = 47.400000, 8.550000          # Startplatz (frei gewaehlt)
M_PER_DEG_LAT = 111320.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))


def gps_raw(deg_val):
    d = int(abs(deg_val))
    minutes = (abs(deg_val) - d) * 60
    return (d << 16) | int(round(minutes * 1000))


def profile_400(t):
    """Szenario "400": Hoehe [m], ENL, Geschwindigkeit [m/s], Richtung [Grad]."""
    if t < 2:
        return 0.0, 30, 0.0, 0
    if t < 12:
        return 41.0 * (t - 2), 1000, 15.0, 0          # 0 -> 410 m in 10 s
    if t < 22:
        return 410 - 1.2 * (t - 12), 40, 18.0, 90      # 410 -> 398 m
    if t < 32:
        return 398 - 1.2 * (t - 22), 40, 18.0, 90      # 398 -> 386 m
    if t < 42:
        return max(0.0, 386 - 38.6 * (t - 32)), 40, 15.0, 90   # Landung
    return 0.0, 30, 0.0, 90


def profile_regel(t):
    """Szenario "regel"."""
    if t < 2:
        return 0.0, 30, 0.0, 0
    if t < 12:
        return 30.0 * (t - 2), 1000, 15.0, 0
    if t < 14:
        return 300.0, 40, 18.0, 90
    if t < 60:
        return 300 - 0.05 * (t - 14), 40, 18.0, 90
    if t < 62:
        return 297.7 - 5.0 * (t - 60), 800, 30.0, 90
    if t < 90:
        return 287.7 - 0.5 * (t - 62), 40, 18.0, 90
    if t < 105:
        return 273.7 + 3.0 * (t - 90), 900, 20.0, 90
    if t < 135:
        return 318.7 - 2.0 * (t - 105), 40, 18.0, 90
    if t < 140:
        return max(0.0, 258.7 - 52.0 * (t - 135)), 40, 15.0, 90
    return 0.0, 30, 0.0, 90


def profile_hoch(t):
    """Szenario "hoch"."""
    if t < 2:
        return 0.0, 30, 0.0, 0
    if t < 12:
        return 30.0 * (t - 2), 1000, 15.0, 0
    if t < 14:
        return 300.0, 40, 18.0, 90
    if t < 40:
        return 300 - 0.5 * (t - 14), 40, 18.0, 90
    return 287.0 + 2.2 * (t - 40), 40, 25.0, 90


def profile(t):
    """Hoehe [m], ENL, Geschwindigkeit [m/s], Richtung [Grad] zum Zeitpunkt t."""
    if t < 10:
        return 0.0, 30, 0.0, 0
    if t < 40:
        return 4.0 * (t - 10), 850, 15.0, 0
    if t < 45:
        return 120 + 2.0 * (t - 40) / 5, 40, 20.0, 45
    if t < 100:
        return 122 - 1.0 * (t - 45), 40, 18.0, 90
    if t < 160:
        return 67 + 1.5 * (t - 100), 40, 12.0, (t - 100) * 18 % 360   # Kreisen
    if t < 400:
        return 157 - 0.5 * (t - 160), 40, 18.0, 90
    if t < 420:
        return max(0.0, 37 - 1.85 * (t - 400)), 40, 10.0, 90
    return 0.0, 30, 0.0, 90


def main():
    prof = {"400": profile_400, "regel": profile_regel, "hoch": profile_hoch}.get(SCENARIO, profile)
    end_t = {"400": 47, "regel": 145, "hoch": 260}.get(SCENARIO, 425)
    lines = [
        f"# XC-Flight Testflug (synthetisch, Szenario {SCENARIO})",
        f"000000000;{VARIO};0;SimVario;",
        f"000000000;{VARIO};1;Rel. altit;m",
        f"000000000;{VARIO};2;ENL;",
        f"000000000;{GPS};0;SimGPS;",
        f"000000000;{GPS};1;Latitude;",
        f"000000000;{GPS};2;Longitude;",
        f"000000000;{GPS};3;Speed;km/h",
    ]
    north = east = 0.0
    dt = 0.2
    t = 0.0
    while t <= end_t:
        ms = int(round(t * 1000)) + 1
        alt, enl, v, hdg = prof(t)
        north += v * math.cos(math.radians(hdg)) * dt
        east += v * math.sin(math.radians(hdg)) * dt
        noise = {"400": 0.2, "regel": 0.05, "hoch": 0.05}.get(SCENARIO, 0.3)
        noisy = max(0.0, alt + random.uniform(-noise, noise)) if alt > 0 else 0.0
        enl_n = min(1000, max(0, enl + random.randint(-15, 15)))   # Skala 0..1000
        lines.append(f"{ms:09d};{VARIO};1;1;1;{int(round(noisy * 10))};2;1;0;{enl_n}")
        if abs(t - round(t)) < 1e-6:                      # GPS 1x pro Sekunde
            lat = LAT0 + north / M_PER_DEG_LAT
            lon = LON0 + east / M_PER_DEG_LON
            lines.append(f"{ms + 5:09d};{GPS};1;9;0;{gps_raw(lat)};2;9;1;{gps_raw(lon)};"
                         f"3;1;0;{int(round(v * 3.6))}")
        t = round(t + dt, 3)
    with open(OUT, "w", encoding="ascii", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{OUT}: {len(lines)} Zeilen")


if __name__ == "__main__":
    main()
