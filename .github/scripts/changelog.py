"""Print the changelog notes for one addon version, for the CurseForge file and GitHub release.
Usage: changelog.py <AddonFolder> <version> <CHANGELOG.md>"""
import re
import sys

addon, version, path = sys.argv[1], sys.argv[2], sys.argv[3]
# "MageServices" -> "Mage Services", the way the changelog names it
pretty = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", addon)
# prefer the toc Title (colour codes stripped), so a renamed addon matches its changelog lines
try:
    for tl in open(f"{addon}/{addon}.toc", encoding="utf-8"):
        if tl.startswith("## Title:"):
            pretty = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", tl.split(":", 1)[1]).strip()
            break
except OSError:
    pass
text = open(path, encoding="utf-8").read().splitlines()

notes, grab = [], False
for line in text:
    if grab:
        # a blank line followed by another heading ends this addon's block
        if line.strip() == "" or line.startswith("#") or (line and not line.startswith("-") and not line.startswith(" ")):
            if notes:
                break
            continue
        notes.append(line)
    elif pretty in line and version in line:
        grab = True

if not notes:
    notes = [f"- {pretty} {version}"]
print(f"**{pretty} {version}**\n")
print("\n".join(notes))
print("\nFull changelog: https://github.com/miff88/wow-forever-addons/blob/main/CHANGELOG.md")
