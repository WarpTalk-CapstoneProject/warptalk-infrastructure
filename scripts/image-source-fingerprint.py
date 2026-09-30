#!/usr/bin/env python3
"""The source an image is built from, as content hashes, so an image is rebuilt only when ITS inputs change.

Usage: image-source-fingerprint.py <repo_dir> <commit> <image-matrix entry as JSON>

Prints one line per declared source path: "<path> <git object id at <commit>>", sorted. A tree or
blob id is a hash of the content, so two commits that leave a service's files alone give the same
lines, and build-release.sh reuses that service's signed image instead of rebuilding and
restarting it. Before this, the fingerprint was the whole repository's commit: one change to
billing rebuilt, re-scanned, re-signed and rolled all nine backend services.

The declared `sourcePaths` are only safe if nothing outside them reaches the image. Two guards
refuse a release where that is not true, rather than reuse a stale image:

  * .NET: every relative path a project file under the declared paths points at
    (ProjectReference, Protobuf, Compile, Content, ...) must resolve inside the declared paths.
  * Python: every top-level package a module under the declared paths imports, if that package
    is a directory of this repository, must be declared.

Everything is read at <commit> through git, never from the working tree.
"""

import json
import posixpath
import re
import subprocess
import sys

INCLUDE_ATTR = re.compile(r'\b(?:Include|Update)\s*=\s*"([^"]+)"')
PY_IMPORT = re.compile(r"^\s*(?:from|import)\s+([A-Za-z_]\w*)", re.MULTILINE)


def fail(message):
    print(f"image source fingerprint: {message}", file=sys.stderr)
    sys.exit(1)


def git(repo, *args):
    result = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def inside(path, roots):
    return any(path == root.rstrip("/") or path.startswith(root.rstrip("/") + "/") for root in roots)


def main():
    if len(sys.argv) != 4:
        fail("usage: image-source-fingerprint.py <repo_dir> <commit> <entry-json>")
    repo, commit, entry = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    name = entry.get("name", "?")
    declared = entry.get("sourcePaths") or []
    if not declared:
        fail(f"{name} declares no sourcePaths")
    roots = sorted(set(declared) | {entry["dockerfile"]})

    lines = []
    for path in roots:
        object_id = git(repo, "rev-parse", "--verify", "--quiet", f"{commit}:{path.rstrip('/')}").strip()
        if not object_id:
            fail(f"{name}: source path {path} does not exist at {commit}")
        lines.append(f"{path} {object_id}")

    files = [
        line
        for line in git(repo, "ls-tree", "-r", "--name-only", commit, "--", *[r.rstrip("/") for r in roots]).splitlines()
        if "/tests/" not in f"/{line}"  # .dockerignore: **/tests/ never reaches an image
    ]
    top_level = set(git(repo, "ls-tree", "--name-only", "-d", commit).split())

    for path in files:
        if path.endswith(".csproj") or path.endswith(".props") or path.endswith(".targets"):
            text = git(repo, "show", f"{commit}:{path}")
            for raw in INCLUDE_ATTR.findall(text):
                if ".." not in raw or "$(" in raw:
                    continue
                target = posixpath.normpath(posixpath.join(posixpath.dirname(path), raw.replace("\\", "/")))
                if not inside(target, roots):
                    fail(f"{name}: {path} references {target}, which is outside sourcePaths {declared}")
        elif path.endswith(".py"):
            text = git(repo, "show", f"{commit}:{path}")
            for package in set(PY_IMPORT.findall(text)):
                if package in top_level and not inside(package, roots):
                    fail(f"{name}: {path} imports {package}, which is outside sourcePaths {declared}")

    print("\n".join(sorted(lines)))


if __name__ == "__main__":
    main()
