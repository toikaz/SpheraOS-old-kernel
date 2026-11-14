n = 0
while n < 10
    n += 1
    if n % 2 == 0
        continue
    end
    if n > 7
        break
    else
        print n, " odd"
    end
end
print "done n=", n
for i = 10 to 1 step -3
    print "down ", i
end
gosub sq
print "after gosub"
goto fin
print "skipped"
sq:
print "in sq"
return
fin:
print "end of script"
