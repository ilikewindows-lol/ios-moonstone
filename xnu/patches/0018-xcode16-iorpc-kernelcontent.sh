#!/bin/bash
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
#
# Xcode 16+'s iig (DriverKit interface generator) emits uses of IORPC.kernelContent;
# xnu-8796's struct IORPC has no such member, so every generated *.iig.cpp fails to
# compile on the macos-15 runner (macos-14, which shipped Xcode 15, is retired).
# Add the member. It is only read by newer xnu's IOUserServer, which this kernel
# does not use, so it does not change behaviour. Same fix as ios-flame/redfin 0082.
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ -f iokit/IOKit/IORPC.h ]] || { echo 'iokit/IOKit/IORPC.h not found' >&2; exit 1; }

python3 - <<'PY'
import re
from pathlib import Path

path = Path('iokit/IOKit/IORPC.h')
text = path.read_text()
if 'kernelContent' in text:
    print('IORPC.kernelContent already present')
    raise SystemExit(0)

# the struct definition itself (not the forward declaration "struct IORPC;")
m = re.search(r'struct IORPC\s*\{[^}]*\}\s*;', text)
if not m:
    raise SystemExit('struct IORPC definition not found in IORPC.h')
body = m.group(0)
if 'replySize' not in body or 'IORPCMessageMach' not in body:
    raise SystemExit('struct IORPC has an unexpected layout: ' + body)

close = body.rindex('}')
new = (body[:close]
       + '\tIORPCMessage * kernelContent;\t/* Xcode 16+ iig; unused by this xnu */\n'
       + body[close:])
if text.count(body) != 1:
    raise SystemExit('struct IORPC definition is not unique')
path.write_text(text.replace(body, new, 1))
print('Added IORPC.kernelContent for Xcode 16+ iig')
PY
