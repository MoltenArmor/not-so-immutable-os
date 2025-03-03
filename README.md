# not-so-immutable-os
A system built with mkosi for my own usage.

This system is based on Debian, using as many systemd components as we can. Basically it is based on the idea of [immutable `/usr`](https://0pointer.net/blog/fitting-everything-together.html), but there are several differences:

1. It does not enable secure boot and verity by default.
2. Its `/etc` is mutable (`--mutable=yes` is enabled for `systemd-confext` by default).

Profiles:
- `desktop`: Include desktop base files in the main image, including `pipewire`, `upower`, `accountservice` and so on.
- `xfce`: Include XFCE desktop environment in the main image.
- `mate`: Include MATE desktop environment in the main image.
- `update`: Enable some special config for updating.
- `sysext-only`: Enable some special config to build sysext images only.

Sysext apps:
- `sysext-chromium`: Chromium browser.
- `sysext-incus`: Incus system container and VM manager, plus qemu.
- `sysext-vmware`: VMWare tools.
- `sysext-breeze`: KDE Breeze dependencies.
- `sysext-kate`: Kate editor.
- `sysext-avahi`: Avahi daemon and utils.
- `sysext-ncat`: Netcat.
- `sysext-virt-viewer`: Virt viewer tool.
- `sysext-apt-file`: apt-file command-line tool.

To build it:

```
mkosi --profile desktop --profile xfce build
```

To try it in VM:

```
mkosi --profile desktop --profile xfce --console gui vm
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
# Enable profiles you are using.
mkosi [--profile desktop --profile xfce] --profile sysext-only [--dependency <APP>] build
```
