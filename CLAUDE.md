# CLAUDE.md

The canonical, cross-tool guide for this repo lives in AGENTS.md. Read it — it is the source of truth for project overview, repo layout, the real `Net.luau` remote names, config constants, the per-module map, and conventions.

@AGENTS.md

## Claude-specific notes

- **Workflow.** This repo prefers dynamic multi-agent workflows for substantive changes: an **implement** phase followed by an adversarial **review** phase. Use that pattern for anything non-trivial.
- **Always end a change by validating the build.** There is no test suite — `rojo build` is the only automated check. Run, from the project dir:
  ```powershell
  Set-Location "<project>"; rojo build -o build-test.rbxlx; if (Test-Path build-test.rbxlx) { Remove-Item build-test.rbxlx }
  ```
  The build producing the file (exit 0) means it compiles/serializes; for behavioral changes, also playtest in Studio (`rojo serve` + Play).
- **Shell is Windows PowerShell 5.1** — no `&&`/`||`, use `;`/`if ($?)`; use absolute paths.
