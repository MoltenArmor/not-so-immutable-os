# not-so-immutable-os
A system built with mkosi for my own usage.

This system is based on Debian, using as many systemd components as we can. And it does not use SECURE BOOT.

To build it:

```
mkosi --profile desktop --profile xfce build
```

To build update image:

```
mkosi --profile desktop --profile xfce --profile update sysupdate
```

To do update:

```
mkosi --profile desktop --profile xfce --profile update sysupdate update
```
