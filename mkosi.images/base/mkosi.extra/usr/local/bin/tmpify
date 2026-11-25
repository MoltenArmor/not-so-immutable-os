#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
# pyright: strict
"""Make a directory disposable by mounting an overlay filesystem on it.

Writes that land in a tmpified directory end up in an upper layer under
/run/tmpify (or $TMPIFY_BASE_DIR) and are thrown away when restored.

Ownership is verified directly against /proc/self/mountinfo using the
deterministic workspace path derived from the target path, so a foreign
overlay on the same mount point is never unmounted by mistake.

Usage:
    tmpify <path>                    Mount a disposable overlay on <path>
    tmpify --restore <path>          Unmount the overlay on <path>, discard writes
    tmpify --status <path> [--json]  Report how <path> is currently mounted
    tmpify --list [--json]           List every overlay this tool manages
"""

import argparse
import dataclasses
import enum
import hashlib
import json
import logging
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Self, TypedDict, cast


class MountState(enum.StrEnum):
    NOT_FOUND = "not-found"
    NOT_OVERLAY = "not-overlay"
    TMPIFIED = "tmpified"
    FOREIGN = "foreign"


class StatusPayload(TypedDict):
    path: str
    state: str
    fstype: str | None
    upperdir: str | None
    lowerdir: str | None
    owner: str | None
    stub: str | None


TMPIFY_BASE_DIR = os.getenv("TMPIFY_BASE_DIR", "/run/tmpify")

logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stderr)


@dataclasses.dataclass(frozen=True, slots=True)
class MountEntry:
    """One mount point from /proc/self/mountinfo."""

    mount_point: str
    fstype: str
    source: str
    options: Mapping[str, str]

    @property
    def upperdir(self) -> str | None:
        return self.options.get("upperdir")

    @property
    def lowerdir(self) -> str | None:
        return self.options.get("lowerdir")

    @classmethod
    def parse_mountinfo(cls, path: Path | None = None) -> tuple[Self, ...]:
        if path is None:
            path = Path("/proc/self/mountinfo")

        entries: list[Self] = []
        for line in path.read_text().splitlines():
            left, sep, right = line.partition(" - ")
            if not sep:
                continue
            lfields, rfields = left.split(), right.split()
            if len(lfields) < 6 or len(rfields) < 2:
                continue
            mount_point = (
                lfields[4]
                .replace("\\040", " ")
                .replace("\\011", "\t")
                .replace("\\012", "\n")
                .replace("\\134", "\\")
            )
            options = {
                k: v
                for opt in (rfields[2].split(",") if len(rfields) > 2 else ())
                for k, eq, v in (opt.partition("="),)
                if eq
            }
            entries.append(cls(mount_point, rfields[0], rfields[1], options))
        return tuple(entries)

    @classmethod
    def find(cls, entries: Sequence[Self], target: str) -> Self | None:
        return max(
            (
                e
                for e in reversed(entries)
                if target == e.mount_point
                or target.startswith(e.mount_point.rstrip("/") + "/")
            ),
            # Find the deepest, topmost mount point
            key=lambda e: len(e.mount_point),
            default=None,
        )


@dataclasses.dataclass(frozen=True, slots=True)
class Status:
    path: str
    state: MountState
    fstype: str | None
    upperdir: str | None
    lowerdir: str | None
    owner: str | None
    stub: str | None

    def as_payload(self) -> StatusPayload:
        return {
            "path": self.path,
            "state": self.state,
            "fstype": self.fstype,
            "upperdir": self.upperdir,
            "lowerdir": self.lowerdir,
            "owner": self.owner,
            "stub": self.stub,
        }


@dataclasses.dataclass(frozen=True, slots=True)
class OverlayTarget:
    """A directory managed (or inspected) by tmpify."""

    path: str
    base_dir: Path = Path("/run/tmpify")

    @property
    def stub(self) -> str:
        digest = hashlib.sha256(self.path.encode("utf-8")).hexdigest()[:8]
        stem = re.sub(r"[^A-Za-z0-9._-]+", "_", self.path.strip("/")) or "root"
        return f"{stem}_{digest}"

    @property
    def workspace(self) -> Path:
        return self.base_dir / self.stub

    @property
    def upperdir(self) -> Path:
        return self.workspace / "upper"

    @property
    def workdir(self) -> Path:
        return self.workspace / "work"

    def inspect(self, entries: Sequence[MountEntry]) -> Status:
        if not Path(self.path).exists():
            return Status(self.path, MountState.NOT_FOUND, None, None, None, None, None)

        mount = MountEntry.find(entries, self.path)
        if mount is None or mount.mount_point != self.path or mount.fstype != "overlay":
            return Status(
                self.path,
                MountState.NOT_OVERLAY,
                mount.fstype if mount else None,
                None,
                None,
                None,
                None,
            )

        if mount.upperdir == str(self.upperdir):
            return Status(
                self.path,
                MountState.TMPIFIED,
                "overlay",
                mount.upperdir,
                mount.lowerdir,
                "tmpify",
                self.stub,
            )

        return Status(
            self.path,
            MountState.FOREIGN,
            "overlay",
            mount.upperdir,
            mount.lowerdir,
            mount.source,
            None,
        )

    def mount(self, entries: Sequence[MountEntry]) -> None:
        if not Path(self.path).is_dir():
            raise NotADirectoryError(f"{self.path} is not a directory")
        if self.inspect(entries).state in (MountState.TMPIFIED, MountState.FOREIGN):
            raise FileExistsError(f"{self.path} is already an overlay mountpoint")

        self.upperdir.mkdir(parents=True, exist_ok=True)
        self.workdir.mkdir(parents=True, exist_ok=True)
        try:
            _ = subprocess.run(
                [
                    "mount",
                    "-t",
                    "overlay",
                    "tmpify",
                    "-o",
                    f"lowerdir={self.path},upperdir={self.upperdir},workdir={self.workdir}",
                    self.path,
                ],
                check=True,
            )
        except subprocess.CalledProcessError:
            shutil.rmtree(self.workspace, ignore_errors=True)
            raise

        logging.info(f"Successfully tmpified {self.path}")
        logging.info(f"To revert, run: tmpify --restore {self.path}")

    def restore(self, entries: Sequence[MountEntry]) -> None:
        match self.inspect(entries).state:
            case MountState.TMPIFIED:
                pass
            case MountState.FOREIGN:
                raise PermissionError(
                    f"Refusing to unmount {self.path}: overlay was not created by tmpify"
                )
            case _:
                raise ValueError(
                    f"Refusing to unmount {self.path}: not an overlay mount"
                )

        if subprocess.run(["umount", self.path], capture_output=True).returncode == 0:
            shutil.rmtree(self.workspace, ignore_errors=True)
            logging.info(f"Successfully restored {self.path}")
            return

        _ = subprocess.run(["umount", "-l", self.path], check=True)
        logging.info(
            f"Detached {self.path} lazily; workspace will be reclaimed on the next run."
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="tmpify",
        description="Make a directory disposable by mounting an overlay filesystem on it.",
    )
    _ = parser.add_argument(
        "--json", action="store_true", help="Emit machine readable output."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    _ = group.add_argument("path", nargs="?", help="Directory to make disposable.")
    _ = group.add_argument(
        "--restore",
        metavar="PATH",
        help="Unmount the overlay on PATH and discard the writes.",
    )
    _ = group.add_argument(
        "--status", metavar="PATH", help="Report how PATH is currently mounted."
    )
    _ = group.add_argument(
        "--list", action="store_true", help="List every overlay managed by this tool."
    )
    args = parser.parse_args()

    if (
        cast(str | None, args.path) is not None
        or cast(str | None, args.restore) is not None
    ) and os.geteuid() != 0:
        raise PermissionError("tmpify must be run as root")

    base_dir, entries = Path(TMPIFY_BASE_DIR), MountEntry.parse_mountinfo()

    # Reclaim leftover workspace directories no longer referenced by any active mount.
    if os.geteuid() == 0 and base_dir.is_dir():
        active_uppers = {
            e.upperdir for e in entries if e.fstype == "overlay" and e.upperdir
        }
        for stub_dir in base_dir.iterdir():
            if stub_dir.is_dir() and str(stub_dir / "upper") not in active_uppers:
                shutil.rmtree(stub_dir, ignore_errors=True)

    if cast(bool, args.list):
        prefix = f"{base_dir}/"
        statuses = tuple(
            OverlayTarget(e.mount_point, base_dir).inspect(entries)
            for e in entries
            if e.fstype == "overlay" and e.upperdir and e.upperdir.startswith(prefix)
        )
        if cast(bool, args.json):
            print(json.dumps([s.as_payload() for s in statuses], indent=2))
        else:
            for s in statuses:
                print(f"{s.path}: {s.state} ({s.stub})")
        return

    if (raw_status := cast(str | None, args.status)) is not None:
        status = OverlayTarget(str(Path(raw_status).resolve()), base_dir).inspect(
            entries
        )
        if cast(bool, args.json):
            print(json.dumps(status.as_payload(), indent=2))
        else:
            print(f"{status.path}: {status.state}")
            if status.upperdir:
                print(f"  upperdir: {status.upperdir}")
            if status.lowerdir:
                print(f"  lowerdir: {status.lowerdir}")
            if status.owner:
                print(f"  owner:    {status.owner}")
        return

    if (raw_restore := cast(str | None, args.restore)) is not None:
        OverlayTarget(str(Path(raw_restore).resolve()), base_dir).restore(entries)
        return

    if (raw_path := cast(str | None, args.path)) is None:
        raise ValueError("Missing target path")
    OverlayTarget(str(Path(raw_path).resolve()), base_dir).mount(entries)


if __name__ == "__main__":
    main()
