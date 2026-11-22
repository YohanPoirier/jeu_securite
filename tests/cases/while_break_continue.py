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
