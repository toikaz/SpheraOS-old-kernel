# autoexec.plb - runs automatically at every boot
login:
print "Enter name: "
input a$
print "Enter password: "
input b$
if a$ == "root" and b$ == "root" then goto ok
if a$ != "root"
    print "Wrong name or password!"
    goto login
end
if b$ != "root" then print "Wrong password!"
goto login

ok:
clear
ver
sysfetch
ls
echo
print "Welcome, ", a$, "!"
