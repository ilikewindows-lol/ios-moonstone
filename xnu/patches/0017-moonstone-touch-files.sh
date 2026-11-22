#!/bin/bash
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
#
# Register the moonstone touch driver (bsd/dev/moon_touch.c, created by
# 0090-moonstone-touch-bitbang.patch) in the BSD build list. The entry goes
# before the memdev.c line so the context of the later patches that edit this
# list (sweet_keys/touch/rpmh/spmi/usb) is untouched.
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ -f bsd/conf/files ]] || { echo 'bsd/conf/files not found' >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path

p = Path('bsd/conf/files')
lines = p.read_text().split('\n')
if any('moon_touch.c' in l for l in lines):
    print('moon_touch.c already listed')
    raise SystemExit(0)
idx = [i for i, l in enumerate(lines) if l.startswith('bsd/dev/memdev.c')]
if len(idx) != 1:
    raise SystemExit('bsd/dev/memdev.c anchor not found exactly once in bsd/conf/files')
lines.insert(idx[0], 'bsd/dev/moon_touch.c\t\t\tstandard')
p.write_text('\n'.join(lines))
print('Registered bsd/dev/moon_touch.c')
PY
