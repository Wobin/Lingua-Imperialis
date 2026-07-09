return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Lingua Imperialis` encountered an error loading the Darktide Mod Framework.")

		new_mod("Lingua Imperialis", {
			mod_script       = "Lingua Imperialis/scripts/mods/Lingua Imperialis/Lingua Imperialis",
			mod_data         = "Lingua Imperialis/scripts/mods/Lingua Imperialis/Lingua Imperialis_data",
			mod_localization = "Lingua Imperialis/scripts/mods/Lingua Imperialis/Lingua Imperialis_localization",
		})
	end,
	load_after = {},
	require = {},
	version = "1.2.0",
	packages = {},
}
