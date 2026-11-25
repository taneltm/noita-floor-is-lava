dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "floor_is_lava"
mod_settings_version = 1
mod_settings = {
    {
        id = "hardcore",
        ui_name = "Hardcore",
        ui_description = "Instead of a patch of lava under you, every pixel of the\nmaterial you stood on turns into lava, everywhere.\nHoly Mountain brickwork still only gets a patch.\nApplies to new runs.",
        value_default = false,
        scope = MOD_SETTING_SCOPE_NEW_GAME,
    },
    {
        id = "debug",
        ui_name = "Debug info",
        ui_description = "Show the grace countdown, ground timer, cooldown and\nthe last material read.",
        value_default = false,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
