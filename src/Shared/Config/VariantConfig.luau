--!strict
-- VariantConfig
-- Every brainrot can roll one of four variants. Variants are applied ON TOP of
-- the TIER-BASED income (see BrainrotConfig.TierIncome):
--   FinalCash/min = tierCash * Variant.CashMult * levelMult * rebirthCashMult
--   FinalGem/min  = (tierGem + Variant.GemBonus) * levelMult * rebirthGemMult
--
-- GemBonus is a flat PER-MINUTE gem amount the variant ADDS on top of the tier
-- base, so Gold/Diamond/Galaxy variants of ANY brainrot (even Commons) generate
-- gems. BrainrotMath divides the per-minute total by 60 for the 1s income loop.
--
-- Variant roll odds are WEIGHTS (not %). They get nudged by Luck (see DiggingManager).

export type Variant = "Normal" | "Gold" | "Diamond" | "Galaxy"

local VariantConfig = {}

VariantConfig.Order = { "Normal", "Gold", "Diamond", "Galaxy" } :: { string }

VariantConfig.Variants = {
	Normal = {
		CashMult = 1,
		GemBonus = 0,    -- gems/min added on top of tier base
		Weight   = 80,   -- 80%
		Glow     = false,
	},
	Gold = {
		CashMult = 3,
		GemBonus = 1,    -- gems/min added on top of tier base
		Weight   = 15,   -- 15%
		Glow     = true,
	},
	Diamond = {
		CashMult = 8,
		GemBonus = 3,    -- gems/min added on top of tier base
		Weight   = 4,    -- 4%
		Glow     = true,
	},
	Galaxy = {
		CashMult = 25,
		GemBonus = 8,    -- gems/min added on top of tier base
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
