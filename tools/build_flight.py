"""Flugfassung von XC-Flight erzeugen (ohne Log-Simulation).

Quelle:  lua/XCFLIGHT.lua   (Testfassung mit Simulation)
Ziel:    lua/flug/XCFLIGHT.lua

Markierungen in der Quelle:
  Zeile endet mit  --@sim        -> Zeile faellt weg
  Zeile  --@sim{  bis  --@sim}   -> Block faellt weg (nicht verschachtelt)
  Zeile beginnt mit --@flight    -> Rest der Zeile wird Code (Einrueckung bleibt)

Aufruf:  python tools/build_flight.py
Danach die .lc im Emulator mit LCDUMP.lua erzeugen (siehe analyse/xc-flight/ANALYSE.md).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "lua", "XCFLIGHT.lua")
DST = os.path.join(ROOT, "lua", "flug", "XCFLIGHT.lua")


def build(text):
    out, skip = [], False
    for n, line in enumerate(text.split("\n"), 1):
        s = line.strip()
        if s == "--@sim{":
            if skip:
                sys.exit(f"Zeile {n}: --@sim{{ verschachtelt")
            skip = True
            continue
        if s == "--@sim}":
            if not skip:
                sys.exit(f"Zeile {n}: --@sim}} ohne Anfang")
            skip = False
            continue
        if skip or line.rstrip().endswith("--@sim"):
            continue
        m = re.match(r"^(\s*)--@flight (.*)$", line)
        if m:
            line = m.group(1) + m.group(2)
        out.append(line)
    if skip:
        sys.exit("--@sim{ ohne Ende")
    return "\n".join(out)


def main():
    src = open(SRC, encoding="utf-8").read()
    dst = build(src)
    # Kontrolle: kein Simulator-Bezug mehr im Code (Kommentare ausgenommen)
    code = re.sub(r"--\[\[.*?\]\]", "", dst, flags=re.S)
    code = "\n".join(l.split("--")[0] for l in code.split("\n"))
    left = sorted(set(re.findall(r"\b(sim\w*|setSim|xcsim)\b", code)))
    if left:
        sys.exit("Simulator-Reste in der Flugfassung: " + ", ".join(left))
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    open(DST, "w", encoding="utf-8", newline="\n").write(dst)
    print(f"{DST}: {len(dst.encode('utf-8'))} Bytes (Quelle {len(src.encode('utf-8'))})")


if __name__ == "__main__":
    main()
