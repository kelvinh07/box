# AGENTS.md — Hatch a Brainrot

Canonical, cross-tool guide for LLM coding assistants working in this repo. Keep it accurate to the code; if you change structure or APIs, update this file.

---

## 1. Project overview

**Hatch a Brainrot** is a Roblox tycoon-style game written in **Luau** and organized for **Rojo**. Everything — UI, the map, brainrot models, bases, the dig lane — is **generated in code at runtime**. There are **no `.rbxmx` / model assets in the repo**; the only checked-in binary is `HatchABrainrot-LATEST.rbxlx` (the latest `rojo build` output, used for one-window Stop/Play testing and Publish-As).

### Core gameplay loop
1. Walk to the **shared central dig lane** (on the half-circle opening side of the lobby).
2. **Hold E to dig** a mound — a pixel/voxel egg pops out of the dirt in stages. Rarity is **server-assigned up front**, so rarer eggs look different (bigger, different color, longer dig) before you finish.
3. Eggs go into a **BACKPACK** (capacity starts **5**, **+5 per rebirth**, capped **50**; opened via the left-side 🎒 button).
4. **Hatch an egg only at your base front INCUBATOR** (server proximity-checked).
5. The hatched brainrot **spins on a podium** and **accrues cash**.
6. Walk over that brainrot's **green PRESSURE PLATE** to collect its accrued cash. **Gems auto-credit** (no plate needed).
7. **Level up** individual brainrots (click them on their podium) to multiply their income; buy more **plots** at the base ghost podium; spend Cash/Gems at the **three in-world upgrade stands** (Shovel / Incubator / Luck) near the lobby spawn.
8. **REBIRTH** at a lane/wall gate once you meet all three requirements (LifetimeCash milestone, Gem cost, correct zone). Rebirth is **not** a fresh start — it **keeps your whole Collection (with levels), Gems, tiers and plots**, resets only Cash + LifetimeCash, and **permanently multiplies income** (gems ×1.5, cash ×1.2 per rebirth, compounding). Rebirths continue past the last zone.

Brainrots have **rarity tiers** (Common → Uncommon → Rare → Legendary, plus zone 2+ exclusive **Mythic**) and **4 variants** (Normal / Gold / Diamond / Galaxy) that multiply stats and add glow. Income is **tier-based** (no longer zone-scaled) and further scaled by the variant, the per-brainrot **level** (cap 10), and the rebirth multipliers — see `BrainrotMath`.

---

## 2. Repo layout

```
robloxrename/
├── aftman.toml                  # toolchain pin (rojo 7.7.0-rc.1)
├── default.project.json         # Rojo project: maps src/ into the DataModel
├── HatchABrainrot-LATEST.rbxlx  # latest rojo build output (one-window Stop/Play + Publish-As)
├── README.md
└── src/
    ├── Shared/                  # -> ReplicatedStorage.Shared
    │   ├── Config/              # ALL gameplay balance + data tables (tune here)
    │   │   ├── GameConfig.luau      # global tunables: starting cash/gems/plots, egg capacity, plot-cost curve, DataStore, ticks
    │   │   ├── EggConfig.luau       # egg rarities: HatchCost, Incubation seconds, BrainrotTier
    │   │   ├── BrainrotConfig.luau  # brainrot roster + TierIncome (per-min cash/gem) + per-brainrot Levels (cost/currency, cap 10)
    │   │   ├── VariantConfig.luau   # Normal/Gold/Diamond/Galaxy: CashMult, GemBonus (gems/min), Weight, LuckBias
    │   │   ├── ZoneConfig.luau      # per-zone DisplayName/Theme, DigOdds, BrainrotTiers, UnlockRebirths (CashScale/GemScale kept but UNUSED by income). Theme drives BaseManager.decorateLane (zone1 "The Burrow"=none, zone2 "Forest"=trees)
    │   │   ├── UpgradeConfig.luau   # Luck (9 tiers, Gems) + Incubator (9 named tiers, Cash 1-5/Gems 6-9) + Rebirth rules (cashMilestone/gemCost/multipliers)
    │   │   ├── ShovelConfig.luau    # dig-speed shovel: 9 tiers (Cash 1-5/Gems 6-9), DigSpeedMult, per-rarity hold stages + 0.3s floor + cooldown helpers
    │   │   ├── RarityColors.luau    # tier/variant/currency color language
    │   │   ├── AssetConfig.luau     # brainrot name -> Creator Store asset id (all nil => procedural), icons, SFX
    │   │   ├── AdminConfig.luau     # admin allow-list (UserIds + usernames) + isAdmin(); /test fill values (MaxCash/MaxGems)
    │   │   └── Palette.luau         # VIBRANT legoish world-color source of truth (grass/snow/dirt/base/walls/plates/podiums/incubator/etc.)
    │   └── Modules/
    │       ├── Net.luau             # central RemoteEvent/RemoteFunction registry (server creates, clients fetch)
    │       ├── BrainrotMath.luau    # SINGLE source of truth for income math (server + client share it)
    │       ├── Format.luau          # number abbreviation (1.5K, 2.3M) + mm:ss
    │       ├── Surface.luau         # classic studs TEXTURE overlay (applyStuds/shouldStud) — the world's studded legoish look, shared by every makePart
    │       └── Util.luau            # weightedPick, choice, uid, shallowCopy
    │
    ├── Server/                  # -> ServerScriptService.Server
    │   ├── Bootstrap.server.luau    # single entry point: setup remotes, build world, init managers, player lifecycle
    │   └── Managers/                # ModuleScripts, each with init() wired by Bootstrap
    │       ├── PlayerData.luau       # authoritative profiles: DataStore load/save, reconcile, snapshot, push
    │       ├── MapBuilder.luau       # shared grass ground + neutral spawn + snow-capped dirt-cliff map border; exposes DigCenter
    │       ├── BaseManager.luau      # the 10 base buildings, podiums, plates, incubators, stairs, ghost Buy-Plot podium, shared dig lane + rebirth walls + zone collision gates + side fences; brainrot Lv label + tag/ClickDetector
    │       ├── BrainrotFactory.luau  # builds a brainrot model (Creator Store asset OR procedural placeholder) + variant glow + label
    │       ├── DiggingManager.luau   # server-authoritative digging: RollEggs / Dig, proximity + rarity-aware cooldown + cap checks
    │       ├── IncubationManager.luau# PlaceEgg / DiscardEgg / CollectIncubator: hatch timing (0.5s floor), base+variant roll, Mythic ascension
    │       ├── EconomyManager.luau   # passive income loop (tier+variant+level+rebirth), per-brainrot cash accrual + collect, BuyPlot, SellBrainrot, LevelBrainrot
    │       ├── UpgradeManager.luau   # UpgradeShovel / UpgradeIncubator / UpgradeLuck (per-tier Cash-or-Gems currency)
    │       ├── StandManager.luau     # builds the 3 in-world upgrade SHOPS (clones of ServerStorage.ShopModel, recolored/retitled per stand; procedural booth fallback), instant-E prompts (StandType attr)
    │       ├── RebirthManager.luau   # Rebirth: 3-requirement check (LifetimeCash/Gems/zone), reset Cash+LifetimeCash only, recompute permanent multipliers
    │       ├── LeaderboardManager.luau # two in-world SurfaceGui boards on the lane fences: most rebirths + rarest brainrot
    │       └── AdminManager.luau       # admin chat commands (Player.Chatted); /test maxes the caller's Cash+Gems; gated by AdminConfig.isAdmin
    │
    └── Client/                  # -> StarterPlayer.StarterPlayerScripts.Client
        ├── Main.client.luau         # entry point: builds the whole UI in code, wires effects/net, starts state
        ├── ClientNet.luau           # thin RemoteFunction wrapper; toasts the server's rejection reason
        ├── ClientState.luau         # holds latest server snapshot, fans out onChanged() to UI panels
        ├── DigSite.luau             # per-client dirt mounds + pixel/voxel eggs over the shared lane; E-to-dig prompts (hold time from ShovelConfig)
        ├── GrassChecker.luau        # overlays a 6x6 two-green CHECKER on top of the STUDDED grass (studs show through) via a runtime EditableImage on "GrassSurface"-tagged parts
        ├── Sounds.luau              # SFX pool (ids from AssetConfig.Sounds)
        ├── UIUtil.luau              # code-built UI helpers (frame/label/button/modal/corner/stroke/pop)
        └── UI/
            ├── Effects.luau         # toasts, +$/+Gem popups, hatch reveal card, screen-shake (server-driven)
            ├── TopBar.luau          # top-center Cash/Gem counters + zone label
            ├── HUD.luau             # always-on incubators panel: one row per UNLOCKED incubator (up to 4) — progress bar, countdown, COLLECT(index)
            ├── Backpack.luau        # 🎒 toggle panel: eggs per rarity + capacity line; click slot to PlaceEgg, 🗑️ to DiscardEgg
            ├── Stands.luau          # 3 in-world stand tier-list panels (Shovel/Incubator/Luck), opened by ProximityPrompt (StandType attr)
            ├── LevelUp.luau         # per-brainrot level-up panel, opened by clicking your brainrot's podium model (Brainrot tag + ClickDetector)
            ├── Collection.luau      # owned brainrots grouped by tier, variant-colored cards, Lv badge, Sell button
            ├── Rebirth.luau         # rebirth progress (LifetimeCash bar) + confirm-step multiplier preview
            └── SideNav.luau         # right-side buttons toggling Collection/Rebirth modals (stands open via proximity, not here)
```

### How `default.project.json` maps `src/` into the DataModel
- `src/Shared` → `ReplicatedStorage.Shared`
- `src/Server` → `ServerScriptService.Server` (so `Bootstrap.server.luau` runs as a Script; managers are children of `Server.Managers`)
- `src/Client` → `StarterPlayer.StarterPlayerScripts.Client` (so `Main.client.luau` runs as a LocalScript)
- `**/*.spec.luau` is glob-ignored (none exist today).
- The project also sets `Workspace` (Gravity 196.2, FilteringEnabled), `Lighting`, and `SoundService` properties.

Require paths follow this mapping, e.g. `require(ReplicatedStorage.Shared.Modules.Net)`, `require(script.Parent.PlayerData)` inside a manager, `require(script.Parent.Parent.UIUtil)` inside a UI module.

---

## 3. Build / run / test commands

> **`rojo build` is the ONLY automated check. There is no unit-test suite.** Verification = build + Studio playtest.

### Build / validate (run after EVERY edit)
```powershell
Set-Location "<project>"; rojo build -o build-test.rbxlx; if (Test-Path build-test.rbxlx) { Remove-Item build-test.rbxlx }
```
`exit 0` (the file got produced) means it compiles/serializes. There is **no** `luau-analyze`, `selene`, or `stylua` installed — do not assume any of them exist.

### Dev / run
`rojo` is managed by **aftman** (see `aftman.toml`, rojo 7.x). In the project dir:
```powershell
rojo serve
```
Then connect the **Rojo Studio plugin** and press **Play**. For DataStore saving, enable **Studio > Game Settings > Security > Enable Studio Access to API Services** (the game runs fine without it — there's just no persistence; `PlayerData` falls back to non-saving temporary profiles).

---

## 4. Conventions & architecture rules

- **Luau, `--!strict`** at the top of every module.
- **SERVER-AUTHORITATIVE.** Clients only **request** via the remotes registered in `src/Shared/Modules/Net.luau`. The server validates **everything** — currency, item ownership, cooldowns, dig proximity, hatch proximity, plot/zone limits, rebirth. **Never trust the client.** The client never mutates gameplay values locally; it reflects the server snapshot (`ClientState`).
- **Config-driven balance.** All numbers/tables live in `src/Shared/Config/*`. Tune gameplay **there**, not in manager logic.
- **Managers with `init()`.** Each `src/Server/Managers/*` is a ModuleScript; `Bootstrap.server.luau` requires it and calls `init()` (which registers its `Net` handlers). Cross-manager references that would cycle (e.g. BaseManager ↔ Incubation/Economy/Rebirth) are wired via setter injection (`setBaseManager`, `setRebirthHandler`) from Bootstrap.
- **Code-built UI.** No StarterGui instances. `Main.client.luau` builds one root `ScreenGui` and every panel via `UIUtil` helpers (`frame`, `label`, `button`, `modal`, `corner`, `stroke`, `pop`).
- **Per-slot BaseManager state.** Base structures are keyed by **slot** (1..10), not by player. State tables: `slotFolder`, `slotPodiums`, `slotModels`, `slotPlates`, `slotSign`, `slotIncubator`, `slotStairBarrier`, `slotGhostPlot`, plus a dynamic `slotOccupant` / `playerSlot` lookup. `slotGhostPlot` is the per-slot ghost "🔒 Buy Plot" podium (a `ClickDetector` routing to `EconomyManager.buyPlot`) shown at the next free index for an occupied base under `MaxPlots` — there is **no** shop UI for plots. (Rebirth gating is **not** per-slot — the walls belong to the single shared central dig lane.) Joining a player only marks the slot occupant, renames the sign, rebuilds podiums to plot count, and loads their brainrots.
- **Constants-driven geometry.** Layout is tuned via named constants, never magic numbers inline:
  - `BaseManager`: `LOBBY_RADIUS`, `ARC_SPAN_DEG`, `MAX_SLOTS`, `FLOOR`, `WALL_H`, `WALL_T`, `FLOOR2_Y`, `SEG_SIZE`, `REBIRTH_WALL`, `PLATE`, `STAIR_GAP` / `STAIR_STEPS` / `STAIR_STEP_H` / `STAIR_STEP_D` / `STAIR_FRONT_LZ` / `STAIR_ENTRANCE_LZ`.
  - `MapBuilder`: `DigCenter`.
- **One income math source.** `Shared/Modules/BrainrotMath.income(entry, rebirthCount)` is used by **both** the server (payout) and client (preview) so displayed numbers always match payouts. Income is **tier-based** (`BrainrotConfig.TierIncome`) × variant × per-brainrot level (`1.2^(level-1)`) × the rebirth multipliers (cash `1.2^rb`, gems `1.5^rb`); it returns **per-second** (per-minute ÷ 60). `entry.level` defaults to 1. Pass the player's **rebirth count**, never a zone — `ZoneConfig.CashScale/GemScale` are no longer income drivers.
- **Rebirth persists progress.** A rebirth is **not** a wipe: it resets ONLY `Cash` + `LifetimeCash` to 0 and recomputes the derived multipliers; `Gems`, all upgrade tiers, `Plots`, and the entire `Collection` (each entry keeps its `.level`) carry over. The rebirth reward is the permanent compounding income multiplier (no luck bonus).
- **`AssetConfig` maps brainrot names → Creator Store asset IDs.** Every entry is currently `nil` ⇒ a chunky procedural placeholder via `BrainrotFactory` (the game is fully playable procedurally). Swap real IDs in `AssetConfig.luau` only.
- **VIBRANT + CLASSIC-STUDDED LEGOISH visual system.** All world geometry uses **saturated `Color3`s from `Palette.luau`** (the single source of truth — grass/snow/dirt/base/walls/plates/podiums/glass/incubator/fence/etc.) and the **classic Roblox "studs & inlets" texture overlaid on every face**. Modern Studio renders `SurfaceType.Studs`/`Inlet` almost invisibly, so instead of surface types we apply the real stud TEXTURE (`rbxassetid://8130710802`) tinted to a brightened part colour via **`Shared/Modules/Surface.luau`** (`Surface.applyStuds` / `Surface.shouldStud`), called from every `makePart` helper (MapBuilder/BaseManager/StandManager) + the dig mounds (`DigSite.buildDirt`). World surfaces use the **`Plastic`** material (matte — switched from SmoothPlastic to kill the specular sheen/glare; the `makePart` helpers default to `Plastic`). `shouldStud` auto-skips glow/see-through/natural materials (Neon, Glass, ForceField, Wood, WoodPlanks, Fabric, Transparency>0.3); pass `NoStuds = true` to a `makePart` call to force-skip (e.g. NPC avatar limbs). Eggs stay **pixel/voxel cubes** (`DigSite`, NOT textured). When adding or recoloring map/UI parts, pull colors from `Palette.luau`, keep them vibrant — never desaturated — and let `makePart` stud them.

---

## 5. Remotes (`src/Shared/Modules/Net.luau`)

The server calls `Net.setupServer()` once (creates a `Remotes` folder under `ReplicatedStorage.Shared`). Clients use `Net.getEvent(name)` / `Net.getFunction(name)`.

**Events (server → client, `RemoteEvent`):**
`PushState`, `Notify`, `HatchResult`, `FloatingText`, `ScreenShake`

**Functions (client → server, `RemoteFunction`, return `{ok=…, …}`) — in declaration order:**
`RequestState`, `RollEggs`, `Dig`, `PlaceEgg`, `DiscardEgg`, `CollectIncubator`, `UnlockIncubator`, `BuyPlot`, `BuyLadder`, `UpgradeLuck`, `UpgradeIncubator`, `UpgradeShovel`, `LevelBrainrot`, `Rebirth`, `SellBrainrot`

(`CollectIncubator(index)` now takes the incubator slot index 1..4. `UnlockIncubator()` spends Cash to unlock the next of up to 4 parallel incubators. `BuyLadder()` spends Cash to unlock the 2nd-floor ladder after owning all 12 floor-1 plots.)

(`DiscardEgg(rarity)` deletes one unwanted egg from the backpack — no hatch, no refund. `UpgradeIncubator` is the renamed `UpgradeHatchSpeed`; `LevelBrainrot(id)` levels a single owned brainrot. Note `RequestState` is registered inline in `Bootstrap.server.luau` (returns `PlayerData.snapshot`), not inside a manager.)

These exact strings are the contract — match them precisely on both sides.

---

## 6. Per-module map

### Server managers (`src/Server/Managers/*`)
- **PlayerData** — authoritative profiles. DataStore (`HatchABrainrot_v1`) load/save with retries; in-memory `cache`/`dirty`. Saved fields: `Cash`, `Gems`, `LifetimeCash` (Cash earned since last rebirth; drives the rebirth milestone; resets on rebirth), `Rebirths`, `GemMultiplier`/`CashMultiplier`/`LevelCostMultiplier` (all derived from `Rebirths`), `ShovelLevel`, `IncubatorLevel`, `LuckLevel`, `Plots`, `CurrentZone`, `Eggs`, `Incubators` (array of up to 4 in-progress hatches) + `IncubatorsUnlocked` (1-4) + `LadderUnlocked`, and `Collection` (each entry has `.level`). `reconcile()` migrates the old `HatchSpeedLevel` → `IncubatorLevel` and the old single `Incubator` → `Incubators[1]`, defaults each `entry.level=1`, and recomputes the rebirth-derived multipliers. `snapshot()` builds the derived client payload (next plot cost, egg capacity, total luck, incubator reduction, dig-speed mult, `RebirthMilestone`/`RebirthGemCost`, and `RebirthReady` = all 3 requirements met); `push()` fires `PushState`; periodic autosave + `BindToClose` final save. Falls back to non-persistent profiles if the DataStore is unavailable (and refuses to overwrite real data on a failed load via `__doNotSave`). On `load` it also builds a **`leaderstats`** folder on the Player — a StringValue `Cash` (current total cash, formatted) + IntValue `Rebirths` — kept current in `push` (`updateLeaderstats`), so the **default Tab player list** shows each player's cash & rebirths.
- **MapBuilder** — `build()` (re)creates the shared `Workspace.World`: a big **studded grass ground** (`Palette.Grass`, classic stud texture via `makePart` like the rest of the world; tagged `GrassSurface` so `Client/GrassChecker` overlays a subtle 6x6 two-green checker on top — studs still show) and an **invisible spawn anchor** (`SpawnLocation` flush with the ground, no visible plate — players are immediately teleported to the front of their own empty base on spawn by `BaseManager.assignBase`, which holds the position for ~0.4s to win the race vs the engine's spawn placement). All parts use the legoish studded `makePart` helper. Exposes `DigCenter` consumed by BaseManager. Also sets a **bright, VIVID but MATTE & glare-free sky** (`setupSky`, at runtime so it replicates; project.json holds matching editor baselines + `Technology = ShadowMap`, which is a protected property scripts can't set): `Brightness 2`, `Ambient (80,80,80)`, `OutdoorAmbient (120,140,100)`, `ExposureCompensation 0.1`, `ColorShift_Top (255,250,242)` subtle warm-white highlight (toned down — full warm read too yellow); **`Atmosphere` Density/Haze/Glare = 0** (off — no haze wash); a global **`ColorCorrectionEffect` "VibrantBoost"** (`Saturation 0.4, Contrast 0.1, Brightness 0.05`) to pop the candy palette; **`BloomEffect` disabled + `EnvironmentSpecularScale 0` + manual `ColorGradingEffect` disabled** (no floor glare, no gloss, no muting); and the **sun/moon hidden** via a `Sky` with `CelestialBodiesShown=false` (+ no `SunRaysEffect`). (`GlobalShadows` is currently off, so ShadowMap casts no dynamic shadows — enable it if shadows are wanted.) Scatters static **blocky rectangular white `Clouds`** high above the map (`buildClouds`, fixed seed, smooth/non-collidable). (The old map-wide **snow-capped dirt border** was removed; the play area is now framed by the two grass-topped dirt cliffs flanking the lane — `BaseManager.buildLaneSideWalls`. Other map edges are currently open — more borders TBD.)
- **BaseManager** — the heaviest module. Pre-builds **10 two-floor base buildings** in a rounded half-circle ring facing center; podiums along the side window walls (6/side/floor, up to 24); green pressure plates per podium (Touched → only the slot occupant, only when `getAccrued ≥ 1`, debounced → `EconomyManager.collect`); **4 incubators in the back** (progressively revealed — only your unlocked ones + the next ghost "🔒 Buy Incubator" show; the rest are reparented to a ServerStorage holder); a back-wall **climbable ladder** (TrussPart) to floor 2 that is HIDDEN until 12 plots, a buyable ghost at 12 plots, climbable once `BuyLadder` is bought; the **2nd floor itself** (a `Floor2` folder per slot) is reparented OUT of Workspace — invisible to everyone — until the ladder is bought; the per-slot **ghost "🔒 Buy Plot" podium** (`ClickDetector` → `EconomyManager.buyPlot`, gated so plot 13 needs the ladder first); and the **single shared dig lane** with **rebirth/zone walls** between zones (`buildSharedLane` / `buildSharedWall` / `buildZoneArea`). The walls are **physical per-player gates**: `setupZoneCollision` registers `ZoneGate*k*` (wall) and `ZoneProg*p*` (player) collision groups so `ZoneProg p` passes `ZoneGate k` only when `p > k`; `applyZoneGate(player)` puts the character on the group matching its highest unlocked zone (called every spawn + after rebirth). `buildLaneFences` adds the zone1/2 side barriers as **two layers** — a **tall (60-stud) INVISIBLE collidable wall** named `ZoneFence_*` (so no one can jump/glitch over to skip the zone) plus a **visible studded fence** in front (the asset `4831942116` tiled when the game owner can load it, else a procedural studded picket fence). `buildLaneSideWalls` adds the **two grass-topped dirt cliffs** flanking the whole lane (`Palette.Dirt` body + `Palette.Grass` cap) to tighten the playable width — they start at `LANE_SIDE_Z_START` (past the front-most bases so base access is never blocked) and PRE-EXTEND to frame `LANE_SIDE_PLANNED_ZONES` zones (room for FUTURE zones beyond `MaxZone`); tune via the `LANE_SIDE_*` constants. The forest trees are **solid (collidable trunk + leaves)** so players can't walk through them, and are placed with a bigger front margin so they clear the boundary fence. `LeaderboardManager` finds the `ZoneFence_*` reference part to place its tombstone. `decorateLane` (called at the end of `buildSharedLane`) frames **every rebirth wall** with tall **studded stone piles** at both ends (`buildWallFrame`/`buildRockPile`, `Palette.Stone`) and adds **per-zone Theme decor** — a `Theme == "Forest"` zone gets trees flanking the dig site (`buildForestTrees`, in the left/right strips only, never on the dig square). Trees use `InsertService:LoadAsset(17280628013)` when the game owner owns it, else a **procedural studded pine fallback** (`buildProceduralTree`), so the forest is never empty. On placing a brainrot it adds a **"Lv N" billboard**, stamps a `BrainrotId` attribute, parents a `ClickDetector`, and tags the model `Brainrot` (CollectionService) so the client `LevelUp` panel can wire it up; `startGateUpdater` keeps plate labels + Lv billboards + ghost-plot affordability in sync. Public: `assignBase`, `freeBase`, `placeBrainrot`, `removeBrainrot`, `refreshBrainrotLabel`, `rebuildPlots`, `applyZoneGate`, `getIncubatorPositions` (unlocked incubator positions for hatch proximity), `refreshBaseProgression(player)` (drives incubator/ladder/floor-2 reveal from the occupant's profile; replaced `updateStaircase`), `startGateUpdater`, `setRebirthHandler`.
- **BrainrotFactory** — `build(entry, rebirthCount)` returns an anchored model: Creator Store asset (via `InsertService:LoadAsset`, normalized to uniform size) if `AssetConfig` has an id, otherwise a procedural placeholder (ball body + eyes + feet). Adds variant glow (PointLight + sparkles, rainbow shimmer for Galaxy) and a billboard name/income label (income via `BrainrotMath` with the rebirth count). Exposes `PODIUM_SIZE`.
- **DiggingManager** — `RollEggs(count, zone)` pre-assigns luck-weighted rarities to mounds (keyed by server id, capped by `MAX_PENDING`/`MAX_ROLL_BATCH`); `Dig(id)` validates a **rarity-aware, shovel-scaled cooldown** (`cd = ShovelConfig.holdDuration(rarity, mult) * 0.85`, so rarer eggs / slower shovels enforce a longer dig), `DigPatch` proximity, backpack cap, then grants the egg and pre-rolls the mound's next rarity. (The flat `GameConfig.DigCooldown` is superseded and kept only as a reference.) Luck shifts odds toward Uncommon/Rare/Legendary.
- **IncubationManager** — **MULTI-INCUBATION** (up to `GameConfig.MaxIncubators` = 4 parallel hatches; `profile.Incubators[1..4]` + `IncubatorsUnlocked`). `PlaceEgg(rarity)`: proximity to ANY of the player's unlocked incubators (`BaseManager.getIncubatorPositions`), finds the first FREE unlocked slot, requires the egg + `Cash ≥ HatchCost` + a free plot accounting for pending hatches (`#Collection + pendingCount < Plots`), spends egg + Cash, starts that slot's timer `max(0.5, Incubation * (1 - incubatorReduction))` (0.5s hatch floor; `endTime` uses `GetServerTimeNow()`). `CollectIncubator(index)`: collects slot `index` once ready — rolls a base brainrot of the egg tier (Legendary can **ascend to Mythic** in zone 2+) + luck-weighted variant, appends to `Collection` at level 1, places the model, fires `HatchResult` + `ScreenShake`. `UnlockIncubator()`: spends Cash (`GameConfig.incubatorUnlockCost`, escalating) to unlock the next incubator, then `BaseManager.refreshBaseProgression`. `DiscardEgg(rarity)`: deletes one held egg (no hatch/refund).
- **EconomyManager** — passive income loop (every `IncomeTickSeconds`): per brainrot, `BrainrotMath.income(entry, profile.Rebirths)` → **cash accrues** per-brainrot (capped, collected at its plate via `collect`, which also adds to `LifetimeCash`); **gems auto-credit** (fractional accumulator → floor → `FloatingText`). Also `buyPlot` (Cash, escalating cost — reached by clicking the per-slot **ghost plot podium**; rejects plot 13 until the ladder is bought), `buyLadder` (Cash `GameConfig.LadderCost`; requires 12 plots; sets `LadderUnlocked` + `BaseManager.refreshBaseProgression` to reveal floor 2), `sellBrainrot` (refund ≈ 30 cycles of cash; NOT credited to `LifetimeCash`), and `levelBrainrot(id)` (level a single brainrot: Cash L2-5 / Gems L6-10, base cost × `levelCostMultiplier`, cap 10, persists through rebirth). `getAccrued` feeds the plate labels.
- **UpgradeManager** — `buyShovel`/`buyIncubator`/`buyLuck` behind `UpgradeShovel` / `UpgradeIncubator` (was `UpgradeHatchSpeed`) / `UpgradeLuck`. Each validates the next tier's **per-tier currency** (Shovel & Incubator: Cash 1-5 / Gems 6-9; Luck: all Gems), level cap (9), and charges the player; all costs/currencies live in `ShovelConfig` / `UpgradeConfig`.
- **StandManager** — `init()` builds the **3 physical upgrade shops** near the lobby spawn (yellow `SpawnLocation`). Each is a **clone of the imported model `ServerStorage.ShopModel`** (security-audited, scripts stripped), scaled + dropped to the ground, with its built-in floating title retitled to the stand name and its white/blue **recolored per stand** (shop1 white+blue / shop2 red+purple / shop3 purple+black). If `ServerStorage.ShopModel` is missing (e.g. a place built from src — the mesh isn't in src/), it falls back to a procedural booth + bacon-hair vendor. Each carries an **instant** `ProximityPrompt` (HoldDuration 0) with a `StandType` attribute (`"Shovel"`/`"Incubator"`/`"Luck"`). No server-side open handler — the client reads the attribute to open the matching panel; purchases go through the `Upgrade*` remotes. **To ship the model in a `rojo build`, save `ServerStorage.ShopModel` to a `.rbxmx` under `src/` and map it in `default.project.json`.**
- **RebirthManager** — `Rebirth`: requires **all three** of `LifetimeCash ≥ cashMilestone(Rebirths)`, `Gems ≥ gemCost(Rebirths)`, and `CurrentZone == highestUnlocked(Rebirths)` (no "must unlock a new zone" gate — rebirths continue past the last zone). On success: charge Gems, reset **only** `Cash` + `LifetimeCash` to 0, bump `Rebirths`, recompute the permanent compounding multipliers (gems `1.5^rb`, cash `1.2^rb`, level-cost `1.5^rb`), advance to the highest unlocked zone, then `rebuildPlots` + `applyZoneGate` (refreshes the just-broken wall's group). Collection (with levels), Gems, tiers, plots and the in-progress Incubator all **persist**; no luck bonus. Triggered from the UI **and** from clicking a shared rebirth wall (via `setRebirthHandler`).
- **StandManager** — (also covered above) `init()` only; no remotes. Idempotently builds the **3 in-world upgrade shops** (Shovel/Incubator/Luck) arced around the spawn pad — clones of `ServerStorage.ShopModel`, recolored/retitled per stand (procedural booth fallback) — each with an instant `ProximityPrompt` carrying a `StandType` attribute. Purely a build step — opening the panels and purchasing are entirely client-side + the `Upgrade*` remotes.
- **LeaderboardManager** — `init()` only. Waits for the lane fences (`ZoneFence_Left`/`Right`, built by `BaseManager`) and builds **two big 3D STONE TOMBSTONE statues** in front of them (studded slab + rounded cylinder top + plinth, `Palette.Stone`) with the rankings **ENGRAVED** into the front face — text sits directly on the stone (transparent SurfaceGui, no panel) in the **"Ghostbum" font** (`Font.fromName("Ghostbum")` via `FontFace`, not the legacy `Enum.Font`). Left = "🏆 MOST REBIRTHS" (by `Rebirths` desc), right = "💎 RAREST BRAINROT" (by tier+variant rank then $/s); refreshes the top 6 every 4s. The $/s figure sums `BrainrotMath.income(entry, Rebirths)` across the Collection.
- **AdminManager** — `init()` only. Hooks `Player.Chatted` (current + future players) for admin chat commands; every command is gated by `AdminConfig.isAdmin(player)` (UserId or case-insensitive username match). `/test` sets the caller's `Cash`/`Gems` to `AdminConfig.MaxCash`/`MaxGems` (1e12) then `PlayerData.markDirty` + `push`. Admin list + fill values live in `Shared/Config/AdminConfig.luau`.

### Client (`src/Client/*`)
- **Main.client** — builds the root `ScreenGui`, then `Effects.build` + `ClientNet.setEffects` FIRST (so toasts work), and pcall-isolates every subsystem via `startSafe` (one broken panel never aborts the rest). Start order: **`ClientState.start()` then `DigSite.start()` first** (the core loop), then the persistent HUD (`TopBar`/`HUD`/`Backpack`), the modals (`Collection`/`Rebirth`), `Stands`, `LevelUp`, and finally `SideNav` with exactly two entries — `Collection` + `Rebirth`. There is **no Shop entry/panel**; upgrade stands open via proximity.
- **ClientNet** — `invoke(funcName, ...)` wraps `RemoteFunction:InvokeServer` in pcall and toasts `result.reason` on failure.
- **ClientState** — subscribes to `PushState`, stores the latest snapshot, calls every `onChanged` listener; also pulls an initial snapshot via `RequestState` (retries to beat the join race).
- **DigSite** — scatters per-client dirt patches + lazily-built **pixel/voxel eggs** on every `DigPatch`-tagged lane slab; `ProximityPrompt` (E, `HoldDuration` from `ShovelConfig.holdDuration` — scales with rarity and the player's shovel) animates the egg popping in stages; calls `Dig` on trigger and `RollEggs` to seed a patch.
- **Sounds** — pooled `Sound` playback from `AssetConfig.Sounds`.
- **UIUtil** — the code-UI toolkit + `Colors`/`Font` palette.
- **UI/** — `Effects` (juice), `TopBar` (Cash + Gems counters + zone label), `HUD` (incubator progress/COLLECT panel), `Backpack` (🎒 panel: per-rarity egg slots → `PlaceEgg`, plus a red 🗑️ trash button per slot → `DiscardEgg`, and a Total/capacity line that turns red at MAX), `Stands` (3 in-world stand panels — Shovel/Incubator/Luck — each listing all tiers with the correct $/💎 per tier, opened via `ProximityPromptService.PromptTriggered` reading the `StandType` attribute, started from `Main.client` via `Stands.start(screen)`), `LevelUp` (per-brainrot level-up panel opened by clicking a `Brainrot`-tagged podium model's `ClickDetector`; previews next-level income + exact cost, invokes `LevelBrainrot`), `Collection` (owned brainrots grouped by tier + Lv badge + Sell), `Rebirth` (LifetimeCash progress bar + confirm-step multiplier preview keyed off `state.RebirthReady`), `SideNav` (Collection/Rebirth modal toggles; pulses the Rebirth button when `RebirthReady`). **There is no `UI/Shop.luau`** (it was deleted).

---

## 7. Key systems & where they live

| System | Where |
|---|---|
| **Egg backpack cap** (5 base, +5/rebirth, max 50) | `GameConfig.EggCapacityBase/PerRebirth/Max` + `GameConfig.eggCapacity()`; enforced in `DiggingManager.dig` |
| **Server-assigned dig rarity + pixel egg** | `DiggingManager.rollEggs/dig` (server) + `DigSite` voxel egg rendering (client) |
| **Multi-incubation** (up to 4 parallel, 0.5s hatch floor) | `IncubationManager` (`Incubators[1..4]`, `IncubatorsUnlocked`, `INCUBATOR_RANGE`, `max(0.5,…)`) using `BaseManager.getIncubatorPositions`; unlock cost `GameConfig.incubatorUnlockCost` (Cash); `Client/UI/HUD` shows one row + COLLECT per unlocked incubator |
| **Pressure-plate cash collection** | `BaseManager.buildPlate` Touched → `EconomyManager.collect` (also credits `LifetimeCash`); cash accrues in `EconomyManager.startIncomeLoop`; gems auto-credit |
| **Income formula** (tier-based, NOT zone-scaled) | `BrainrotMath.income(entry, rebirthCount)`: cash/min = `tierCash × variant.CashMult × 1.2^(level-1) × 1.2^rb`, gem/min = `(tierGem + variant.GemBonus) × 1.2^(level-1) × 1.5^rb`, ÷60 for per-second. Tier table = `BrainrotConfig.TierIncome` (Common 10c/0g, Uncommon 35c/0g, Rare 120c/1g, Legendary 500c/5g, Mythic 2000c/15g); variants CashMult 1/3/8/25, gem/min add 0/1/3/8 |
| **Brainrot leveling** (cap 10, ×1.2/level, persists rebirth) | `BrainrotConfig.Levels` (L2-5 Cash 200/600/1500/3500, L6-10 Gems 500/1200/3000/7500/18000) × `levelCostMultiplier` (`1.5^rb`); `EconomyManager.levelBrainrot` (`LevelBrainrot` remote); `Client/UI/LevelUp` panel via the `Brainrot` tag + ClickDetector + Lv billboard (`BaseManager`) |
| **Egg trash / discard** | `IncubationManager.discardEgg` (`DiscardEgg` remote); 🗑️ trash button per slot in `Client/UI/Backpack` |
| **Shared central dig lane + rebirth walls** | `BaseManager.buildSharedLane` / `buildSharedWall` / `buildZoneArea` (tagged `DigPatch`, `Zone` attribute) |
| **Zone gating (physical, per-player) + side fences** | `BaseManager.setupZoneCollision` (`ZoneGate*k*` vs `ZoneProg*p*` groups, pass when `p>k`) + `applyZoneGate(player)` (every spawn + after rebirth) + `buildLaneFences` (un-jumpable `ZoneFence_Left/Right`) |
| **In-world leaderboards** | `LeaderboardManager` mounts 2 SurfaceGui boards on the lane fences (most rebirths / rarest brainrot), top 8, 4s refresh |
| **Two-floor bases + ladder unlock** | `BaseManager.buildBuilding` (`FLOOR2_Y`; floor-2 structure in a per-slot `Floor2` folder) + a back-wall climbable `Ladder` (TrussPart) + `refreshBaseProgression` (12 plots → buyable ladder ghost; `EconomyManager.buyLadder` Cash `GameConfig.LadderCost` → reveals floor 2 + makes the ladder climbable). Plots 13-24 are gated behind the ladder. |
| **Zones & variants** | `ZoneConfig` (odds/unlock; `CashScale`/`GemScale` kept but UNUSED by income), `VariantConfig` (mults/gem-add/weights/luck bias), `BrainrotMath.income` for payout |
| **Mythic ascension** (zone 2+ only) | `IncubationManager.rollBase` (Legendary egg → Mythic chance) |
| **Asset → model mapping** | `AssetConfig.Brainrots` (id or `nil`) consumed by `BrainrotFactory.build` |
| **Rebirth** (keeps Collection; permanent compounding multipliers) | `RebirthManager.rebirth` requires ALL 3 (LifetimeCash `≥ cashMilestone`, Gems `≥ gemCost`, `CurrentZone == highestUnlocked`); resets only Cash + LifetimeCash; rewards gems `1.5^rb` / cash `1.2^rb` / level-cost `1.5^rb`. `UpgradeConfig`: `cashMilestone` 50k/150k/400k/1M/2.5M then ×2.5, `gemCost` 500/875/1531/2678/4687 then ×1.75; no luck bonus |
| **Luck** (Gems, 9 tiers, tier 9 max; no rebirth bonus) | `UpgradeConfig.Luck` (50/150/400/1000/2500/6000/12000/25000/50000); `totalLuck` = sum of unlocked tier `Value`s only; `UpgradeManager.buyLuck` (`UpgradeLuck`) |
| **Incubator** (Cash 1-5 / Gems 6-9, 9 named tiers, hatch-time reduction) | `UpgradeConfig.Incubator` (Cash 100/300/800/2000/5000, Gems 200/600/1500/4000); `incubatorReduction(level)`; `UpgradeManager.buyIncubator` (`UpgradeIncubator`, was `UpgradeHatchSpeed`); 0.5s floor in `IncubationManager` |
| **Dig-speed shovels** (Cash 1-5 / Gems 6-9, 9 tiers Wood→Galaxy) | `ShovelConfig` (Cash 50/150/400/1000/2500, Gems 100/300/800/2000; `DigSpeedMult`, `Stages`/`PerStage`/`holdDuration`/`MinDigTime` 0.3s floor/`CooldownTolerance`) consumed by `DigSite` (prompt hold) + `DiggingManager` (cooldown); bought via `UpgradeManager.buyShovel` |
| **Upgrade access (in-world shops, no shop icon)** | `StandManager` builds 3 shops (clones of `ServerStorage.ShopModel`, recolored/retitled per stand; procedural booth fallback) with instant-E prompts (`StandType` attr `Shovel`/`Incubator`/`Luck`); `Client/UI/Stands` opens the matching tier-list panel |
| **Plot buying (base ghost podium, no shop)** | per-slot `slotGhostPlot` ghost "🔒 Buy Plot" podium built by `BaseManager`; occupant click routes through `EconomyManager.buyPlot` (`BuyPlot` remote). Cost curve (`GameConfig.plotCost`): Nth slot beyond `StartingPlots`(3) = 100/300/800/2000/5000/12000 then DOUBLES each slot after the 6th; `MaxPlots` 24 |
| **Lane-flanking cliff walls** (tighten lane width) | `BaseManager.buildLaneSideWalls` — two grass-topped (`Palette.Grass`) **dirt "mountain" cliffs** (`Palette.Dirt`) running parallel to the lane (+Z) just outside the forest strip, from past the front bases to past the last dig site. Tune `LANE_SIDE_INNER_X` (lower = thinner lane), `LANE_SIDE_THICK`, `LANE_SIDE_BODY_H`, `LANE_SIDE_CAP_H`. (Replaced the old map-wide snow border.) |
| **Vibrant legoish look** | `Palette.luau` (saturated color source of truth) + `Shared/Modules/Surface.luau` (`applyStuds`/`shouldStud`: classic stud TEXTURE `rbxassetid://8130710802` on every face, tinted to the part colour). `StudsPerTile = 3` (chunky studs) and `TINT_BRIGHTEN = 0.8` (tint just BELOW the part colour so stud highlights don't clip to white and the inlets read DEEP). Called from each `makePart` (MapBuilder/BaseManager/StandManager) + `DigSite.buildDirt`; world surfaces use the matte **`Plastic`** material (was SmoothPlastic — switched to kill specular glare); pixel/voxel eggs in `DigSite` stay untextured. **Grass is studded the same way**, with a subtle 6x6 two-green checker overlaid on top (next row) |
| **Grass = studded + checker overlay** | Grass parts (`Ground`, `ZoneBorder`, `LaneWallGrass`) are studded normally AND tagged **`GrassSurface`**. `Client/GrassChecker` overlays a runtime `EditableImage` on each one's top face (`StudsPerTileU/V = 12` → 6-stud cells): light cells fully transparent, dark cells `Palette.GrassCheckerB` #54B312 at ~0.45 alpha, so the **classic studs read through both cells**. Two stacked top-face Textures layer fine (no z-fight). Client-side (EditableImage doesn't replicate); falls back to plain studded green if unavailable |

---

## 8. Gotchas

- **Rojo live-sync does NOT re-run already-running scripts.** A live sync replaces source, but `Bootstrap.server.luau` / `Main.client.luau` only build the world/UI **once on run**. After editing, do a full **Stop → Play** in Studio (or rebuild the place) — otherwise you are looking at stale code that already ran.
- **Multiple Studio windows / testing the wrong place.** It's easy to have several Studio windows open and edit/play the wrong one, or to test a live-synced Baseplate while the *rebuilt* `HatchABrainrot-LATEST.rbxlx` is the real target. Keep **one** window, Stop+Play it, and when delivering rebuild `HatchABrainrot-LATEST.rbxlx` and Publish-As to update the live game.
- **Published games load profiles from the DataStore → join race.** On a published server the client can fire requests before its profile finishes loading. Client requests must tolerate this: `ClientState` retries `RequestState` (6×, 1s) and `DigSite` retries `RollEggs` directly (20×, 1s, no toast on transient "No profile"). Don't remove those retries.
- **OneDrive nesting.** The project lives inside OneDrive; sync can occasionally create odd folder nesting or lock files (e.g. `HatchABrainrot-LATEST.rbxlx.lock`). Keep the folder set to **"Always keep on this device."**
- **Always `rojo build` after edits** (Section 3) — it's the only automated signal that the code still compiles/serializes.
- **Shell is Windows PowerShell 5.1.** Use `$null` (not `/dev/null`), `$env:VAR`, backtick line-continuation, `;`/`if ($?)` chaining (no `&&`/`||`). Pin paths absolutely.
- **No analyzer/linter/formatter** is installed — `--!strict` typing is your only static safety net; keep it correct.
- **Workflow-driven dev.** Changes are typically made via dynamic multi-agent workflows (an **implement** phase + an adversarial **review** phase), always finishing with a `rojo build`.
- **DataStore is optional in Studio** — without API access the game still runs (no persistence; `PlayerData` falls back to non-saving temporary profiles flagged `__doNotSave`). Don't add code that hard-requires saving.

---

## 9. Making changes — checklist

1. **Balance/data change?** Edit the relevant `src/Shared/Config/*` file (and a derived helper if needed). Do **not** bury constants in manager logic.
2. **New gameplay action?** Add the remote name to `Net.Events`/`Net.Functions`, register the handler in the owning manager's `init()`, validate fully server-side, and consume it from the client via `ClientNet.invoke`.
3. **Geometry/layout change?** Adjust the **named constants** in `BaseManager` / `MapBuilder`; keep derived constants (e.g. `FLOOR2_Y`, `STAIR_*`) consistent.
4. **Keep server authority.** The client may preview (using `BrainrotMath`) but never decide. Recompute/validate on the server.
5. **Keep income math single-sourced** via `BrainrotMath.income`.
6. **Validate:** run the `rojo build` command in Section 3. `exit 0`/file-produced = pass.
7. **Playtest** in Studio (`rojo serve` + Play) for anything behavioral — there is no test suite to catch logic regressions.
