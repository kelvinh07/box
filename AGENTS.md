# AGENTS.md — Hatch a Brainrot

Canonical, cross-tool guide for LLM coding assistants working in this repo. Keep it accurate to the code; if you change structure or APIs, update this file.

---

## 1. Project overview

**Hatch a Brainrot** is a Roblox tycoon-style game written in **Luau** and organized for **Rojo**. Everything — UI, the map, brainrot models, bases, the dig lane — is **generated in code at runtime**. There are **no `.rbxmx` / model assets in the repo**; the only checked-in binary is `HatchABrainrot.rbxl` (a placeholder place file).

### Core gameplay loop
1. Walk to the **shared central dig lane** (on the half-circle opening side of the lobby).
2. **Hold E to dig** a mound — a pixel/voxel egg pops out of the dirt in stages. Rarity is **server-assigned up front**, so rarer eggs look different (bigger, different color, longer dig) before you finish.
3. Eggs go into a **BACKPACK** (capacity starts **5**, **+5 per rebirth**, capped **50**; opened via the left-side 🎒 button).
4. **Hatch an egg only at your base front INCUBATOR** (server proximity-checked).
5. The hatched brainrot **spins on a podium** and **accrues cash**.
6. Walk over that brainrot's **green PRESSURE PLATE** to collect its accrued cash. **Gems auto-credit** (no plate needed).
7. Spend on **plots / gem upgrades**; then **REBIRTH** at a lane/wall gate to unlock the next **ZONE** (rarer eggs, higher cash/gem scaling).

Brainrots have **rarity tiers** (Common → Uncommon → Rare → Legendary, plus zone 2+ exclusive **Mythic**) and **4 variants** (Normal / Gold / Diamond / Galaxy) that multiply stats and add glow.

---

## 2. Repo layout

```
robloxrename/
├── aftman.toml                  # toolchain pin (rojo 7.7.0-rc.1)
├── default.project.json         # Rojo project: maps src/ into the DataModel
├── HatchABrainrot.rbxl          # placeholder place file (binary)
├── README.md
└── src/
    ├── Shared/                  # -> ReplicatedStorage.Shared
    │   ├── Config/              # ALL gameplay balance + data tables (tune here)
    │   │   ├── GameConfig.luau      # global tunables: starting cash/gems/plots, egg capacity, plot cost, DataStore, ticks
    │   │   ├── EggConfig.luau       # egg rarities: HatchCost, Incubation seconds, BrainrotTier
    │   │   ├── BrainrotConfig.luau  # brainrot roster: Tier, BaseCash, BaseGem, Color, Scale
    │   │   ├── VariantConfig.luau   # Normal/Gold/Diamond/Galaxy: CashMult, GemBonus, Weight, LuckBias
    │   │   ├── ZoneConfig.luau      # per-zone DigOdds, BrainrotTiers, CashScale, GemScale, UnlockRebirths
    │   │   ├── UpgradeConfig.luau   # Luck (10 tiers) + HatchSpeed (9 named tiers, cap 85%), Rebirth rules, derived helpers
    │   │   ├── ShovelConfig.luau    # dig-speed shovel: 9 named tiers (DigSpeedMult), per-rarity hold stages + cooldown helpers
    │   │   ├── RarityColors.luau    # tier/variant/currency color language
    │   │   └── AssetConfig.luau     # brainrot name -> Creator Store asset id (nil => procedural), icons, SFX
    │   └── Modules/
    │       ├── Net.luau             # central RemoteEvent/RemoteFunction registry (server creates, clients fetch)
    │       ├── BrainrotMath.luau    # SINGLE source of truth for income math (server + client share it)
    │       ├── Format.luau          # number abbreviation (1.5K, 2.3M) + mm:ss
    │       └── Util.luau            # weightedPick, choice, uid, shallowCopy
    │
    ├── Server/                  # -> ServerScriptService.Server
    │   ├── Bootstrap.server.luau    # single entry point: setup remotes, build world, init managers, player lifecycle
    │   └── Managers/                # ModuleScripts, each with init() wired by Bootstrap
    │       ├── PlayerData.luau       # authoritative profiles: DataStore load/save, snapshot, push
    │       ├── MapBuilder.luau       # shared ground + spawn; exposes DigCenter / DigRadius
    │       ├── BaseManager.luau      # the 10 base buildings, podiums, plates, incubators, stairs, shared dig lane + rebirth walls
    │       ├── BrainrotFactory.luau  # builds a brainrot model (Creator Store asset OR procedural placeholder) + variant glow + label
    │       ├── DiggingManager.luau   # server-authoritative digging: RollEggs / Dig, proximity + cooldown + cap checks
    │       ├── IncubationManager.luau# PlaceEgg / CollectIncubator: hatch timing, base+variant roll, Mythic ascension
    │       ├── EconomyManager.luau   # passive income loop, per-brainrot cash accrual + collect, BuyPlot, SellBrainrot
    │       ├── UpgradeManager.luau   # UpgradeShovel (Cash) / UpgradeLuck / UpgradeHatchSpeed (gem-purchased)
    │       ├── StandManager.luau     # builds the 3 in-world upgrade stands + bacon-hair NPC vendors, instant-E prompts
    │       └── RebirthManager.luau   # Rebirth: milestone+gem checks, reset, zone unlock, permanent luck
    │
    └── Client/                  # -> StarterPlayer.StarterPlayerScripts.Client
        ├── Main.client.luau         # entry point: builds the whole UI in code, wires effects/net, starts state
        ├── ClientNet.luau           # thin RemoteFunction wrapper; toasts the server's rejection reason
        ├── ClientState.luau         # holds latest server snapshot, fans out onChanged() to UI panels
        ├── DigSite.luau             # per-client dirt mounds + pixel/voxel eggs over the shared lane; E-to-dig prompts (hold time from ShovelConfig)
        ├── Sounds.luau              # SFX pool (ids from AssetConfig.Sounds)
        ├── UIUtil.luau              # code-built UI helpers (frame/label/button/modal/corner/stroke/pop)
        └── UI/
            ├── Effects.luau         # toasts, +$/+Gem popups, hatch reveal card, screen-shake (server-driven)
            ├── TopBar.luau          # top-center Cash/Gem counters + zone label
            ├── HUD.luau             # always-on incubator panel: progress bar, countdown, COLLECT
            ├── Backpack.luau        # 🎒 toggle panel: eggs per rarity, capacity line, click to PlaceEgg
            ├── Stands.luau          # 3 in-world stand tier-list panels (Shovel/HatchSpeed/Luck), opened by ProximityPrompt
            ├── Collection.luau      # owned brainrots grouped by tier, variant-colored cards, Sell button
            ├── Rebirth.luau         # rebirth progress + confirm step
            └── SideNav.luau         # right-side buttons toggling Collection/Rebirth modals
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
- **Per-slot BaseManager state.** Base structures are keyed by **slot** (1..10), not by player. State tables: `slotFolder`, `slotPodiums`, `slotPodiumCount`, `slotModels`, `slotPlates`, `slotSign`, `slotIncubator`, `slotStairBarrier`, `slotGhostPlot`, plus a dynamic `slotOccupant` / `playerSlot` lookup. (Rebirth gating is **not** per-slot — the walls belong to the single shared central dig lane.) Joining a player only marks the slot occupant, renames the sign, rebuilds podiums to plot count, and loads their brainrots.
- **Constants-driven geometry.** Layout is tuned via named constants, never magic numbers inline:
  - `BaseManager`: `LOBBY_RADIUS`, `ARC_SPAN_DEG`, `MAX_SLOTS`, `FLOOR`, `WALL_H`, `WALL_T`, `FLOOR2_Y`, `SEG_SIZE`, `REBIRTH_WALL`, `PLATE`, `STAIR_GAP` / `STAIR_STEPS` / `STAIR_STEP_H` / `STAIR_STEP_D` / `STAIR_FRONT_LZ` / `STAIR_ENTRANCE_LZ`.
  - `MapBuilder`: `DigCenter`, `DigRadius`.
- **One income math source.** `Shared/Modules/BrainrotMath.income(entry, zone)` is used by **both** the server (payout) and client (preview) so displayed numbers always match payouts.
- **`AssetConfig` maps brainrot names → Creator Store asset IDs.** `nil` ⇒ a chunky procedural placeholder via `BrainrotFactory`. Swap real IDs in `AssetConfig.luau` only.

---

## 5. Remotes (`src/Shared/Modules/Net.luau`)

The server calls `Net.setupServer()` once (creates a `Remotes` folder under `ReplicatedStorage.Shared`). Clients use `Net.getEvent(name)` / `Net.getFunction(name)`.

**Events (server → client, `RemoteEvent`):**
`PushState`, `Notify`, `HatchResult`, `FloatingText`, `ScreenShake`

**Functions (client → server, `RemoteFunction`, return `{ok=…, …}`):**
`RequestState`, `RollEggs`, `Dig`, `PlaceEgg`, `CollectIncubator`, `BuyPlot`, `UpgradeShovel`, `UpgradeLuck`, `UpgradeHatchSpeed`, `Rebirth`, `SellBrainrot`

These exact strings are the contract — match them precisely on both sides.

---

## 6. Per-module map

### Server managers (`src/Server/Managers/*`)
- **PlayerData** — authoritative profiles. DataStore (`HatchABrainrot_v1`) load/save with retries + reconcile of new fields; in-memory `cache`/`dirty`; `snapshot()` builds the derived client payload (next plot cost, egg capacity, total luck, hatch reduction, rebirth readiness); `push()` fires `PushState`; periodic autosave + `BindToClose` final save. Falls back to non-persistent profiles if the DataStore is unavailable (and refuses to overwrite real data on a failed load via `__doNotSave`).
- **MapBuilder** — builds the shared `World` (big grass ground + neutral `SpawnLocation`). Exposes `DigCenter`/`DigRadius` consumed by BaseManager.
- **BaseManager** — the heaviest module. Pre-builds **10 two-floor base buildings** in a rounded half-circle ring facing center; podiums along the side window walls (6/side/floor, up to 24); green pressure plates per podium (Touched → `EconomyManager.collect`); per-slot incubator out the open front; a back-center **staircase** to floor 2 gated by `StairBarrier`; and the **single shared dig lane** with **rebirth walls** between zones (`buildSharedLane` / `buildSharedWall`). Public: `assignBase`, `freeBase`, `placeBrainrot`, `removeBrainrot`, `rebuildPlots`, `getIncubatorPosition`, `getOrigin`, `updateStaircase`, `startGateUpdater`, `setRebirthHandler`.
- **BrainrotFactory** — `build(entry, zone)` returns an anchored model: Creator Store asset (via `InsertService:LoadAsset`, normalized to uniform size) if `AssetConfig` has an id, otherwise a procedural placeholder (ball body + eyes + feet). Adds variant glow (PointLight + sparkles, rainbow shimmer for Galaxy) and a billboard name/income label. Exposes `PODIUM_SIZE`.
- **DiggingManager** — `RollEggs(count, zone)` pre-assigns luck-weighted rarities to mounds (keyed by server id, capped by `MAX_PENDING`/`MAX_ROLL_BATCH`); `Dig(id)` validates a **rarity-aware, shovel-scaled cooldown** (`cd = ShovelConfig.holdDuration(rarity, mult) * 0.85`, so rarer eggs / slower shovels enforce a longer dig), `DigPatch` proximity, backpack cap, then grants the egg and pre-rolls the mound's next rarity. (The flat `GameConfig.DigCooldown` is superseded and kept only as a reference.) Luck shifts odds toward Uncommon/Rare/Legendary.
- **IncubationManager** — `PlaceEgg(rarity)`: incubator proximity (`INCUBATOR_RANGE`), spends egg + Cash hatch cost, starts a timer of `Incubation * (1 - HatchReduction)`. `CollectIncubator`: once `GetServerTimeNow()` passes `endTime`, rolls a base brainrot of the egg tier available in the zone (Legendary can **ascend to Mythic** in zone 2+) + a luck-weighted variant, appends to `Collection`, places the model, fires `HatchResult` + `ScreenShake`.
- **EconomyManager** — passive income loop (every `IncomeTickSeconds`): per brainrot, **cash accrues** per-brainrot (capped, collected at its plate via `collect`); **gems auto-credit** (fractional accumulator → floor → `FloatingText`). Also `buyPlot` (Cash, escalating cost — now reached by clicking the per-slot **ghost plot podium** on the base, server-authoritative as before), `sellBrainrot` (refund ≈ 30 cycles of cash). `getAccrued` feeds the plate labels.
- **UpgradeManager** — `UpgradeShovel` (Cash, validated against `ShovelConfig` Cash cost + level cap) / `UpgradeLuck` (10 tiers) / `UpgradeHatchSpeed` (9 named tiers, gem-purchased), escalating cost, validated against `UpgradeConfig`. Hatch speed effect hard-capped at 85%.
- **StandManager** — `init()` builds the **3 physical upgrade stands** near the lobby spawn, each staffed by a procedural classic "bacon hair" NPC vendor and carrying an **instant** `ProximityPrompt` (HoldDuration 0) with a `StandType` attribute (`"Shovel"`/`"HatchSpeed"`/`"Luck"`). No server-side open handler — the client reads the attribute to open the matching panel and purchases go through the `Upgrade*` remotes.
- **RebirthManager** — `Rebirth`: requires the Cash milestone, requires that a rebirth actually unlocks a new zone, charges gems, resets Cash + Collection + Incubator, advances `CurrentZone`, grants permanent luck (via `Rebirths` count). Triggered from the UI **and** from clicking a shared rebirth wall (via `setRebirthHandler`).

### Client (`src/Client/*`)
- **Main.client** — builds the root `ScreenGui` and every UI panel; wires `Effects` into `ClientNet`; starts `DigSite` and `ClientState`.
- **ClientNet** — `invoke(funcName, ...)` wraps `RemoteFunction:InvokeServer` in pcall and toasts `result.reason` on failure.
- **ClientState** — subscribes to `PushState`, stores the latest snapshot, calls every `onChanged` listener; also pulls an initial snapshot via `RequestState` (retries to beat the join race).
- **DigSite** — scatters per-client dirt patches + lazily-built **pixel/voxel eggs** on every `DigPatch`-tagged lane slab; `ProximityPrompt` (E, `HoldDuration` from `ShovelConfig.holdDuration` — scales with rarity and the player's shovel) animates the egg popping in stages; calls `Dig` on trigger and `RollEggs` to seed a patch.
- **Sounds** — pooled `Sound` playback from `AssetConfig.Sounds`.
- **UIUtil** — the code-UI toolkit + `Colors`/`Font` palette.
- **UI/** — `Effects` (juice), `TopBar` (currency + zone), `HUD` (incubator panel), `Backpack` (eggs → PlaceEgg), `Stands` (3 in-world stand panels — Shovel/HatchSpeed/Luck — opened via `ProximityPromptService.PromptTriggered` reading the `StandType` attribute, started from `Main.client` via `Stands.start(screen)`), `Collection` (owned brainrots + Sell), `Rebirth` (rebirth flow), `SideNav` (modal toggles).

---

## 7. Key systems & where they live

| System | Where |
|---|---|
| **Egg backpack cap** (5 base, +5/rebirth, max 50) | `GameConfig.EggCapacityBase/PerRebirth/Max` + `GameConfig.eggCapacity()`; enforced in `DiggingManager.dig` |
| **Server-assigned dig rarity + pixel egg** | `DiggingManager.rollEggs/dig` (server) + `DigSite` voxel egg rendering (client) |
| **Incubator-proximity hatching** | `IncubationManager` (`INCUBATOR_RANGE`) using `BaseManager.getIncubatorPosition` |
| **Pressure-plate cash collection** | `BaseManager.buildPlate` Touched → `EconomyManager.collect`; cash accrues in `EconomyManager.startIncomeLoop`; gems auto-credit |
| **Shared central dig lane + rebirth walls** | `BaseManager.buildSharedLane` / `buildSharedWall` / `buildZoneArea` (tagged `DigPatch`, `Zone` attribute) |
| **Two-floor bases + staircase unlock** | `BaseManager.buildBuilding` (`FLOOR2_Y`, `STAIR_*`) + `updateStaircase` (opens once occupant owns all 12 floor-1 plots) |
| **Zones & variants** | `ZoneConfig` (odds/scaling/unlock), `VariantConfig` (mults/weights/luck bias), `BrainrotMath.income` for payout |
| **Mythic ascension** (zone 2+ only) | `IncubationManager.rollBase` (Legendary egg → Mythic chance) |
| **Asset → model mapping** | `AssetConfig.Brainrots` (id or `nil`) consumed by `BrainrotFactory.build` |
| **Rebirth rules / luck / hatch speed** | `UpgradeConfig` (Luck = 10 tiers, HatchSpeed = 9 named tiers capped 85% via `MaxHatchSpeedReduction`; helpers: `totalLuck`, `hatchReduction`, `rebirthGemCost`) |
| **Dig-speed shovels** (Cash, 9 named tiers Wood→Galaxy) | `ShovelConfig` (`DigSpeedMult`, `Stages`/`PerStage`/`holdDuration`/`CooldownTolerance`) consumed by `DigSite` (prompt hold) + `DiggingManager` (cooldown); bought via `UpgradeManager.buyShovel` |
| **Upgrade access (in-world stands, no shop icon)** | `StandManager` builds 3 stands + bacon NPCs with instant-E prompts (`StandType` attr); `Client/UI/Stands` opens the matching tier-list panel |
| **Plot buying (base ghost podium)** | per-slot `slotGhostPlot` ghost "🔒 Buy Plot" podium built by `BaseManager`; occupant click routes through `EconomyManager.buyPlot` (`BuyPlot` remote) |

---

## 8. Gotchas

- **OneDrive nesting.** The project lives inside OneDrive; sync can occasionally create odd folder nesting or lock files (`HatchABrainrot.rbxl.lock`). Keep the folder set to **"Always keep on this device."**
- **Always `rojo build` after edits** (Section 3) — it's the only automated signal that the code still compiles/serializes.
- **Shell is Windows PowerShell 5.1.** Use `$null` (not `/dev/null`), `$env:VAR`, backtick line-continuation, `;`/`if ($?)` chaining (no `&&`/`||`). Pin paths absolutely.
- **No analyzer/linter/formatter** is installed — `--!strict` typing is your only static safety net; keep it correct.
- **Workflow-driven dev.** Changes are typically made via dynamic multi-agent workflows (an **implement** phase + an adversarial **review** phase), always finishing with a `rojo build`.
- **DataStore is optional in Studio** — without API access the game still runs (no persistence). Don't add code that hard-requires saving.

---

## 9. Making changes — checklist

1. **Balance/data change?** Edit the relevant `src/Shared/Config/*` file (and a derived helper if needed). Do **not** bury constants in manager logic.
2. **New gameplay action?** Add the remote name to `Net.Events`/`Net.Functions`, register the handler in the owning manager's `init()`, validate fully server-side, and consume it from the client via `ClientNet.invoke`.
3. **Geometry/layout change?** Adjust the **named constants** in `BaseManager` / `MapBuilder`; keep derived constants (e.g. `FLOOR2_Y`, `STAIR_*`) consistent.
4. **Keep server authority.** The client may preview (using `BrainrotMath`) but never decide. Recompute/validate on the server.
5. **Keep income math single-sourced** via `BrainrotMath.income`.
6. **Validate:** run the `rojo build` command in Section 3. `exit 0`/file-produced = pass.
7. **Playtest** in Studio (`rojo serve` + Play) for anything behavioral — there is no test suite to catch logic regressions.
