# pc1-shell

PC1 controller shell, Chromium browser, Files and keyboard.

Part of the [PC1 project](https://github.com/users/MarwanSummakieh/projects/3).
[MarwanOS](https://github.com/MarwanSummakieh/MarwanOS) builds the complete OS and
integrates an exact pinned export of this component. This repository owns its
implementation; the Godot UI for backend components lives in pc1-shell.

Source organization date: 2026-10-06. The exported implementation includes the
2026-10-05 development work from MarwanOS commit a634e6ce3001f197524daa8cf357b160383890db.
Existing relative paths are retained so component Python tests can run directly.

See the documentation in docs/ for behavior, evidence and current limitations.
For cross-component tests and complete image builds, use the PC1 OS workspace.
The OS repository's pc1-components.json records the integrated commit and file
ownership; scripts/components.py checks or restores the pinned integration copies.
## Shell checks

Use Godot 4.7.1 and its matching export templates. With that editor available:

```bash
GODOT_BIN=/path/to/godot bash scripts/check-shell.sh
```

The headless fixtures run without the Chromium extension. Building and validating
the real embedded browser additionally requires the pinned CEF/godot-cpp inputs
and OS build environment described in shell/README.md and docs/built-in-tools.md.
