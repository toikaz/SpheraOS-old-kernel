# fib.plb - first 15 Fibonacci numbers
a = 0
b = 1
for i = 1 to 15
    print a;
    print " ";
    t = a + b
    a = b
    b = t
end
print
