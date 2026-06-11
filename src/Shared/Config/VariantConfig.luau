--!strict
-- VariantConfig
-- Every brainrot can roll one of four variants. Variants are applied ON TOP of
-- the TIER-BASED income (see BrainrotConfig.TierIncome):
--   FinalCash/sec = round( tierCashPerSec * Variant.CashMult * levelMult * rebirthCashMult )
--   FinalGem/min  = (tierGemPerMin + Variant.GemBonus) * levelMult * rebirthGemMult
--
-- CASH is sourced per-second and the final cash/sec is rounded to a whole integer in
-- BrainrotMath (NO /60 for cash). GemBonus is a flat PER-MINUTE gem amount the variant
-- ADDS on top of the tier base, so Gold/Diamond/Galaxy variants of ANY brainrot (even
-- Commons) generate gems; BrainrotMath divides ONLY the per-minute gem total by 60.
--
-- CashMults are tuned (Gold 2.2, Diamond 3.6) so Gold(N) < Normal(N+1) < Diamond(N)
-- at every adjacent tier pair. Galaxy (x6) stays PARKED/unobtainable.
--
-- Variant roll odds are WEIGHTS (not %). They get nudged by Luck (see DiggingManager).

export type Variant = "Normal" | "Gold" | "Diamond" | "Galaxy"

local VariantConfig = {}

VariantConfig.Order = { "Normal", "Gold", "Diamond", "Galaxy" } :: { string }

VariantConfig.Variants = {
	Normal = {
		CashMult = 1,
		GemBonus = 0,    -- FIXED gems/sec added on top of the tier base (no level/rebirth scaling)
		Weight   = 80,   -- 80%
		Glow     = false,
	},
	Gold = {
		CashMult = 2.2,
		GemBonus = 1,    -- FIXED gems/sec added on top of the tier base
		Weight   = 15,   -- 15%
		Glow     = true,
	},
	Diamond = {
		CashMult = 3.6,
		GemBonus = 2,    -- FIXED gems/sec added on top of the tier base
		Weight   = 4,    -- 4%
		Glow     = true,
	},
	Galaxy = {
		CashMult = 6,
		GemBonus = 4,    -- FIXED gems/sec added on top of the tier base
		Weight   = 1,    -- 1%
		Glow     = true,
		Rainbow  = true,
	},
}

-- How strongly Luck pushes the roll toward rarer variants.
-- Each variant's weight is multiplied by (1 + luck * LuckBias).
VariantConfig.LuckBias = {
	Normal  = 0,
	Gold    = 1.0,
	Diamond = 2.0,
	Galaxy  = 3.0,
}

function VariantConfig.get(variant: string)
	return VariantConfig.Variants[variant]
end

return VariantConfig
