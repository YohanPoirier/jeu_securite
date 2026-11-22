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
