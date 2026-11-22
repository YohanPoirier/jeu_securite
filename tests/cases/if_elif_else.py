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
