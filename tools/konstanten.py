#!/usr/bin/env python3
"""Fasst die Konstanten jeder Funktion aus einer luadis53-Ausgabe zusammen.

Aufruf:  python konstanten.py datei.dis.txt
"""
import re
import sys

PAT = re.compile(r"K\[\d+\]=('(?:[^'\\]|\\.)*'|[0-9.e+-]+)")

cur, out = None, {}
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"=== function (\S+)", line)
    if m:
        cur = m.group(1)
        out[cur] = []
        continue
    for k in PAT.findall(line):
        if k not in out[cur]:
            out[cur].append(k)
for f, ks in out.items():
    print(f, ":", " ".join(ks))
