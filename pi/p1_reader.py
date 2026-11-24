#!/usr/bin/env python3
"""Liest Telemetrie vom Jeti-Stecker P1 (COM1) am Raspberry Pi mit.

Versteht:
  * P1TEST.lua im CSV-Modus  ->  "P1,seq,ms,txV,rx1Q,rx1V,s1,s2,s3\\r\\n"
  * P1TEST.lua im JSON-Modus ->  ein JSON-Objekt pro Zeile
  * VSpeak glasses            ->  JSON-Objekte OHNE Zeilenende, direkt aneinander
                                  ({"res_addr":..,"page":..,"value":[..],..}{...})

Verdrahtung (3,3 V, KEIN Pegelwandler nötig):
  P1-4 (COM1 TX)  ->  Pi GPIO15 / RXD (Pin 10)
  P1-1 (GND)      ->  Pi GND (z. B. Pin 6)
  optional P1-3 (COM1 RX) <- Pi GPIO14 / TXD (Pin 8), nur für --echo-Tests
  P1-2/P1-6 NICHT mit dem Pi verbinden.

Aufruf:
  python3 p1_reader.py                      # /dev/serial0, 115200
  python3 p1_reader.py --log p1.csv         # zusätzlich mitschreiben
  python3 p1_reader.py --raw                # rohe Bytes als Hex anzeigen

Benötigt: sudo apt install python3-serial
"""
import argparse
import csv
import json
import sys
import time

import serial


def parse_csv(line):
    f = line.split(",")
    if len(f) < 9 or f[0] != "P1":
        return None
    keys = ["seq", "ms", "txV", "rx1Q", "rx1V", "s1", "s2", "s3"]
    return dict(zip(keys, f[1:9]))


class JsonStream:
    """Zerlegt einen Bytestrom in vollständige JSON-Objekte per Klammerzählung."""

    def __init__(self):
        self.buf = ""

    def feed(self, text):
        self.buf += text
        out = []
        while True:
            start = self.buf.find("{")
            if start < 0:
                self.buf = ""
                return out
            depth, in_str, esc, end = 0, False, False, -1
            for i in range(start, len(self.buf)):
                c = self.buf[i]
                if in_str:
                    if esc:
                        esc = False
                    elif c == "\\":
                        esc = True
                    elif c == '"':
                        in_str = False
                elif c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            if end < 0:
                self.buf = self.buf[start:]
                if len(self.buf) > 8192:      # Müll verwerfen
                    self.buf = ""
                return out
            chunk = self.buf[start:end + 1]
            self.buf = self.buf[end + 1:]
            try:
                out.append(json.loads(chunk))
            except json.JSONDecodeError:
                print(f"! defektes JSON: {chunk[:80]}", file=sys.stderr)


def show_vspeak(o):
    vals = o.get("value", [])
    units = o.get("unit", [])
    parts = [f"{v}{u}" for v, u in zip(vals, units + [""] * len(vals))]
    return (f"VSpeak page={o.get('page')} ble={o.get('ble_On')} "
            f"addr={o.get('res_addr')!r} | " + "  ".join(parts))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/serial0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log", help="CSV-Datei zum Mitschreiben")
    ap.add_argument("--raw", action="store_true", help="Rohdaten als Hex ausgeben")
    a = ap.parse_args()

    ser = serial.Serial(a.port, a.baud, timeout=0.2)
    print(f"Lausche auf {a.port} @ {a.baud} 8N1 ... (Strg+C beendet)")

    logw = None
    if a.log:
        logf = open(a.log, "a", newline="")
        logw = csv.writer(logf)

    js = JsonStream()
    line = ""
    total, t0 = 0, time.time()
    try:
        while True:
            data = ser.read(512)
            if not data:
                continue
            total += len(data)
            if a.raw:
                print(data.hex(" "))
                continue
            text = data.decode("latin-1")

            # 1) VSpeak/JSON: Objekte per Klammerzählung
            for o in js.feed(text):
                stamp = time.strftime("%H:%M:%S")
                if "res_addr" in o or "page" in o:
                    print(stamp, show_vspeak(o))
                else:
                    print(stamp, "JSON", o)
                if logw:
                    logw.writerow([time.time(), json.dumps(o, separators=(",", ":"))])

            # 2) CSV-Zeilen der Test-App
            line += text
            while "\n" in line:
                one, line = line.split("\n", 1)
                one = one.strip()
                rec = parse_csv(one)
                if rec:
                    rate = total / max(time.time() - t0, 1e-3)
                    print(f"#{rec['seq']:>5} t={rec['ms']}ms Tx={rec['txV']}V "
                          f"Q={rec['rx1Q']}% Rx={rec['rx1V']}V | "
                          f"{rec['s1']} {rec['s2']} {rec['s3']}   ({rate:.0f} B/s)")
                    if logw:
                        logw.writerow([time.time(), one])
            if len(line) > 4096:
                line = ""
    except KeyboardInterrupt:
        print(f"\n{total} Bytes empfangen.")


if __name__ == "__main__":
    main()
