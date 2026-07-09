local mod = get_mod("Lingua Imperialis")

local provider_options = {
	{ text = "provider_mymemory", value = "mymemory" },
	{ text = "provider_google", value = "google" },
	{ text = "provider_offline", value = "offline" }
}

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
				setting_id = "settings_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "enabled",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "provider",
						type = "dropdown",
						default_value = "mymemory",
						options = provider_options,
					},
					{
						setting_id = "download_model",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "download_model_large",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "target_language",
						type = "dropdown",
						default_value = "en",
						options = language_options,
					},
				},
			},
			{
				setting_id = "outgoing_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "outgoing_enabled",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "outgoing_language",
						type = "dropdown",
						default_value = "en",
						options = language_options,
					},
				},
			},
			{
				setting_id = "translation_colour",
				type = "group",
				sub_widgets = {
					{ setting_id = "translation_colour_R", type = "numeric", default_value = 106, range = { 0, 255 }, step_size = 1 },
					{ setting_id = "translation_colour_G", type = "numeric", default_value = 190, range = { 0, 255 }, step_size = 1 },
					{ setting_id = "translation_colour_B", type = "numeric", default_value = 48, range = { 0, 255 }, step_size = 1 },
				},
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
