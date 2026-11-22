#!/usr/bin/env python3
"""Génère les tests de l'interpréteur : les sorties attendues viennent de CPython.

Usage :  python3 tools/gen_tests.py      (depuis le dossier du projet)
Écrit tests/cases/NOM.py et tests/cases/NOM.out
"""
import contextlib
import io
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = os.path.join(HERE, "..", "tests", "cases")
os.makedirs(CASES, exist_ok=True)

PROGRAMS = {}

PROGRAMS["arith_entiers"] = """\
print(7 // 2, -7 // 2, 7 // -2, -7 // -2)
print(7 % 3, -7 % 3, 7 % -3, -7 % -3)
print(2 ** 10, 2 ** 0, (-2) ** 3, -2 ** 2, 0 ** 0)
print(10 / 4, 10 / 5, 7 / 2, -7 / 2)
print(1 + 2 * 3, (1 + 2) * 3, 2 * 3 ** 2, 2 ** 3 ** 2, 10 - 2 - 3, 100 // 10 // 3, 7 - 3 % 2)
print(-5, +5, - -5, -(-(-5)))
"""

PROGRAMS["bool_et_verite"] = """\
print(True + True, True * 5, False - 1, True == 1, True == True, False == 0)
print(not 0, not 1, not "", not "a", not None, not not 5)
print(0 or 5, 3 and 4, 0 and 4, "" or "x", None or 0, 1 and 0 or 7)
print(1 < 2 < 3, 3 > 2 > 2, 1 <= 1 < 2, 1 == 1 != 2, 5 > 4 > 3 > 2, 5 > 4 > 4 > 2)
print(None == None, None == 0, 0 == "", "a" != "b")
"""

PROGRAMS["chaines"] = """\
print("a" + "b", "ab" * 3, 3 * "x", "abc" == "abc", "a" < "b", "b" < "a")
print("x" * 0 == "", "x" * -1 == "")
print()
print("un", "deux", 3, None, True, 2.5)
print("saut\\nde ligne", 'guillemets "doubles"', "l'apostrophe")
print(str(12) + "!", str(True), str(None), str(-3))
"""

PROGRAMS["while_break_continue"] = """\
i = 0
total = 0
while i < 20:
    i += 1
    if i % 2 == 0:
        continue
    if i > 15:
        break
    total += i
print(i, total)
n = 27
steps = 0
while n != 1:
    if n % 2 == 0:
        n = n // 2
    else:
        n = 3 * n + 1
    steps += 1
print(steps)
while True:
    steps -= 1
    if steps < 100:
        break
print(steps)
"""

PROGRAMS["for_range"] = """\
for i in range(5):
    print(i)
for i in range(2, 5):
    print(i)
for i in range(10, 0, -3):
    print(i)
for i in range(0):
    print("jamais")
for i in range(5, 2):
    print("jamais")
for i in range(0, 10, 4):
    print(i)
print(i)
for i in range(3):
    for j in range(3):
        if j == 2:
            break
        if i == 1:
            continue
        print(i, j)
s = 0
for k in range(1, 101):
    s += k
print(s)
"""

PROGRAMS["if_elif_else"] = """\
for x in range(-2, 6):
    if x < 0:
        print(x, "negatif")
    elif x == 0:
        print(x, "zero")
    elif x < 3:
        print(x, "petit")
    elif x < 5 and x != 4:
        print(x, "moyen")
    else:
        print(x, "grand")
if 1:
    print("un")
if 0:
    print("jamais")
else:
    print("zero est faux")
if "":
    print("jamais")
elif "a":
    print("chaine non vide")
"""

PROGRAMS["augassign"] = """\
x = 10
x += 5
print(x)
x -= 3
print(x)
x *= 4
print(x)
x //= 5
print(x)
x %= 7
print(x)
x **= 3
print(x)
x /= 4
print(x)
s = "ab"
s += "cd"
s *= 2
print(s)
"""

PROGRAMS["fizzbuzz"] = """\
for n in range(1, 31):
    if n % 15 == 0:
        print("FizzBuzz")
    elif n % 3 == 0:
        print("Fizz")
    elif n % 5 == 0:
        print("Buzz")
    else:
        print(n)
"""

PROGRAMS["classiques"] = """\
for n in range(2, 61):
    premier = True
    d = 2
    while d * d <= n:
        if n % d == 0:
            premier = False
            break
        d += 1
    if premier:
        print(n)
a = 1071
b = 462
while b != 0:
    r = a % b
    a = b
    b = r
print(a)
f = 1
for i in range(1, 16):
    f *= i
print(f)
x = 0
y = 1
for i in range(20):
    t = x + y
    x = y
    y = t
print(x)
n = 98765
s = 0
while n > 0:
    s += n % 10
    n //= 10
print(s)
"""

PROGRAMS["builtins"] = """\
print(abs(-3), abs(3), abs(-2.5), abs(0))
print(min(3, 1, 2), max(3, 1, 2), min(2.5, 1), max(-1, -5))
print(int(3.7), int(-3.7), int("42"), int(True), int(-0.5))
print(str(12) + "!", str(2.5), str(None))
"""

PROGRAMS["variables_types"] = """\
x = 1
print(x)
x = "a"
print(x)
x = None
print(x)
x = 2.5
print(x)
y = x
x = 7
print(y, x)
"""

PROGRAMS["flottants"] = """\
print(0.5 + 0.25, 1.5 * 2, 3.0 // 2, 7.5 % 2, 2 ** -1, 1 / 4)
print(3 == 3.0, 2.5 < 3, 1.0 + 1)
print(7.0 // 2, -7.0 // 2, 7 // 2.0, -7 % 2.5)
"""


def run_cpython(src):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        exec(compile(src, "<cas>", "exec"), {})
    return buf.getvalue()


def gen_fuzz(seed, count):
    rnd = random.Random(seed)

    def gen(depth):
        if depth == 0 or rnd.random() < 0.25:
            r = rnd.random()
            if r < 0.7:
                return ("n", rnd.randint(-9, 12))
            if r < 0.85:
                return ("c", rnd.choice(["True", "False"]))
            return ("n", rnd.randint(0, 3))
        r = rnd.random()
        if r < 0.55:
            op = rnd.choice(["+", "-", "*", "//", "%", "+", "-", "*"])
            return ("b", op, gen(depth - 1), gen(depth - 1))
        if r < 0.65:
            return ("p", gen(depth - 1), rnd.randint(0, 3))
        if r < 0.78:
            op = rnd.choice(["<", "<=", ">", ">=", "==", "!="])
            return ("b", op, gen(depth - 1), gen(depth - 1))
        if r < 0.86:
            return ("chain", gen(depth - 1), gen(depth - 1), gen(depth - 1),
                    rnd.choice(["<", "<=", ">", ">=", "==", "!="]),
                    rnd.choice(["<", "<=", ">", ">=", "==", "!="]))
        if r < 0.93:
            return ("b", rnd.choice(["and", "or"]), gen(depth - 1), gen(depth - 1))
        if r < 0.97:
            return ("not", gen(depth - 1))
        return ("neg", gen(depth - 1))

    def src(t):
        k = t[0]
        if k == "n":
            return str(t[1]) if t[1] >= 0 else "(%d)" % t[1]
        if k == "c":
            return t[1]
        if k == "b":
            return "(%s %s %s)" % (src(t[2]), t[1], src(t[3]))
        if k == "p":
            return "(%s ** %d)" % (src(t[1]), t[2])
        if k == "chain":
            return "(%s %s %s %s %s)" % (src(t[1]), t[4], src(t[2]), t[5], src(t[3]))
        if k == "not":
            return "(not %s)" % src(t[1])
        if k == "neg":
            return "(-%s)" % src(t[1])

    lines = []
    outs = []
    tries = 0
    while len(lines) < count and tries < count * 20:
        tries += 1
        s = src(gen(4))
        try:
            v = eval(s)
        except Exception:
            continue
        if isinstance(v, int) and not isinstance(v, bool) and abs(v) > 10 ** 12:
            continue
        # évite les dépassements intermédiaires (entiers 64 bits côté Godot)
        if "**" in s and any(abs(eval(sub)) > 10 ** 15 for sub in _subexprs(s)):
            continue
        lines.append("print(%s)" % s)
    return "\n".join(lines) + "\n"


def _subexprs(s):
    """Sous-expressions parenthésées (pour détecter des valeurs intermédiaires énormes)."""
    out = []
    stack = []
    for i, ch in enumerate(s):
        if ch == "(":
            stack.append(i)
        elif ch == ")" and stack:
            j = stack.pop()
            sub = s[j:i + 1]
            try:
                v = eval(sub)
                if isinstance(v, (int, float)):
                    out.append(sub)
            except Exception:
                pass
    return out or ["0"]


PROGRAMS["fuzz_expressions_a"] = gen_fuzz(1, 400)
PROGRAMS["fuzz_expressions_b"] = gen_fuzz(2, 400)
PROGRAMS["fuzz_expressions_c"] = gen_fuzz(3, 400)

for name, src in PROGRAMS.items():
    out = run_cpython(src)
    with open(os.path.join(CASES, name + ".py"), "w", encoding="utf-8") as f:
        f.write(src)
    with open(os.path.join(CASES, name + ".out"), "w", encoding="utf-8") as f:
        f.write(out)
print("%d programmes de test générés avec CPython %s" % (len(PROGRAMS), sys.version.split()[0]))
