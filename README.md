# 🧠 Hatch a Brainrot

A complete, playable Roblox game built in Luau and organized for **Rojo**.
Dig for eggs → hatch Italian Brainrot memes (in 4 variants) → display them on
glowing podiums that generate Cash & Gems → upgrade Luck / Hatch Speed → rebirth
to unlock new zones.

Everything is **code-driven** — UI, map, and brainrot models are all generated
at runtime, so the game is fully playable on first run with **zero asset IDs**.
Drop Creator Store asset IDs into `AssetConfig.luau` later to replace the chunky
placeholder models.

---

## 📁 File structure

```
HatchABrainrot/
├── default.project.json          # Rojo project (maps src/ → DataModel)
├── README.md
└── src/
    ├── Shared/                    → ReplicatedStorage.Shared
    │   ├── Config/
    │   │   ├── GameConfig.luau        global tunables (timings, plots, autosave)
    │   │   ├── RarityColors.luau      tier + variant color language
    │   │   ├── EggConfig.luau         egg costs, incubation times, tier mapping
    │   │   ├── BrainrotConfig.luau    base brainrot roster + base income/gems
    │   │   ├── VariantConfig.luau     Normal/Gold/Diamond/Galaxy mults + odds
    │   │   ├── ZoneConfig.luau        per-zone egg odds, pools, currency scaling
    │   │   ├── UpgradeConfig.luau     Luck (10 tiers)/Hatch Speed (9 tiers, cap 85%) + Rebirth rules
    │   │   ├── ShovelConfig.luau      dig-speed shovel: 9 named tiers + dig hold/cooldown
    │   │   └── AssetConfig.luau       Creator Store asset IDs (placeholders here)
    │   └── Modules/
    │       ├── Net.luau               RemoteEvent/Function registry
    │       ├── Format.luau            number/time formatting (1.5K, mm:ss)
    │       ├── Util.luau              weighted random + uid helpers
    │       └── BrainrotMath.luau      single source of truth for income math
    │
    ├── Server/                    → ServerScriptService.Server
    │   ├── Bootstrap.server.luau      entry point: wires everything, lifecycle
    │   └── Managers/
    │       ├── PlayerData.luau        DataStore load/save + retries + snapshots
    │       ├── MapBuilder.luau        builds the world + dig field
    │       ├── BaseManager.luau       per-player base, podiums, model placement
    │       ├── BrainrotFactory.luau   Creator Store insert OR procedural fallback
    │       ├── DiggingManager.luau    luck-weighted egg rolls + dig proximity
    │       ├── IncubationManager.luau hatch timers + base/variant rolling
    │       ├── EconomyManager.luau    passive income loop, plots, selling
    │       ├── UpgradeManager.luau    Shovel (Cash) + Luck + Hatch Speed purchases
    │       ├── StandManager.luau      builds 3 in-world upgrade stands + bacon NPCs
    │       └── RebirthManager.luau    reset + zone unlock + permanent luck
    │
    └── Client/                    → StarterPlayer.StarterPlayerScripts.Client
        ├── Main.client.luau           builds the whole UI, starts state sync
        ├── UIUtil.luau                chunky rounded buttons/frames/tweens
        ├── ClientState.luau           holds authoritative server snapshot
        ├── ClientNet.luau             remote wrapper + failure toasts
        ├── Sounds.luau                SFX pool
        └── UI/
            ├── Effects.luau           toasts, +$/+Gem popups, hatch reveal, shake
            ├── TopBar.luau            Cash/Gem counters + zone label
            ├── HUD.luau               DIG button, egg inventory, incubator bar
            ├── Stands.luau            3 in-world stand panels (Shovel/Hatch/Luck)
            ├── Collection.luau        owned brainrots by tier + variant
            ├── Rebirth.luau           rebirth panel + confirmation
            └── SideNav.luau           toggle buttons for the modals
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
rojo build -o HatchABrainrot.rbxlx
```
Open `HatchABrainrot.rbxlx` in Studio and press **Play**.

### ⚙️ Enable saving
For DataStore persistence: **Game Settings → Security → Enable Studio Access to
API Services** (and the game must be saved to Roblox). Without it the game still
runs perfectly — it just won't persist between sessions (it logs a warning and
uses a temporary profile that is never written, so real saves are never
overwritten).

---

## 🎮 How to play
1. Stand on the brown **DIG** field in the center and press the big **⛏️ DIG**
   button (bottom). You find an egg of random rarity.
2. Click the egg in your **🥚 Eggs** tray (bottom-left) to start hatching it in
   the **🔮 Incubator** (bottom-right). Watch the live progress bar.
3. Press **COLLECT** when it's ready — a brainrot + variant is revealed and
   placed on a glowing podium at your base, where it generates passive Cash
   (and Gems if it's Rare/Legendary tier or a Gold/Diamond/Galaxy variant).
4. Walk up to the **upgrade stands** near the lobby spawn — each is run by a
   bacon-hair vendor, just press **E** (instant) to open it: 🪓 **Shovel** (Cash,
   faster digging), 🔥 **Hatch Speed** (Gems, faster incubation, capped at 85%),
   and 🍀 **Luck** (Gems, better eggs/variants). Buy more **Plots** at your base
   by clicking the **🔒 Buy Plot** podium on your next free slot.
5. Open **📦 Collection** to view everything you own by tier + variant, or sell.
6. Reach the Cash milestone, then hit **🔁 Rebirth** to reset, unlock the next
   **Zone** (rarer eggs, exclusive Mythic brainrots, higher payouts), and gain a
   permanent luck bonus.

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
Append an entry to `ZoneConfig.Zones` (egg odds, brainrot tiers, cash/gem scale,
`UnlockRebirths`) and bump `MaxZone`. Digging, economy, the rebirth unlock chain,
and the base tinting all read from it automatically.
# box
