local mod = get_mod("Lingua Imperialis")

local language_options = {
	{ text = "lang_en", value = "en" },
	{ text = "lang_de", value = "de" },
	{ text = "lang_fr", value = "fr" },
	{ text = "lang_es", value = "es" },
	{ text = "lang_pt", value = "pt" },
	{ text = "lang_it", value = "it" },
	{ text = "lang_ru", value = "ru" },
	{ text = "lang_pl", value = "pl" },
	{ text = "lang_nl", value = "nl" },
	{ text = "lang_sv", value = "sv" },
	{ text = "lang_tr", value = "tr" },
	{ text = "lang_uk", value = "uk" },
	{ text = "lang_zh", value = "zh" },
	{ text = "lang_ja", value = "ja" },
	{ text = "lang_ko", value = "ko" },
	{ text = "lang_ar", value = "ar" },
}

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,

	options = {
		widgets = {
			{
				setting_id = "enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "target_language",
				type = "dropdown",
				default_value = "en",
				options = language_options,
			},
			{
				setting_id = "channels_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "channel_hub",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "channel_mission",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "channel_party",
						type = "checkbox",
						default_value = true,
					},
				},
			},
		},
	},
}
