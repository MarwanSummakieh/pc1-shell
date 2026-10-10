#!/usr/bin/python3
"""Install user-selected Chromium MV3 ZIPs into the player's browser profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import zipfile

MAX_ARCHIVE = 64 * 1024 * 1024
MAX_EXPANDED = 128 * 1024 * 1024
MAX_FILE = 32 * 1024 * 1024
MAX_FILES = 4096
UID = re.compile(r"[0-9a-f]{32}\Z")


def safe_path(name):
    path = PurePosixPath(name)
    if not name or "\\" in name or ":" in name or "\x00" in name or path.is_absolute() or ".." in path.parts:
        raise ValueError("The ZIP contains an unsafe file path.")
    return path


def inspect_archive(source):
    source = Path(source)
    if source.stat().st_size > MAX_ARCHIVE:
        raise ValueError("Extension ZIPs must be smaller than 64 MB.")
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    with zipfile.ZipFile(source) as archive:
        files = archive.infolist()
        if len(files) > MAX_FILES:
            raise ValueError("The extension contains too many files.")
        total, seen = 0, set()
        for info in files:
            safe_path(info.orig_filename)
            key = info.filename.rstrip("/").casefold()
            if key in seen:
                raise ValueError("The ZIP contains duplicate file paths.")
            seen.add(key)
            mode = info.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR) or info.flag_bits & 1:
                raise ValueError("Extension ZIPs cannot contain links, special files, or encrypted files.")
            total += info.file_size
            if info.file_size > MAX_FILE or total > MAX_EXPANDED:
                raise ValueError("The unpacked extension is too large.")
        # Accept a publisher's enclosing folder, but never choose among several manifests.
        manifests = [item for item in files if PurePosixPath(item.filename).name == "manifest.json"]
        roots = [item for item in manifests if "/" not in item.filename]
        if roots:
            manifest_file = roots[0]
        elif len(manifests) == 1:
            manifest_file = manifests[0]
        else:
            raise ValueError("Choose a ZIP containing one extension manifest.json.")
        if manifest_file.file_size > 1024 * 1024:
            raise ValueError("The extension manifest is too large.")
        manifest = json.loads(archive.read(manifest_file))
        if not isinstance(manifest, dict) or manifest.get("manifest_version") != 3:
            raise ValueError("This browser supports Manifest V3 extensions.")
        name, version = manifest.get("name"), manifest.get("version")
        if not isinstance(name, str) or not name.strip() or not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){0,3}", version):
            raise ValueError("The extension needs a valid name and version.")
        components = [int(value) for value in version.split(".")]
        if max(components) > 65535 or not any(components):
            raise ValueError("The extension needs a valid version between 0 and 65535 per component.")
        prefix = str(PurePosixPath(manifest_file.filename).parent)
        prefix = "" if prefix == "." else prefix + "/"
        if name.startswith("__MSG_") and name.endswith("__"):
            locale = manifest.get("default_locale", "en")
            locale_path = prefix + "_locales/" + str(locale) + "/messages.json"
            safe_path(locale_path)
            if locale_path in archive.namelist():
                messages = json.loads(archive.read(locale_path))
                message = messages.get(name[6:-2]) if isinstance(messages, dict) else None
                if not isinstance(message, dict) or not isinstance(message.get("message"), str):
                    raise ValueError("The extension has an invalid translated name.")
                name = message["message"]
                if not name.strip():
                    raise ValueError("The extension needs a valid name.")
        permissions = []
        for key in ("permissions", "host_permissions"):
            values = manifest.get(key, [])
            if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
                raise ValueError("The extension has invalid permissions.")
            permissions.extend(values)
        for key in ("optional_permissions", "optional_host_permissions"):
            values = manifest.get(key, [])
            if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
                raise ValueError("The extension has invalid optional permissions.")
            permissions.extend("Optional: " + value for value in values)
        scripts = manifest.get("content_scripts", [])
        if not isinstance(scripts, list):
            raise ValueError("The extension has invalid content scripts.")
        for script in scripts:
            matches = script.get("matches", []) if isinstance(script, dict) else None
            if not isinstance(matches, list) or not all(isinstance(value, str) for value in matches):
                raise ValueError("The extension has invalid website access.")
            permissions.extend(matches)
        return {"uid": digest[:32], "digest": digest, "name": " ".join(str(name).split())[:120],
                "version": version, "permissions": sorted(set(permissions)), "prefix": prefix}


class Store:
    def __init__(self, root):
        self.root = Path(root).absolute()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.root.is_symlink():
            raise ValueError("The extensions folder cannot be a symbolic link.")
        self.index = self.root / "extensions.json"
        self.entries = json.loads(self.index.read_text()) if self.index.exists() else []
        if not isinstance(self.entries, list) or any(not isinstance(item, dict) or not UID.fullmatch(str(item.get("uid", ""))) for item in self.entries):
            raise ValueError("The saved extensions list is invalid.")

    def save(self):
        fd, name = tempfile.mkstemp(prefix=".index-", dir=self.root)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(self.entries, stream, ensure_ascii=False)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.index)
        finally:
            Path(name).unlink(missing_ok=True)

    def install(self, source, expected_digest):
        # Snapshot the selected file so replacement during review/extraction cannot change it.
        with tempfile.TemporaryDirectory(prefix=".install-", dir=self.root) as temporary:
            temporary = Path(temporary)
            snapshot = temporary / "extension.zip"
            with Path(source).open("rb") as incoming, snapshot.open("wb") as outgoing:
                remaining = MAX_ARCHIVE + 1
                while remaining:
                    block = incoming.read(min(1024 * 1024, remaining))
                    if not block:
                        break
                    outgoing.write(block)
                    remaining -= len(block)
                if not remaining:
                    raise ValueError("Extension ZIPs must be smaller than 64 MB.")
            package = inspect_archive(snapshot)
            if package["digest"] != expected_digest:
                raise ValueError("The ZIP changed after review. Choose it again.")
            if any(item["uid"] == package["uid"] for item in self.entries):
                raise ValueError("This extension is already installed.")
            staged = temporary / "files"
            staged.mkdir()
            with zipfile.ZipFile(snapshot) as archive:
                for info in archive.infolist():
                    if not info.filename.startswith(package["prefix"]):
                        continue
                    relative = info.filename[len(package["prefix"]):]
                    if not relative:
                        continue
                    target = staged / str(safe_path(relative))
                    if info.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.open(info) as incoming, target.open("xb") as outgoing:
                            shutil.copyfileobj(incoming, outgoing)
            destination = self.root / package["uid"]
            if destination.exists() or destination.is_symlink():
                raise ValueError("This package is awaiting removal. Restart MarwanOS before installing it again.")
            os.replace(staged, destination)
            entry = {key: package[key] for key in ("uid", "name", "version", "permissions")}
            entry["enabled"] = True
            self.entries.append(entry)
            try:
                self.save()
            except OSError:
                shutil.rmtree(destination)
                raise
            return entry

    def change(self, action, uid):
        entry = next((item for item in self.entries if item["uid"] == uid), None)
        if entry is None:
            raise ValueError("This extension is no longer installed.")
        if action == "remove":
            # Chromium may still be reading these files. Prune them before its next startup.
            self.entries.remove(entry)
        else:
            entry["enabled"] = action == "enable"
        self.save()
        return entry

    def prune(self):
        keep = {item["uid"] for item in self.entries}
        for path in self.root.iterdir():
            if UID.fullmatch(path.name) and path.name not in keep and path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("action", choices=("inspect", "install", "enable", "disable", "remove", "prune"))
    parser.add_argument("value", nargs="?", default="")
    parser.add_argument("digest", nargs="?", default="")
    args = parser.parse_args()
    try:
        if args.action == "inspect":
            result = inspect_archive(args.value)
        else:
            store = Store(args.root)
            if args.action == "install":
                result = store.install(args.value, args.digest)
            elif args.action == "prune":
                store.prune()
                result = {}
            else:
                result = store.change(args.action, args.value)
        print(json.dumps({"ok": True, "result": result}))
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, RuntimeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
