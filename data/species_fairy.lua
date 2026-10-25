-- Gen 9 types for the 18 Gen 3 species that gained Fairy.
-- Keys are gen1recomp species ids (the constants without the SPECIES_ prefix).
-- The other 368 Gen 3 species keep their Gen 3 types.
return {
  CLEFFA = { "FAIRY" },
  CLEFAIRY = { "FAIRY" },
  CLEFABLE = { "FAIRY" },

  IGGLYBUFF = { "NORMAL", "FAIRY" },
  JIGGLYPUFF = { "NORMAL", "FAIRY" },
  WIGGLYTUFF = { "NORMAL", "FAIRY" },

  TOGEPI = { "FAIRY" },
  TOGETIC = { "FAIRY", "FLYING" },

  AZURILL = { "NORMAL", "FAIRY" },
  MARILL = { "WATER", "FAIRY" },
  AZUMARILL = { "WATER", "FAIRY" },

  SNUBBULL = { "FAIRY" },
  GRANBULL = { "FAIRY" },

  RALTS = { "PSYCHIC_TYPE", "FAIRY" },
  KIRLIA = { "PSYCHIC_TYPE", "FAIRY" },
  GARDEVOIR = { "PSYCHIC_TYPE", "FAIRY" },

  MAWILE = { "STEEL", "FAIRY" },
  MR_MIME = { "PSYCHIC_TYPE", "FAIRY" },
}
