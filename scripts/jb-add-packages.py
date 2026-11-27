#!/usr/bin/env python3
"""Install Procursus packages (and their missing dependencies) into the rootless jailbreak payload, as dpkg would
without running maintainer scripts.

  jb-add-packages.py <root: dir holding var/jb> <package> [<package> ...]

Reads the repo's Packages index, skips whatever the payload's dpkg status already has (Package or Provides),
downloads the rest, extracts each into <root> (their paths start with var/jb/), and records them as installed.
"""
import lzma, os, re, subprocess, sys, urllib.request

REPO = "https://apt.procurs.us/"
INDEX = REPO + "dists/2000/main/binary-iphoneos-arm64/Packages.xz"


def stanzas(text):
    for block in text.split("\n\n"):
        fields, key = {}, None
        for line in block.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += "\n" + line
            elif ":" in line:
                key, value = line.split(":", 1)
                fields[key] = value.strip()
        if "Package" in fields:
            yield fields


def names(field):
    for alt in field.split(","):
        first = alt.split("|")[0].strip()
        if first:
            yield re.split(r"[\s(]", first)[0]


def main():
    root, wanted = sys.argv[1], sys.argv[2:]
    status_path = os.path.join(root, "var/jb/Library/dpkg/status")
    status = open(status_path).read()
    have = set()
    for s in stanzas(status):
        have.add(s["Package"])
        have.update(names(s.get("Provides", "")))
    index = lzma.decompress(urllib.request.urlopen(INDEX, timeout=120).read()).decode()
    repo = {}
    for s in stanzas(index):
        repo.setdefault(s["Package"], s)   # first (newest listed) wins
        for p in names(s.get("Provides", "")):
            repo.setdefault(p, s)
    todo, done = list(wanted), []
    while todo:
        name = todo.pop(0)
        if name in have:
            continue
        s = repo.get(name)
        if not s:
            print(f"jb-add-packages: {name} not in the repo, skipped")
            have.add(name)
            continue
        have.add(name)
        have.add(s["Package"])
        have.update(names(s.get("Provides", "")))
        todo += list(names(s.get("Depends", ""))) + list(names(s.get("Pre-Depends", "")))
        done.append(s)
    with open(status_path, "a") as out:
        for s in done:
            deb = "/tmp/" + os.path.basename(s["Filename"])
            urllib.request.urlretrieve(REPO + s["Filename"], deb)
            subprocess.run(["dpkg-deb", "-x", deb, root], check=True)
            files = subprocess.run(["dpkg-deb", "-c", deb], check=True, capture_output=True, text=True).stdout
            print(f"jb-add-packages: {s['Package']} {s['Version']} ({len(files.splitlines())} entries)")
            control = subprocess.run(["dpkg-deb", "-f", deb], check=True, capture_output=True, text=True).stdout
            lines = control.strip().splitlines()
            out.write(lines[0] + "\nStatus: install ok installed\n" + "\n".join(lines[1:]) + "\n\n")


if __name__ == "__main__":
    main()
