# Phosphor Icons (regular weight)

The shell's icon font. One file, so the whole icon language of the UI has one
source and one license.

- Source: https://github.com/phosphor-icons/web — `src/regular/Phosphor.ttf`
- Fetched: 2026-08-08, from the `master` branch
- License: MIT (see LICENSE beside this file, fetched from the same commit)
- sha256: `06b91e022b7ee899a63efced879392a74f0bacbda54e4467e9f663220d173a10`

Codepoints used by the shell are declared in `shell/src/icons.gd`, extracted
from the same commit's `src/regular/style.css`. When bumping the font, re-check
every codepoint there: Phosphor does not guarantee stable codepoints across
releases, and a silent shift would swap every icon in the UI at once — which is
why the font is vendored at a recorded hash rather than fetched at build time.

This is the repo's second binary asset (the first is the plymouth splash). The
"no binary assets" discipline is about artefacts a build can produce — the
exported shell, an editor-authored scene — not about upstream inputs pinned by
hash, which is exactly what the Containerfile already does for Godot itself.
