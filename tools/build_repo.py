"""App-Quelle fuer Jeti Studio erzeugen: repository/apps.json

Jeti Studio: Datei > Konfiguration > App-Quellen ->
    https://eichmyve.github.io/JetiDeck/repository/apps.json
Danach lassen sich die Apps im App-Manager installieren und aktualisieren.

Aufbau wie bei LeonAirRC/Jeti-Lua-Apps: je App Name/Version/Autor/Beschreibung/Icon/hw
und eine Dateiliste mit url, destination (Pfad auf der SD-Karte), size und hash
(SHA-1 ueber den Dateiinhalt). Ausgeliefert wird ueber GitHub Pages.

Aufruf (nach jedem neuen .lc):  python tools/build_repo.py
Das Release-Datum einer App bleibt, solange sich keine ihrer Dateien aendert.
"""
import datetime
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "repository", "apps.json")
BASE = "https://eichmyve.github.io/JetiDeck/"

# Senderkennungen wie bei LeonAir (Bedeutung nicht dokumentiert; dort fuer alle Farbdisplay-Sender)
HW = [674, 675, 676, 677, 678, 679, 680, 652, 653, 3857, 3858]

APPS = [
    {
        "key": "XCFlight",
        "name": {"de": "XC-Flight", "en": "XC-Flight"},
        "source": "lua/flug/XCFLIGHT.lua",          # Version wird hier gelesen
        "files": [("lua/flug/XCFLIGHT.lc", "Apps/XCFLIGHT.lc")],
        "icon": "repository/xcflight.png",
    },
    {
        "key": "VSGL2",
        "name": {"de": "VSpeak glasses 2", "en": "VSpeak glasses 2"},
        "source": "lua/VSGL2.lua",
        "files": [("lua/VSGL2.lc", "Apps/VSGL2.lc")],
        "icon": "repository/vsgl2.png",
    },
    {
        "key": "CHGlide",
        "name": {"de": "CH_Glide", "en": "CH_Glide"},
        "source": "lua/CH_Glide.lua",
        "files": [("lua/CH_Glide.lc", "Apps/CH_Glide.lc")],
        "icon": "repository/chglide.png",
    },
]

DAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
MONTHS = ["Jan", "Feb", "Mrz", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]


def jeti_date(d):
    # Format wie in LeonAirs apps.json, z. B. "Mo Okt 21 00:00:00 2024"
    return f"{DAYS[d.weekday()]} {MONTHS[d.month - 1]} {d.day} 00:00:00 {d.year}"


def read_version(path):
    m = re.search(r'version\s*=\s*"([^"]+)"', open(path, encoding="utf-8").read())
    if not m:
        sys.exit(f"keine Version in {path}")
    return m.group(1)


def main():
    old = {}
    if os.path.exists(OUT):
        for a in json.load(open(OUT, encoding="utf-8")).get("applications", []):
            old[a["name"]["en"]] = a
    today = jeti_date(datetime.date.today())
    apps = []
    for spec in APPS:
        version = read_version(os.path.join(ROOT, spec["source"]))
        files = []
        for src, dst in spec["files"]:
            data = open(os.path.join(ROOT, src), "rb").read()
            # Plausibilitaet: die .lc muss die Versionsnummer der Quelle enthalten
            if src.endswith(".lc") and version.encode() not in data:
                sys.exit(f"{src} passt nicht zu Version {version} - .lc neu erzeugen")
            files.append({
                "destination": dst,
                "hash": hashlib.sha1(data).hexdigest(),
                "size": len(data),
                "url": BASE + src,
            })
        prev = old.get(spec["name"]["en"])
        same = prev and prev.get("version") == version and prev.get("files") == files
        apps.append({
            "author": "JetiDeck",
            "description": {
                "de": BASE + f"repository/doc/{spec['key']}-de.html",
                "en": BASE + f"repository/doc/{spec['key']}-en.html",
            },
            "files": files,
            "hw": HW,
            "id": 0,
            "name": spec["name"],
            "previewIcon": BASE + spec["icon"],
            "releaseDate": prev["releaseDate"] if same else today,
            "version": version,
        })
        print(f"{spec['name']['en']} {version}: " + ", ".join(f"{f['destination']} {f['size']} B" for f in files))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"applications": apps}, f, indent=4, ensure_ascii=False)
        f.write("\n")
    print("geschrieben:", OUT)


if __name__ == "__main__":
    main()
