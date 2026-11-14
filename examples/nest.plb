# nested blocks, shell commands inside scripts
a = 3
if a == 3
    if a > 5
        print "wrong"
    else
        if a < 2 then print "wrong2"
        print "inner else ok"
    end
    print "outer ok"
else
    print "wrong3"
end
if a == 0
    print "no"
end
echo shell command from script
for i = 1 to 2
    for j = 1 to 2
        print i, ",", j
    end
end
print "bye"
