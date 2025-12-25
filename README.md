# Sh9 - a somewhat better shell for Inferno OS

How is it different from out-of-the box shell ?

* Supports left/right, home/end keys for line editing
* Supports up/down keys for history navigation
* Has current working directory and username in its prompt instead of just ";"

Hopefully will get more tiny conveniences of modern-ish shells

## Build and install

Run this to build dis files and install module files:

```
mk clean; mk; mk install
```

## Current progress

* variable substitution: yes
* command calling: yes
* command output substitution: no
* scripts: no
* if/elif/else conditional execution: no
* for loop: no
* while loop: no
* functions/procedures: no
* keyboard interrupt handling: no
* arrays: no
* tab completion: no
