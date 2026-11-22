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
