# CLAUDE.md

The canonical, cross-tool guide for this repo lives in AGENTS.md. Read it — it is the source of truth for project overview, repo layout, the real `Net.luau` remote names, config constants, the per-module map, and conventions.

@AGENTS.md

## Claude-specific notes

- **Workflow.** This repo prefers a **dynamic implement → review** pattern for substantive changes: an **implement** phase followed by an adversarial **review** phase. Use that pattern for anything non-trivial; let scope drive how many passes.
- **Always end a change by validating the build.** There is no test suite — `rojo build` is the only automated check. Run, from the project dir:
  ```powershell
  Set-Location "<project>"; rojo build -o build-test.rbxlx; if (Test-Path build-test.rbxlx) { Remove-Item build-test.rbxlx }
  ```
  The build producing the file (exit 0) means it compiles/serializes.
- **VIBRANT + legoish palette is a standing directive.** ALL map/UI work uses saturated, vivid colors — the source of truth is `src/Shared/Config/Palette.luau`. World parts get the classic Roblox **studs texture on every face** via `Shared/Modules/Surface.luau` (`applyStuds`), called from each module's `makePart` (modern `SurfaceType.Studs` renders too subtly, so we overlay the real texture `rbxassetid://8130710802` tinted to a brightened part colour). Never desaturate; pull colors from `Palette.luau` and let `makePart` stud them.
- **A Roblox Studio MCP is connected for live debugging.** During Play you can use it to inspect/drive the running game — `get_console_output` reads logs and `execute_luau` runs code **client-side** in the playing session. Use it to confirm behavior instead of guessing.
- **Deliver / test loop.** Rebuild the place file (`rojo build -o HatchABrainrot-LATEST.rbxlx`), open **one** Studio window, do a full **Stop → Play** (live-sync does NOT re-run already-running scripts, and multiple windows make it easy to test stale code or the wrong place), then **Publish-As** to update the live game. For behavioral changes, playtest (`rojo serve` + Play) — there is no test suite to catch logic regressions.
- **Shell is Windows PowerShell 5.1** — no `&&`/`||`, use `;`/`if ($?)`; use absolute paths.
