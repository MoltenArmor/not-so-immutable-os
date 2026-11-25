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
mkosi --dependency base -B build
```

To test it in an VM:

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
mutablectl enter
```

`enter` makes `/etc`, `/usr` and the metadata of the package managers writable.
The package manager directories are the ones mkosi cleans up, so that every
package manager we know of can be used: `/var/lib/apt`, `/var/cache/apt`,
`/var/lib/dpkg`, `/var/lib/dnf`, `/var/cache/dnf`, `/var/lib/libdnf5`,
`/var/cache/libdnf5`, `/var/lib/rpm`, `/var/lib/pacman`, `/var/cache/pacman`,
`/var/lib/zypp`, `/var/cache/zypp`, `/var/lib/apk` and `/var/cache/apk`.

Exit volatile RW mode and drop all operations:
```
mutablectl exit
```

Execute command with `/etc` writable:
```
mutablectl unlock [-d|--directly] [--ephemeral] <command>
```

`unlock` has three modes.  By default the changes are merged into a mutable
confext, they are **not** thrown away when the command is done.  With
`--ephemeral` they land in a temporary directory and are discarded, and with
`--directly` the confexts are unmerged, so that the changes are written to the
real `/etc` and stay there.

Show the state of every layer:
```
mutablectl status [--json]
```

Make any directory disposable:
```
tmpify <directory>
```

`tmpify` is a general purpose tool: it mounts an overlay filesystem on the
directory, so that every write ends up in a throw away layer under
`/run/tmpify`.  Use it to try something out without touching the real files.

```
tmpify /some/directory       # Mount a disposable overlay on /some/directory
tmpify --restore /some/directory   # Unmount it and throw the writes away
tmpify --status /some/directory --json   # Report how it is mounted
tmpify --list                # List every overlay tmpify manages
```

`tmpify` only unmounts the overlays it created itself, it refuses to touch a
foreign overlay that happens to sit on the same path.

Tips:
- After attaching sysext (and their confext dependencies) images, you are recommended to run `mutablectl unlock systemd-tmpfiles --create`.
- After attaching GNOME-related sysext images (for example, `ext-gnome-boxes`), you **HAVE TO** run `run0 glib-compile-schemas /usr/share/glib-2.0/schemas/ --targetdir=/var/lib/glib-2.0/schemas/` to use these apps.
