# 🧠 Hatch a Brainrot

A complete, playable Roblox game built in Luau and organized for **Rojo**.
Dig for eggs → hatch Italian Brainrot memes (in 4 variants) → display them on
glowing podiums that generate Cash & Gems → level up your brainrots and upgrade
Shovel / Incubator / Luck at in-world stands → rebirth to permanently multiply
your income (keeping your whole collection).

Everything is **code-driven** — UI, map, and brainrot models are all generated
at runtime, so the game is fully playable on first run with **zero asset IDs**.
Drop Creator Store asset IDs into `AssetConfig.luau` later to replace the chunky
placeholder models.

The whole world wears a **vibrant, semi-pixelated legoish look**: saturated
colors from `Palette.luau`, studded plastic parts, studded dirt dig mounds, and
pixel/voxel eggs.

---

## 📁 File structure

```
HatchABrainrot/
├── default.project.json          # Rojo project (maps src/ → DataModel)
├── README.md
└── src/
    ├── Shared/                    → ReplicatedStorage.Shared
    │   ├── Config/
    │   │   ├── GameConfig.luau        global tunables (timings, plot-cost curve, autosave)
    │   │   ├── RarityColors.luau      tier + variant color language
    │   │   ├── EggConfig.luau         egg costs, incubation times, tier mapping
    │   │   ├── BrainrotConfig.luau    roster + per-tier income + per-brainrot levels (cap 10)
    │   │   ├── VariantConfig.luau     Normal/Gold/Diamond/Galaxy mults + gem add + odds
    │   │   ├── ZoneConfig.luau        per-zone egg odds + pools (CashScale/GemScale unused by income)
    │   │   ├── UpgradeConfig.luau     Luck (9 tiers) / Incubator (9 tiers) + Rebirth rules + multipliers
    │   │   ├── ShovelConfig.luau      dig-speed shovel: 9 tiers + dig hold/cooldown (0.3s floor)
    │   │   ├── AssetConfig.luau       Creator Store asset IDs (all nil → procedural)
    │   │   └── Palette.luau           VIBRANT legoish world-color source of truth
    │   └── Modules/
    │       ├── Net.luau               RemoteEvent/Function registry
    │       ├── Format.luau            number/time formatting (1.5K, mm:ss)
    │       ├── Util.luau              weighted random + uid helpers
    │       └── BrainrotMath.luau      single source of truth for income math
    │
    ├── Server/                    → ServerScriptService.Server
    │   ├── Bootstrap.server.luau      entry point: wires everything, lifecycle
    │   └── Managers/
    │       ├── PlayerData.luau        DataStore load/save + reconcile + snapshots
    │       ├── MapBuilder.luau        builds the world + spawn + snow-capped dirt map border
    │       ├── BaseManager.luau       bases, podiums, plates, ghost Buy-Plot, dig lane + zone gates + fences, model placement
    │       ├── BrainrotFactory.luau   Creator Store insert OR procedural fallback
    │       ├── DiggingManager.luau    luck-weighted egg rolls + dig proximity + rarity cooldown
    │       ├── IncubationManager.luau hatch timers + base/variant rolling + egg discard
    │       ├── EconomyManager.luau    passive income, plots, selling, brainrot leveling
    │       ├── UpgradeManager.luau    Shovel + Incubator + Luck purchases (per-tier Cash/Gems)
    │       ├── StandManager.luau      builds 3 in-world upgrade stands + bacon NPCs
    │       ├── RebirthManager.luau    3-requirement check + reset Cash only + permanent multipliers
    │       └── LeaderboardManager.luau in-world boards: most rebirths + rarest brainrot
    │
    └── Client/                    → StarterPlayer.StarterPlayerScripts.Client
        ├── Main.client.luau           builds the whole UI, starts state sync
        ├── UIUtil.luau                chunky rounded buttons/frames/tweens
        ├── ClientState.luau           holds authoritative server snapshot
        ├── ClientNet.luau             remote wrapper + failure toasts
        ├── DigSite.luau               per-client dig mounds + hold-E-to-dig prompts
        ├── Sounds.luau                SFX pool
        └── UI/
            ├── Effects.luau           toasts, +$/+Gem popups, hatch reveal, shake
            ├── TopBar.luau            Cash/Gem counters + zone label
            ├── HUD.luau               incubator panel: progress bar, countdown, COLLECT
            ├── Backpack.luau          🎒 eggs-per-rarity tray: click to hatch, 🗑️ to discard
            ├── Stands.luau            3 in-world stand panels (Shovel/Incubator/Luck)
            ├── LevelUp.luau           per-brainrot level-up panel (click your podium)
            ├── Collection.luau        owned brainrots by tier + variant + Lv badge
            ├── Rebirth.luau           rebirth panel + confirmation
            └── SideNav.luau           toggle buttons for the modals (Collection/Rebirth)
```

---

## ▶️ How to test in Studio

### Option A — Rojo live sync (recommended)
1. Install [Rojo](https://rojo.space) (`rokit add rojo-rbx/rojo` or download the
   plugin + CLI). Install the **Rojo** Studio plugin.
2. In a terminal in this folder, run:
   ```
   rojo serve
   ```
3. In Studio: open a new **Baseplate**, click the Rojo plugin → **Connect**.
   The whole tree syncs into ReplicatedStorage / ServerScriptService /
   StarterPlayer.
4. Press **Play**. You spawn on the grass field.

### Option B — Build a place file
```
rojo build -o HatchABrainrot-LATEST.rbxlx
```
Open `HatchABrainrot-LATEST.rbxlx` in Studio and press **Play**. (Note: Rojo live-sync
does not re-run already-running scripts, so after editing do a full **Stop → Play**, or
rebuild this place file, to avoid testing stale code.)

### ⚙️ Enable saving
For DataStore persistence: **Game Settings → Security → Enable Studio Access to
API Services** (and the game must be saved to Roblox). Without it the game still
runs perfectly — it just won't persist between sessions (it logs a warning and
uses a temporary profile that is never written, so real saves are never
overwritten).

---

## 🎮 How to play
1. Walk to the green **dig lane** on the open side of the lobby and **hold E** on
   a mound to dig — an egg pops out of the dirt. Its rarity is decided up front,
   so rarer eggs look bigger and take longer to dig. Eggs go into your **🎒
   backpack** (starts at 5, +5 per rebirth, max 50).
2. Open your **🎒 backpack** (left). Click an egg to start hatching it at your base's
   front **🥚 Incubator** (watch the live progress bar in the HUD), or hit the **🗑️**
   on a slot to throw away an egg you don't want (no refund).
3. Press **COLLECT** when it's ready — a brainrot + variant is revealed and
   placed on a glowing podium at your base. It accrues Cash (walk over its green
   **pressure plate** to bank it); Gems auto-credit. Income depends on its tier,
   variant, **level**, and your rebirth count.
4. **Click one of your brainrots** on its podium to open the **⬆️ Level Up**
   panel — leveling (cap 10) multiplies that brainrot's Cash *and* Gem income
   (Cash for levels 2-5, Gems for 6-10). Levels are kept forever, even through
   rebirth.
5. Walk up to the **upgrade stands** near the lobby spawn — each is run by a
   bacon-hair vendor, just press **E** (instant) to open it: 🪓 **Shovel** (faster
   digging), 🔥 **Incubator** (faster hatching), and 🍀 **Luck** (better
   eggs/variants). Each track has 9 tiers (early tiers cost Cash, later tiers
   cost Gems). Buy more **Plots** at your base by clicking the **🔒 Buy Plot**
   podium on your next free slot.
6. Open **📦 Collection** to view everything you own by tier + variant, or sell.
7. Hit **🔁 Rebirth** at a lane wall once you meet all three requirements
   (Lifetime Cash milestone, Gem cost, and being in your highest unlocked zone).
   Rebirth is **not** a fresh start: it keeps your whole collection (with levels),
   Gems, upgrade tiers and plots, resets only your Cash, and **permanently
   multiplies your income** — Gems ×1.5 and Cash ×1.2 per rebirth, compounding.
   Rebirthing also unlocks the next **Zone** (rarer eggs, exclusive Mythic
   brainrots) until you reach the last one, then keeps going for more multipliers.
   (Each zone is gated by a physical wall you can only walk through once you've
   unlocked it.)
8. Check the **in-world leaderboard boards** on the dig-lane fences — 🏆 most
   rebirths and 💎 rarest brainrot — to see how you stack up.

---

## 🖼️ Swapping in Creator Store models
Open `src/Shared/Config/AssetConfig.luau` and paste real Creator Store asset IDs
next to each brainrot name (and optionally the egg/incubator models + UI icons).
`BrainrotFactory` will insert those via `InsertService`, anchor + normalize them
onto the podiums, and only fall back to the procedural placeholder for any
brainrot left as `nil`. Use **only** official, moderated Creator Store assets.

---

## 🔒 Security notes
All gameplay is validated on the **server**. The client can only *request*
actions via RemoteFunctions; the server decides currency, items, cooldowns,
costs, dig proximity, and incubation timing. The client never grants itself
anything — it only reflects the authoritative snapshot the server pushes.

## ➕ Adding a zone
Append an entry to `ZoneConfig.Zones` (egg odds, brainrot tiers, `UnlockRebirths`,
display name/color) and bump `MaxZone`. Digging, the rebirth unlock chain, and the
map all read from it automatically. (Note: income is no longer zone-scaled —
`CashScale`/`GemScale` are kept for reference but unused; payouts scale with the
permanent rebirth multipliers instead.)
