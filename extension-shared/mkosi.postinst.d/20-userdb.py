#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
# pyright: strict
"""Auto-generate systemd-userdbd drop-ins for accounts added by an extension.

During an mkosi extension build (Overlay=yes), package maintainer scripts and
sysusers.d fragments create system users, groups, and memberships in
$BUILDROOT/etc/{passwd,group}.  Because mkosi strips overlay files that also
exist in BaseTrees when finalizing the image, those entries would otherwise be
lost at runtime.

This host-side postinst script invokes systemd-sysusers inside the image via
mkosi-chroot, diffs $BUILDROOT/etc/{passwd,group} against BaseTrees, allocates
deterministic collision-free UIDs/GIDs in a dedicated range, and writes
systemd-userdbd JSON drop-ins and numeric symlinks under
$BUILDROOT/usr/lib/userdb/.  Existing hand-maintained drop-ins always win.
"""

import dataclasses
import hashlib
import json
import logging
import os
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import cast

# Dedicated deterministic ID block: above Debian's 100..299 static/hand-managed
# range and below systemd-sysusers' top-down dynamic allocation (~900..999).
AUTO_ID_MIN = 300
AUTO_ID_MAX = 899

BUILDROOT = Path(os.environ["BUILDROOT"])
MKOSI_CONFIG = Path(os.environ["MKOSI_CONFIG"])
SRCDIR = Path(os.environ["SRCDIR"])


logging.basicConfig(level=logging.INFO, stream=sys.stderr)


@dataclasses.dataclass(frozen=True, slots=True)
class PasswdEntry:
    name: str
    uid: int
    gid: int
    gecos: str
    home: str
    shell: str


@dataclasses.dataclass(frozen=True, slots=True)
class GroupEntry:
    name: str
    gid: int
    members: frozenset[str]


@dataclasses.dataclass(frozen=True, slots=True)
class UserdbSnapshot:
    users: Mapping[str, int]
    groups: Mapping[str, int]
    memberships: frozenset[tuple[str, str]]


def parse_passwd(path: Path) -> Mapping[str, PasswdEntry]:
    if not path.is_file():
        return {}
    return {
        f[0]: PasswdEntry(f[0], int(f[2]), int(f[3]), f[4], f[5], f[6])
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if (line := raw.strip())
        and not line.startswith("#")
        and len(f := line.split(":")) >= 7
        and f[2].isdigit()
        and f[3].isdigit()
    }


def parse_group(path: Path) -> Mapping[str, GroupEntry]:
    if not path.is_file():
        return {}
    return {
        f[0]: GroupEntry(f[0], int(f[2]), frozenset(m for m in f[3].split(",") if m))
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if (line := raw.strip())
        and not line.startswith("#")
        and len(f := line.split(":")) >= 4
        and f[2].isdigit()
    }


def load_userdb(userdb_dir: Path) -> UserdbSnapshot:
    if not userdb_dir.is_dir():
        return UserdbSnapshot({}, {}, frozenset())

    users: dict[str, int] = {}
    groups: dict[str, int] = {}
    memberships: set[tuple[str, str]] = set()

    for p in sorted(userdb_dir.iterdir()):
        if p.is_symlink() or not p.is_file():
            continue
        name = p.name
        if name.endswith(".membership"):
            u, sep, g = name.removesuffix(".membership").partition(":")
            if sep and u and g:
                memberships.add((u, g))
            continue
        if not name.endswith((".user", ".group")):
            continue
        try:
            raw = cast(object, json.loads(p.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as e:
            logging.warning(f"Skipping invalid JSON {p}: {e}")
            continue
        if not isinstance(raw, dict):
            continue
        data = cast(dict[str, object], raw)
        if name.endswith(".user"):
            if isinstance(u := data.get("userName"), str) and isinstance(
                uid := data.get("uid"), int
            ):
                users[u] = uid
        elif isinstance(g := data.get("groupName"), str) and isinstance(
            gid := data.get("gid"), int
        ):
            groups[g] = gid

    return UserdbSnapshot(users, groups, frozenset(memberships))


def resolve_base_trees(config: Path, src_root: Path) -> tuple[Path, ...]:
    """Map host BaseTrees paths from $MKOSI_CONFIG into sandbox $SRCDIR paths."""
    raw = cast(dict[str, object], json.loads(config.read_text(encoding="utf-8")))
    raw_trees = raw.get("BaseTrees")
    if not isinstance(raw_trees, list) or not raw_trees:
        raise RuntimeError(f"No BaseTrees configured in {config}")

    src_mappings: list[tuple[Path, Path]] = []
    if isinstance(raw_sources := raw.get("BuildSources"), list):
        for item in cast(list[object], raw_sources):
            if isinstance(item, dict):
                entry = cast(dict[str, object], item)
                if isinstance(s := entry.get("Source"), str):
                    t = entry.get("Target")
                    dst = (
                        src_root / t.lstrip("/")
                        if isinstance(t, str) and t
                        else src_root
                    )
                    src_mappings.append((Path(s), dst))
            elif isinstance(item, str):
                src_mappings.append((Path(item), src_root))

    if not src_mappings and isinstance(raw_dir := raw.get("Directory"), str):
        src_mappings.append((Path(raw_dir), src_root))

    resolved: list[Path] = []
    for item in cast(list[object], raw_trees):
        if not isinstance(item, str):
            continue
        mapped = next(
            (
                cand
                for host_src, sandbox_dst in src_mappings
                if (host_path := Path(item)).is_relative_to(host_src)
                and (cand := sandbox_dst / host_path.relative_to(host_src)).is_dir()
            ),
            host_path if host_path.is_dir() else None,
        )
        if mapped is None:
            raise RuntimeError(f"BaseTree {host_path} is not accessible in sandbox")
        resolved.append(mapped)

    if not resolved:
        raise RuntimeError(f"Failed to resolve any BaseTrees from {config}")
    return tuple(resolved)


def generate_id(
    name: str,
    reserved: frozenset[int],
    id_min: int = AUTO_ID_MIN,
    id_max: int = AUTO_ID_MAX,
) -> int:
    """Deterministically hash ``name`` into [id_min, id_max], probing linearly."""
    span = id_max - id_min + 1
    start = int.from_bytes(hashlib.sha256(name.encode()).digest()[:4], "big") % span
    for offset in range(span):
        if (cand := id_min + ((start + offset) % span)) not in reserved:
            return cand
    raise RuntimeError(f"Exhausted ID range {id_min}..{id_max} for {name!r}")


def write_entry(
    userdb_dir: Path,
    stem: str,
    suffix: str,
    numeric_id: int,
    payload: Mapping[str, object],
) -> None:
    target = f"{stem}.{suffix}"
    _ = (userdb_dir / target).write_text(
        json.dumps(payload, indent=4) + "\n", encoding="utf-8"
    )
    link = userdb_dir / f"{numeric_id}.{suffix}"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(target)


def make_userdb(
    buildroot: Path,
    base_trees: Sequence[Path],
    *,
    id_min: int = AUTO_ID_MIN,
    id_max: int = AUTO_ID_MAX,
) -> tuple[int, int, int]:
    """Generate missing userdb drop-ins for accounts added relative to BaseTrees.

    Returns ``(new_users, new_groups, new_memberships)``.
    """
    base_users: dict[str, PasswdEntry] = {}
    base_groups: dict[str, GroupEntry] = {}
    base_udb_uids: set[int] = set()
    base_udb_gids: set[int] = set()

    for tree in base_trees:
        base_users.update(parse_passwd(tree / "etc/passwd"))
        for gname, g in parse_group(tree / "etc/group").items():
            prev = base_groups.get(gname)
            base_groups[gname] = (
                GroupEntry(gname, g.gid, prev.members | g.members) if prev else g
            )
        udb = load_userdb(tree / "usr/lib/userdb")
        base_udb_uids.update(udb.users.values())
        base_udb_gids.update(udb.groups.values())

    cur_users = parse_passwd(buildroot / "etc/passwd")
    cur_groups = parse_group(buildroot / "etc/group")
    userdb_dir = buildroot / "usr/lib/userdb"
    existing = load_userdb(userdb_dir)

    reserved_uids = frozenset(
        base_udb_uids
        | set(existing.users.values())
        | {u.uid for u in base_users.values()}
    )
    reserved_gids = frozenset(
        base_udb_gids
        | set(existing.groups.values())
        | {g.gid for g in base_groups.values()}
    )

    added_users = {k: v for k, v in cur_users.items() if k not in base_users}
    added_groups = {k: v for k, v in cur_groups.items() if k not in base_groups}

    resolved_gids: dict[str, int] = {
        **{k: g.gid for k, g in base_groups.items()},
        **existing.groups,
    }
    cur_gid_to_name = {g.gid: k for k, g in cur_groups.items()}

    groups_to_write: list[tuple[str, int]] = []
    for gname in sorted(added_groups):
        if gname in existing.groups:
            continue
        joint = (
            reserved_uids | reserved_gids
            if gname in added_users and gname not in existing.users
            else reserved_gids
        )
        gid = generate_id(gname, joint, id_min, id_max)
        reserved_gids |= {gid}
        resolved_gids[gname] = gid
        groups_to_write.append((gname, gid))

    users_to_write: list[tuple[PasswdEntry, int, int]] = []
    for uname in sorted(added_users):
        if uname in existing.users:
            continue
        u = added_users[uname]
        same_gid = resolved_gids.get(uname)
        uid = (
            same_gid
            if same_gid is not None
            and id_min <= same_gid <= id_max
            and same_gid not in reserved_uids
            else generate_id(uname, reserved_uids, id_min, id_max)
        )
        reserved_uids |= {uid}
        primary_gname = cur_gid_to_name.get(u.gid)
        gid = (
            resolved_gids[primary_gname]
            if primary_gname is not None and primary_gname in resolved_gids
            else u.gid
        )
        users_to_write.append((u, uid, gid))

    memberships_to_write: set[tuple[str, str]] = {
        (member, gname)
        for gname, cur_g in cur_groups.items()
        for member in cur_g.members
        - (base_groups[gname].members if gname in base_groups else frozenset())
        if (member, gname) not in existing.memberships
    } | {
        (u.name, u.name)
        for u, _, gid in users_to_write
        if resolved_gids.get(u.name) == gid
        and (u.name, u.name) not in existing.memberships
    }

    if groups_to_write or users_to_write or memberships_to_write:
        userdb_dir.mkdir(parents=True, exist_ok=True)

    for gname, gid in groups_to_write:
        write_entry(userdb_dir, gname, "group", gid, {"groupName": gname, "gid": gid})
        logging.info(f"Generated group {gname} (gid={gid})")

    for u, uid, gid in users_to_write:
        write_entry(
            userdb_dir,
            u.name,
            "user",
            uid,
            {
                "userName": u.name,
                "uid": uid,
                "gid": gid,
                "realName": u.gecos or u.name,
                "homeDirectory": u.home or "/nonexistent",
                "shell": u.shell or "/usr/sbin/nologin",
                "storage": "classic",
            },
        )
        logging.info(f"Generated user {u.name} (uid={uid}, gid={gid})")

    written_memberships = 0
    for member, gname in sorted(memberships_to_write):
        path = userdb_dir / f"{member}:{gname}.membership"
        if not path.exists() and not path.is_symlink():
            _ = path.write_text("{}\n", encoding="utf-8")
            written_memberships += 1
            logging.info(f"Generated membership {member}:{gname}")

    return len(users_to_write), len(groups_to_write), written_memberships


def main() -> None:
    if (BUILDROOT / "usr/bin/systemd-sysusers").is_file():
        _ = subprocess.run(["mkosi-chroot", "/usr/bin/systemd-sysusers"], check=True)

    base_trees = resolve_base_trees(MKOSI_CONFIG, SRCDIR)
    n_users, n_groups, n_memberships = make_userdb(BUILDROOT, base_trees)
    logging.info(
        f"Done: +{n_users} user(s), +{n_groups} group(s), +{n_memberships} membership(s)"
    )


if __name__ == "__main__":
    main()
