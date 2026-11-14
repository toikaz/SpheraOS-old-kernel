input "Your name? ", n$
input "Your age? ", age
print "Hi ", n$, ", next year you will be ", age + 1
s$ = "line one from plb"
save "note.txt", s$
load t$, "note.txt"
print "loaded: ", t$
