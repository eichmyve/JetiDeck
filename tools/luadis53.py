#!/usr/bin/env python3
"""Minimaler Disassembler für Lua-5.3-Bytecode (Jeti: 4-Byte int/size_t/Instruction/Integer/Number).

Aufruf:  python luadis53.py VS_glass.lc
"""
import struct
import sys

OPS = ["MOVE", "LOADK", "LOADKX", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETTABUP", "GETTABLE",
       "SETTABUP", "SETUPVAL", "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "MOD", "POW",
       "DIV", "IDIV", "BAND", "BOR", "BXOR", "SHL", "SHR", "UNM", "BNOT", "NOT", "LEN", "CONCAT",
       "JMP", "EQ", "LT", "LE", "TEST", "TESTSET", "CALL", "TAILCALL", "RETURN", "FORLOOP",
       "FORPREP", "TFORCALL", "TFORLOOP", "SETLIST", "CLOSURE", "VARARG", "EXTRAARG"]


class R:
    def __init__(self, data):
        self.d, self.p = data, 0

    def b(self):
        v = self.d[self.p]; self.p += 1; return v

    def i(self):
        v = struct.unpack_from("<i", self.d, self.p)[0]; self.p += 4; return v

    def u(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]; self.p += 4; return v

    def f(self):
        v = struct.unpack_from("<f", self.d, self.p)[0]; self.p += 4; return v

    def s(self):
        n = self.b()
        if n == 0xFF:
            n = self.u()
        if n == 0:
            return None
        v = self.d[self.p:self.p + n - 1]; self.p += n - 1
        return v.decode("latin-1")


def header(r):
    assert r.d[:4] == b"\x1bLua", "kein Lua-Bytecode"
    r.p = 4 + 1 + 1 + 6 + 5  # sig, version, format, LUAC_DATA, 5 Größenbytes
    r.p += 4 + 4             # LUAC_INT, LUAC_NUM
    return r.b()             # Anzahl Upvalues der Hauptfunktion


def const(r):
    t = r.b()
    tt = t & 0x0F
    if tt == 0:
        return "nil"
    if tt == 1:
        return "true" if r.b() else "false"
    # Jeti verschiebt die Typ-Tags um 2: Zahl 5 (statt 3), String 6 (statt 4).
    # Bit 0x10 = Variante: Integer bzw. langer String.
    if tt in (3, 5):
        return r.f() if t & 0x10 == 0 else r.i()
    if tt in (4, 6):
        return repr(r.s())
    raise ValueError(f"unbekannter Konstanten-Tag 0x{t:02x} @ {r.p - 1}")


def func(r, name, depth=0):
    src = r.s()
    line, last = r.i(), r.i()
    npar, vararg, maxs = r.b(), r.b(), r.b()
    code = [r.u() for _ in range(r.i())]
    k = [const(r) for _ in range(r.i())]
    ups = [(r.b(), r.b()) for _ in range(r.i())]
    subs_start = r.p
    nsub = r.i()
    subs = []
    for n in range(nsub):
        subs.append(func(r, f"{name}.{n}", depth + 1))
    lineinfo = [r.i() for _ in range(r.i())]
    locs = [(r.s(), r.i(), r.i()) for _ in range(r.i())]
    upn = [r.s() for _ in range(r.i())]
    return dict(name=name, line=line, last=last, npar=npar, code=code, k=k, subs=subs, ups=ups,
                lineinfo=lineinfo, locs=locs, upn=upn)


def rk(x, k):
    return f"K[{x & 0xFF}]={k[x & 0xFF]}" if x & 0x100 else f"R{x}"


def dump(fn):
    k = fn["k"]
    print(f"\n=== function {fn['name']}  (Zeilen {fn['line']}-{fn['last']}, {fn['npar']} Param.)")
    print("    upvalues:", fn["upn"], " (instack,idx):", fn["ups"])
    print("    locals  :", [l[0] for l in fn["locs"]])
    for pc, ins in enumerate(fn["code"]):
        op = ins & 0x3F
        a = (ins >> 6) & 0xFF
        c = (ins >> 14) & 0x1FF
        b = (ins >> 23) & 0x1FF
        bx = ins >> 14
        sbx = bx - 131071
        name = OPS[op] if op < len(OPS) else f"OP{op}"
        ln = fn["lineinfo"][pc] if pc < len(fn["lineinfo"]) else "?"
        if name in ("LOADK",):
            arg = f"R{a} := K[{bx}]={k[bx]}"
        elif name in ("GETTABUP",):
            arg = f"R{a} := U{b}[{rk(c, k)}]"
        elif name in ("SETTABUP",):
            arg = f"U{a}[{rk(b, k)}] := {rk(c, k)}"
        elif name in ("GETTABLE", "SELF"):
            arg = f"R{a} := R{b}[{rk(c, k)}]"
        elif name == "SETTABLE":
            arg = f"R{a}[{rk(b, k)}] := {rk(c, k)}"
        elif name in ("JMP", "FORLOOP", "FORPREP", "TFORLOOP"):
            arg = f"A={a} -> {pc + 1 + sbx}"
        elif name == "CLOSURE":
            arg = f"R{a} := closure(sub {bx})"
        elif name in ("EQ", "LT", "LE"):
            arg = f"{a} {rk(b, k)} {rk(c, k)}"
        elif name in ("ADD", "SUB", "MUL", "DIV", "MOD", "IDIV", "CONCAT"):
            arg = f"R{a} := {rk(b, k)} , {rk(c, k)}"
        else:
            arg = f"A={a} B={b} C={c}"
        print(f"  [{pc:3}] L{ln:<4} {name:9} {arg}")
    for s in fn["subs"]:
        dump(s)


if __name__ == "__main__":
    r = R(open(sys.argv[1], "rb").read())
    header(r)
    dump(func(r, "main"))
