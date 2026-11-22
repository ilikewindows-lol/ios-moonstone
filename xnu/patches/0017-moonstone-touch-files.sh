#!/bin/bash
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
#
# Register the moonstone touch driver (bsd/dev/moon_touch.c, created by
# 0090-moonstone-touch-bitbang.patch) in the BSD build list.
#
# The entry is APPENDED at the end of the file. Every sweet patch that edits
# bsd/conf/files (0028, 0054, 0060, 0062, 0072) anchors on the memdev.c /
# mem.c block around line 104-110 and needs those lines adjacent; inserting
# anywhere near them makes git apply reject the patch, and the whole driver
# series is then skipped. The order of lines in this list does not matter.
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ -f bsd/conf/files ]] || { echo 'bsd/conf/files not found' >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path

p = Path('bsd/conf/files')
text = p.read_text()
if 'moon_touch.c' in text:
    print('moon_touch.c already listed')
    raise SystemExit(0)
if not text.endswith('\n'):
    text += '\n'
text += 'bsd/dev/moon_touch.c\t\t\tstandard\n'
p.write_text(text)
print('Registered bsd/dev/moon_touch.c (appended)')
PY
