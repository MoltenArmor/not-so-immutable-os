# not-so-immutable-os
A system built with mkosi for my own usage.

This system is based on Debian, using as many systemd components as we can. And it does not use SECURE BOOT.

Profiles:
- `desktop`: Include desktop base files in the main image, including `pipewire`, `upower`, `accountservice` and so on.
- `xfce`: Include XFCE desktop environment in the main image.
- `update`: Enable some special config for updating.
- `sysext-only`: Enable some special config to build sysext images only.

Sysext apps:
- `chromium`: Chromium browser.
- `incus`: Incus system container and VM manager, plus qemu.
- `vmware`: VMWare tools.

To build it:

```
mkosi --profile desktop --profile xfce build
```

To build update images:

```
mkosi --profile desktop --profile xfce --profile update sysupdate
```

To apply update:

```
mkosi --profile desktop --profile xfce --profile update sysupdate update
```

To build sysext images:

```
# Enable profiles that you are using.
mkosi [--profile desktop --profile xfce] --profile sysext-only [--dependency <APP>] build
```
