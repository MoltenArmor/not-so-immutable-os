# not-so-immutable-os
A system built with mkosi for my own usage.

This system is based on Debian, using as many systemd components as we can. Basically it is based on the idea of [immutable `/usr`](https://0pointer.net/blog/fitting-everything-together.html), but it does not enable secure boot and verity by default.

Profiles:
- `ext-only`: Enable some special config to build sysext images only.

Sysext apps:
- `ext-desktop`: Desktop environment, it has these profiles:
  - `xfce`: Include XFCE desktop environment in the ext.
  - `mate`: Include MATE desktop environment in the ext.
  - `gnome`: Include GNOME desktop environment in the ext.
  - `lxqt`: Include LXQT desktop environment in the ext.
- `ext-zsh`: Zsh.
- `ext-chromium`: Chromium browser.
- `ext-incus`: Incus system container and VM manager, plus qemu.
- `ext-podman`: Podman container tool and `podman-docker` symlink.
- `ext-vmware`: VMWare tools.
- `ext-breeze`: KDE Breeze dependencies.
- `ext-kate`: Kate editor.
- `ext-ncat`: Netcat.
- `ext-virt-viewer`: Virt viewer tool.
- `ext-apt-file`: apt-file command-line tool.
- `ext-mkosi-tools`: Tools for using mkosi to build other distros.
- `ext-gnome-boxes`: GNOME Boxes VM tool.
- `ext-gnome-connections`: GNOME Connections.

To build it:

```
mkosi --dependency base build
```

To try it in VM:

```
mkosi --console gui vm
```

To apply update:

```
mkosi --dependency base sysupdate update
```

To build sysext images:

```
# Enable profiles you are using.
mkosi --profile ext-only [--dependency <APP>] build
```

For example, to build XFCE:
```
mkosi --profile ext-only --dependency base --profile xfce build
```

Enter volatile RW mode:
```
enter-rw
```

Exit volatile RW mode and drop all operations:
```
exit-rw
```

Execute command with `/etc` writable:
```
unlock-etc [-d|--directly] <command>
```

Tips:
- After attaching sysext (and their confext dependencies) images, you are recommended to run `unlock-etc (systemd-sysusers && systemd-tmpfiles --create)`.
- After attaching GNOME-related sysext images (for example, `ext-gnome-boxes`), you **HAVE TO** run `run0 glib-compile-schemas /usr/share/glib-2.0/schemas/ --targetdir=/var/lib/glib-2.0/schemas/` to use these apps.
