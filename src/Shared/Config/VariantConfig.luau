--!strict
-- VariantConfig
-- Every brainrot can roll one of four variants. Variants are applied ON TOP of
-- a base brainrot's stats:
--   FinalCash = BaseCash * Variant.CashMult * Zone.CashScale
--   FinalGem  = (BaseGem + Variant.GemBonus) * Zone.GemScale
--
-- GemBonus is a flat per-cycle gem amount the variant adds, so Gold/Diamond/
-- Galaxy variants of ANY brainrot (even Commons) generate gems.
--
-- Variant roll odds are WEIGHTS (not %). They get nudged by Luck (see DiggingManager).

export type Variant = "Normal" | "Gold" | "Diamond" | "Galaxy"

local VariantConfig = {}

VariantConfig.Order = { "Normal", "Gold", "Diamond", "Galaxy" } :: { string }

VariantConfig.Variants = {
	Normal = {
		CashMult = 1,
		GemBonus = 0,
		Weight   = 80,   -- 80%
		Glow     = false,
	},
	Gold = {
		CashMult = 3,
		GemBonus = 0.02,
		Weight   = 15,   -- 15%
		Glow     = true,
	},
	Diamond = {
		CashMult = 8,
		GemBonus = 0.10,
		Weight   = 4,    -- 4%
		Glow     = true,
	},
	Galaxy = {
		CashMult = 25,
		GemBonus = 0.50,
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
