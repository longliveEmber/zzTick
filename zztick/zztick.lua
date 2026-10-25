--[[
* Zztick - Ashita v4 addon
*
* Shows a countdown to the next /heal recovery tick and your projected HP/MP
* after that tick. Only visible while resting; hides as soon as you stand.
*
* Released under the GNU GPL v3 or later (see LICENSE), to match
* Ashita's addon license.
--]]

addon.name    = 'zztick';
addon.author  = 'Banedon';
addon.version = '1.1.4';
addon.desc    = 'Countdown to the next resting (/heal) tick with projected HP/MP.';
addon.link    = 'https://ashitaxi.com/';

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');
local model    = require('zzmodel');
local zzfonts  = require('zzfonts');
local style    = require('zzstyle');
local FX       = require('zzfx');

-- Tick numbers: a night's rest reaches thousands (the count coasts on the clock once HP/MP are full), so the
-- tick text is reserved for 4 digits and anything above 9999 shows as "9999+".
style.WORST.tick   = 'Tick 9999+';
style.WORST.c_tick = '  (#9999+)';
local function tick_txt(n) return (n > 9999) and '9999+' or tostring(n); end

local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min;
local sformat = string.format;

--[[
* Default settings (saved per character by the settings library).
--]]
local default_settings = T{
    -- window
    x            = 200,
    y            = 200,
    locked       = false,
    scale        = 1.0,
    bg_alpha     = 0.75,
    show_title   = false,
    compact      = false,
    bar_height   = 8,
    width        = 0,        -- fixed window width in pixels; 0 = auto (widest possible content)
    -- look
    theme        = style.DEFAULT_THEME, -- "Vana'diel Gold", 'Crystal Blue', 'Midnight' or 'Classic'
    animate      = true,     -- smooth bar, last-second glow, +gain pop
    fade_ms      = 150,      -- fade in when you sit / out when you stand (0 = instant)
    rounding     = 8,        -- window corner radius (themes only)
    show_minibars = true,    -- HP/MP mini bars with the projected gain as a ghost segment
    -- fonts (bundled Google Fonts; fall back to Ashita's font if they can't load)
    font_name    = 'Barlow Semi Condensed', -- body / labels
    title_font   = 'Cinzel',                -- header title
    num_font     = 'JetBrains Mono',        -- numbers (tabular digits)
    font_size    = 16,       -- 0 = Ashita's default size
    font_bold    = false,
    font_outline = false,
    -- lines
    show_timer   = true,
    show_bar     = true,
    show_hp      = true,
    show_mp      = true,
    show_gain    = true,
    show_tick_no = true,
    show_full    = true,
    show_last    = false,
    show_sync    = true,     -- "Synced Lv NN" badge when Level Sync / Level Restriction caps you
    -- v1.4.0 look & sound
    show_icons   = true,     -- heart / droplet icons left of the HP / MP labels (themes)
    full_effect  = 'border', -- when HP/MP reaches full: 'border' (comet lap) | 'sparkle' | 'both' | 'off' (needs animate)
    tick_border  = true,     -- border comet on every tick roll-over (separate from the full effect; needs animate)
    chime_enabled = true,    -- soft chime when fully healed (on by default since 1.4.1)
    chime_choice = false,    -- true once you turned the chime on/off yourself (then it is never changed for you)
    chime_backend = 'auto',  -- 'auto' (Ashita, then winmm) | 'ashita' | 'winmm'
    chime_mode   = 'both',   -- 'both' | 'any' | 'hp' | 'mp'
    chime_sound  = 'chime_soft.wav', -- a .wav in addons/zztick/sounds/
    chime_volume = 100,      -- 0-200 %: 100 = the file as it is, 0 = silent, above 100 = louder (clipped)
    chime_sit_full = false,  -- also chime when sitting down already full
    sub_ratio    = 1,        -- server SUBJOB_RATIO (LSB default 1 = half the main level)
    -- v1.5.0 effects (zzfx.lua) and the food line
    fx_level     = 'full',   -- 'off' | 'subtle' | 'full' (needs Animations)
    fx_strength  = 0.8,      -- 0.1-1.0 brightness of the effects
    fx_bar_shine = true,     -- a band of light glides across the bar now and then (full)
    fx_shine_period = 5.0,   -- seconds between shines
    fx_bar_spark = true,     -- star glint at the leading edge of the bar (full)
    fx_spark_size = 0.55,    -- spark size, 0.10-1.00
    fx_spark_strength = 0.35, -- spark strength, 0.10-1.00
    fx_charge    = true,     -- the bar warms and glows over the last 3 seconds
    fx_glint     = true,     -- diagonal glint across the HP/MP row that gained on a tick
    fx_pop       = true,     -- heart / droplet pop on a tick (full)
    fx_roll      = true,     -- the current HP/MP number counts up to its new value
    fx_sleep     = true,     -- breathing moon and floating z's in the header (full)
    fx_rested    = true,     -- "Fully rested" line, window glint and stars when HP and MP are full
    row_pad      = 0,        -- extra vertical padding between lines, 0-5 px (scaled)
    show_food    = true,     -- a line with the food you ate (and its healing bonus) while the Food effect lasts
    food_id      = 0,        -- 1.1.4: the food last eaten, kept while its Food effect lasts so it survives logoff / logon
    food_hp      = 0,
    food_mp      = 0,
    food_name    = '',
    food_chat    = false,    -- 1.1.3: chat lines when you eat (food and its bonus / food not recognized); off = only the window line
    -- colors {r,g,b,a}
    col_text     = T{ 1.00, 1.00, 1.00, 1.00 },
    col_timer    = T{ 1.00, 0.92, 0.55, 1.00 },
    col_hp       = T{ 0.55, 1.00, 0.55, 1.00 },
    col_mp       = T{ 0.55, 0.78, 1.00, 1.00 },
    col_bar      = T{ 0.95, 0.75, 0.20, 1.00 },
    col_bar_bg   = T{ 0.15, 0.15, 0.15, 0.90 },
    col_outline  = T{ 0.00, 0.00, 0.00, 1.00 },
    -- model
    bonus_hp     = 0,        -- extra HP per tick (food, gear the scan misses)
    bonus_mp     = 0,        -- extra MP per tick
    auto_gear    = true,     -- read "HP/MP recovered while healing +N" off equipped gear
    auto_food    = true,     -- also count the healing bonus of the food you eat (seen when you eat it)
    signet_mode  = 0,        -- 0 = auto (Signet/Sanction/Sigil buff), 1 = always, 2 = never
    profile      = 'lsb',    -- 'lsb' (LandSandBoat private servers, default since 1.4.3) or 'retail' (BG-Wiki)
    profile_choice = false,  -- true once you picked a profile yourself
    blu_cm_tier  = 0,        -- Clear Mind tier from BLU spells (0-6)
};

-- How often the (allocating) scans may run, in seconds.
local GEAR_CHECK_EVERY = 1.0;
local BUFF_CHECK_EVERY = 0.5;
local JOB_CHECK_EVERY  = 1.0;
local SAVE_DEBOUNCE    = 1.5;
local REST_GAP         = 1.0;   -- not resting for longer than this ends the rest (chime latch)
local SWEEP_DUR        = 0.15;  -- tick reset sweep (bar flash) length in seconds

local BLOCKED_IDS = { model.BUFF.DISEASE, model.BUFF.PLAGUE, model.BUFF.CURSE_II };
local WARN_COLOR  = { 1.0, 0.4, 0.4, 1.0 };

local rt = {
    settings    = settings.load(default_settings),
    tracker     = nil,
    config_open = { false },
    main_open   = { true },
    test_mode   = false,
    debug       = false,
    apply_pos   = true,
    dragging    = false,     -- 1.1.2: a drag that started on this window is in progress
    pos_vec     = { 0, 0 },
    bar_size    = { 200, 8 },
    dirty       = false,
    dirty_at    = 0,
    test_start  = 0,

    -- cached game data (refreshed on throttles / packets, never per frame)
    ctx  = { level = 1, maxhp = 0, maxmp = 0, hp_bonus = 0, mp_bonus = 0, signet = false,
             profile = 'retail', cm_tier = 0, blocked = false },
    st   = { hp = 0, mp = 0, maxhp = 0, maxmp = 0, main = 0, mainlv = 0, sub = 0, sublv = 0, status = nil },
    gear = { hp = 0, mp = 0, ids = {}, next_check = 0, force = true },
    food = { id = 0, hp = 0, mp = 0, name = '', set_at = -1e9 },   -- last food eaten (while the Food buff lasts)
    item_bonus = {},  -- item id -> { hp, mp } parsed once
    buffs = { signet = false, blocked = false, sync = false, restrict = false, sj_off = false, next_check = 0, force = true,
              raw = {}, raw_n = 0, ids = {}, ids_n = 0, list_kind = 'none', list_base = 1, last_scan = nil },
    jobs  = { next_check = 0 },
    lv_in = { main = 0, sub = 0, real_main = 0, real_sub = 0, cur_main = 0, cur_sub = 0, party_main = 0,
              sync = false, restrict = false, sj_off = false, ratio = 1 },
    lv    = { main = 0, sub = 0, real_main = 0, real_sub = 0, capped = false, reason = nil, source = '' },
    lv_cache = {},   -- job id -> last real level seen while not synced
    font_base = { size = 13, next_check = 0 },

    -- fonts
    font_list   = nil,
    font_obj    = nil,   -- body ImFont in use (nil = Ashita default)
    font_title  = nil,   -- title ImFont (nil = body font)
    font_num    = nil,   -- digits ImFont (nil = body font)
    font_status = '',
    font_want   = true,  -- (re)apply the font choice at the next frame start

    -- fixed layout (recomputed only when fonts/scale/toggles/theme change)
    L      = {},
    lkey   = {},
    lvalid = false,
    wgen   = 0,          -- bumps when fonts change -> cached text widths re-measured
    style_pad = 8,

    -- animation state
    fx = { alpha = 0, last_now = nil, disp = nil, last_n = nil, ghp = 0, gmp = 0,
           pop_at = -100, pop_hp = '', pop_mp = '', pop_whp = -1, pop_wmp = -1,
           test_r = nil, zoning = false, wait_a = 1, sweep_at = -1e9, rested_at = -1e9,
           -- full sparkle (preallocated particle pools) and the last full state per stat
           spark_hp = model.new_spark(7), spark_mp = model.new_spark(7), was_fhp = nil, was_fmp = nil,
           -- border flash: start time per stat (HP streak clockwise, MP counter-clockwise)
           flash_t = { -1e9, -1e9 } },
    perim = { w = -1, h = -1, r_in = -1, len = 0 },   -- window perimeter geometry (recomputed on size change)
    chime  = model.new_chime(),
    rest_sess  = { id = 0, last = -1e9 },   -- debounced rest session (chime: once per rest)
    chime_view = { fh = false, fm = false, has_mp = false, cond = false },
    sounds = nil,              -- cached list of .wav files in sounds/ (scanned on demand)
    snap = { valid = false, st = nil, ctx = nil, rem = 0, prog = 0, n = 1, eh = 0, em = 0 },

    -- counters (debug readout + tests)
    stats = { f_arrows = 0, f_icons = 0, f_sparkle = 0, f_flash = 0, flash_sets = 0, gear_scans = 0, item_parses = 0, buff_scans = 0, saves = 0, frames = 0,
              acc_ms = 0, max_ms = 0, win_frames = 0, win_start = 0, avg_ms = 0, peak_ms = 0 },

    -- string caches: only re-format when the shown numbers change
    sc = {
        timer = { k1 = -1, k2 = -1, k3 = nil, s = '' },
        hp    = { k1 = -1, k2 = -1, k3 = -1, k4 = nil, s = '' },
        mp    = { k1 = -1, k2 = -1, k3 = -1, k4 = nil, s = '' },
        full  = { k1 = -2, k2 = -1, s = '' },
        last  = { k1 = -1, k2 = -1, k3 = -1, k4 = -1, s = '' },
        dbg   = { k1 = -1, k2 = -1, k3 = -1, k4 = -1, k5 = -1, s = '' },
    },
    col_u32 = nil,  -- outline color, packed once per settings change

    -- observed-tick resync + timer hold / bar fade
    tick_hold = {
        holding = false,
        hold_start = 0,
        last_hp = 0,
        last_mp = 0,
        fade_window = 0.25,
    },
};

rt.tracker = model.new_tracker();   -- timing comes from the server's tick reports, not from settings
rt.bar      = model.new_glide();  -- displayed fill: constant speed, gentle corrections (v1.3.1)
rt.test_bar = model.new_glide();
-- Wall clock (os.clock is CPU time by the C standard; see zzmodel.make_clock).
rt.clock, rt.clock_name = model.make_clock(rawget(_G, 'ashita') and ashita.time, imgui, os.clock);
-- preview "tracker": ticks every 10 s from test_start
rt.test_tr = { next_n = 3, next_time = 0, rest_start = nil, interval_for = function () return 10; end };
rt.view = { mhp = 0, mmp = 0, fhp = false, fmp = false };   -- per-stat max/full for the frame
if (rawget(_G, 'ZZTICK_TEST')) then _G.ZZTICK_RT = rt; end

local function msg(text) print(chat.header(addon.name):append(chat.message(text))); end
local function err(text) print(chat.header(addon.name):append(chat.error(text))); end

--[[
* Saving: only after a user change, debounced, and never mid-drag.
--]]
local function mark_dirty(now)
    rt.dirty = true;
    rt.dirty_at = now or rt.now or 0;
    rt.col_u32 = nil;
end

local function save_now()
    settings.save();
    rt.stats.saves = rt.stats.saves + 1;
    rt.dirty = false;
end

local function rebuild_tracker()
    rt.tracker = model.new_tracker();
end

local function invalidate_caches()
    rt.gear.force  = true;
    rt.buffs.force = true;
    rt.jobs.next_check = 0;
    rt.font_want   = true;
    rt.apply_pos   = true;
    rt.col_u32     = nil;
    rt.lvalid      = false;
end

--[[
* Settings validation (v1.4.6). The settings file is plain Lua and can be edited by hand, so every
* value is checked on load and on character switch:
*   - numbers saved as text ("1.35") are read as numbers, booleans as text ("true") as booleans;
*   - numbers outside their range are clamped (same ranges as the config window);
*   - a value of the wrong type (or an unknown theme / option) goes back to its default;
*   - keys Zztick does not use (old versions, typos) are removed.
* One chat line names every key that was changed, so a bad hand edit is easy to spot.
--]]
-- key = { min, max, integer }
local RANGES = {
    x = { -20000, 20000, true }, y = { -20000, 20000, true },
    scale = { 0.5, 3.0 }, bg_alpha = { 0.0, 1.0 }, bar_height = { 2, 30 }, width = { 0, 2000, true },
    fade_ms = { 0, 1000, true }, rounding = { 0, 16 }, font_size = { 0, 72, true },
    sub_ratio = { 0, 3, true }, bonus_hp = { -100, 500, true }, bonus_mp = { -100, 500, true },
    signet_mode = { 0, 2, true }, blu_cm_tier = { 0, 6, true }, chime_volume = { 0, 200, true },
    fx_strength = { 0.1, 1.0 }, fx_shine_period = { 2.0, 60.0 }, fx_spark_size = { 0.1, 1.0 }, fx_spark_strength = { 0.1, 1.0 }, row_pad = { 0, 5, true },
};
local ENUMS = {
    full_effect = { border = true, sparkle = true, both = true, off = true },
    fx_level = { off = true, subtle = true, full = true },
    chime_backend = { auto = true, ashita = true, winmm = true },
    chime_mode = { both = true, any = true, hp = true, mp = true },
    profile = { lsb = true, retail = true },
};
-- keys older versions wrote that are no longer used (removed quietly, listed separately)
local RETIRED = { first_run = true, sparkle = true, first_delay = true, interval = true, arrow_drawn = true, fx_z_period = true };

local function copy_default(d)
    if (type(d) ~= 'table') then return d; end
    local r = {};
    for i = 1, #d do r[i] = d[i]; end
    return (rawget(_G, 'T') and T(r)) or r;
end

local function show(v)
    if (type(v) == 'string') then return '"' .. v .. '"'; end
    if (type(v) == 'table') then return 'a table'; end
    return tostring(v);
end

-- Validates s in place. Returns a list of problems ("key: what"), a list of retired keys removed.
local function validate_settings(s)
    local bad, old = {}, {};
    if (type(s) ~= 'table') then return bad, old; end
    local keys = {};
    for k in pairs(s) do keys[#keys + 1] = k; end
    table.sort(keys, function (a, b) return tostring(a) < tostring(b); end);
    for _, k in ipairs(keys) do
        if (default_settings[k] == nil) then
            if (RETIRED[k]) then old[#old + 1] = tostring(k); else bad[#bad + 1] = tostring(k) .. ': unknown key removed'; end
            s[k] = nil;
        end
    end
    -- known keys, in a stable order
    keys = {};
    for k in pairs(default_settings) do keys[#keys + 1] = k; end
    table.sort(keys);
    for _, k in ipairs(keys) do
        local d, v = default_settings[k], s[k];
        local td = type(d);
        if (v == nil) then
            s[k] = copy_default(d);
            bad[#bad + 1] = k .. ': missing, set to ' .. show(d);
        elseif (td == 'number') then
            local n = v;
            if (type(v) == 'string') then n = tonumber(v); end
            if (type(n) ~= 'number' or n ~= n or n == math.huge or n == -math.huge) then
                s[k] = d; bad[#bad + 1] = k .. ': ' .. show(v) .. ' is not a number, reset to ' .. show(d);
            else
                local r = RANGES[k];
                local m = n;
                if (r ~= nil) then
                    if (r[3]) then m = floor(m + 0.5); end
                    if (m < r[1]) then m = r[1]; elseif (m > r[2]) then m = r[2]; end
                end
                s[k] = m;
                if (type(v) ~= 'number') then bad[#bad + 1] = k .. ': text ' .. show(v) .. ' read as ' .. show(m);
                elseif (m ~= n) then bad[#bad + 1] = k .. ': ' .. show(n) .. ' out of range, set to ' .. show(m); end
            end
        elseif (td == 'boolean') then
            if (type(v) ~= 'boolean') then
                local l = type(v) == 'string' and v:lower() or nil;
                if (l == 'true' or v == 1) then s[k] = true; bad[#bad + 1] = k .. ': ' .. show(v) .. ' read as true';
                elseif (l == 'false' or v == 0) then s[k] = false; bad[#bad + 1] = k .. ': ' .. show(v) .. ' read as false';
                else s[k] = d; bad[#bad + 1] = k .. ': ' .. show(v) .. ' is not true/false, reset to ' .. show(d); end
            end
        elseif (td == 'string') then
            if (type(v) ~= 'string') then
                s[k] = d; bad[#bad + 1] = k .. ': ' .. show(v) .. ' is not text, reset to ' .. show(d);
            elseif (ENUMS[k] ~= nil and not ENUMS[k][v]) then
                local l = v:lower();
                if (ENUMS[k][l]) then s[k] = l;
                else s[k] = d; bad[#bad + 1] = k .. ': ' .. show(v) .. ' is not a valid choice, reset to ' .. show(d); end
            elseif (k == 'theme') then
                local t = style.find_theme(v);
                if (t == nil) then s[k] = d; bad[#bad + 1] = k .. ': unknown theme ' .. show(v) .. ', reset to ' .. show(d);
                elseif (t.name ~= v) then s[k] = t.name; end
            end
        elseif (td == 'table') then
            -- colors {r, g, b, a} in 0..1
            local ok = type(v) == 'table';
            if (ok) then
                for i = 1, 4 do
                    local c = tonumber(v[i]);
                    if (c == nil or c ~= c) then ok = false; break; end
                    c = min(1, max(0, c));
                    if (c ~= v[i]) then v[i] = c; end
                end
            end
            if (not ok) then s[k] = copy_default(d); bad[#bad + 1] = k .. ': not a color {r,g,b,a}, reset to default'; end
        end
    end
    return bad, old;
end
rt._validate_settings = validate_settings;   -- for the offline tests

-- Validates the loaded settings, says what changed (one line), and saves the fixed file.
local function check_settings(save)
    local s = rt.settings;
    local bad, old = validate_settings(s);
    rt.settings_problems = bad;
    if (#bad > 0) then
        print(chat.header(addon.name):append(chat.error('Fixed invalid settings (hand edit?): ' .. table.concat(bad, '; ') .. '.')));
    end
    if (#old > 0) then
        print(chat.header(addon.name):append(chat.message('Removed settings no longer used: ' .. table.concat(old, ', ') .. '.')));
    end
    if (save and (#bad > 0 or #old > 0)) then settings.save(); end
    return #bad + #old;
end

local function reset_settings()
    settings.reset();
end

-- 1.4.1: the chime shipped off in 1.4.0 and that file value got saved; turn it on once for anyone
-- who never chose. An explicit choice (checkbox / command) sets chime_choice and is kept.
local function apply_chime_default()
    local s = rt.settings;
    if (s == nil or s.chime_choice == true or s.chime_enabled == true) then return false; end
    s.chime_enabled = true;
    if (not rt.chime_notice) then
        rt.chime_notice = true;
        print(chat.header(addon.name):append(chat.message('Full-heal chime is on now (/zztick chime off to turn it off).')));
    end
    return true;
end
rt._apply_chime_default = apply_chime_default;

-- 1.4.3: 'retail' was the default and got saved into every settings file. Zztick is used on
-- LandSandBoat servers (Phoenix), where the retail Signet level term is 3 HP low at levels 10/20/.../70.
-- Switch to 'lsb' once for anyone who never picked a profile; an explicit choice is kept.
local function apply_profile_default()
    local s = rt.settings;
    if (s == nil or s.profile_choice == true) then return false; end
    if (s.profile ~= 'lsb' and s.profile ~= 'retail') then s.profile = 'lsb'; return true; end
    if (s.profile == 'lsb') then return false; end
    s.profile = 'lsb';
    if (not rt.profile_notice) then
        rt.profile_notice = true;
        print(chat.header(addon.name):append(chat.message('Formula profile is now lsb (LandSandBoat). On a retail server: /zztick profile retail')));
    end
    return true;
end
rt._apply_profile_default = apply_profile_default;

settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then rt.settings = s; end
    rt.food.id, rt.food.hp, rt.food.mp, rt.food.name = 0, 0, 0, '';   -- 1.1.4: another character's food is not ours
    check_settings(false);      -- character switch / reset: fix hand-edited values (saved just below)
    apply_chime_default();
    apply_profile_default();
    invalidate_caches();
    rebuild_tracker();
    save_now();
end);
local _n = check_settings(false);
local _c, _p = apply_chime_default(), apply_profile_default();
if (_n > 0 or _c or _p) then settings.save(); end

--[[
* Throttled game-data refreshes. At most one of the expensive ones per frame.
--]]
local function refresh_gear(now)
    local g = rt.gear;
    g.next_check = now + GEAR_CHECK_EVERY;
    g.force = false;
    rt.stats.gear_scans = rt.stats.gear_scans + 1;

    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local changed = false;
    for slot = 0, 15 do
        local id = 0;
        local e = inv:GetEquippedItem(slot);
        if (e ~= nil and e.Index ~= nil and e.Index ~= 0) then
            local item = inv:GetContainerItem(bit.band(e.Index, 0xFF00) / 0x0100, e.Index % 0x0100);
            if (item ~= nil and item.Id ~= nil and item.Id ~= 65535) then id = item.Id; end
        end
        if (g.ids[slot] ~= id) then g.ids[slot] = id; changed = true; end
    end
    if (not changed) then return; end

    -- Equipment changed: re-total, parsing each item description at most once ever.
    local res = AshitaCore:GetResourceManager();
    local hp, mp = 0, 0;
    for slot = 0, 15 do
        local id = g.ids[slot];
        if (id ~= 0) then
            local b = rt.item_bonus[id];
            if (b == nil) then
                local h, m = 0, 0;
                local r = res:GetItemById(id);
                if (r ~= nil and r.Description ~= nil) then h, m = model.parse_heal_bonus(r.Description[1]); end
                b = { h, m };
                rt.item_bonus[id] = b;
                rt.stats.item_parses = rt.stats.item_parses + 1;
            end
            hp = hp + b[1];
            mp = mp + b[2];
        end
    end
    g.hp, g.mp = hp, mp;
end

-- Buff list reader. Ashita returns the 32 player buff slots (int16, empty = -1 or 255), but the Lua
-- value is not guaranteed to be a plain table: depending on the build it is a table (1- or 0-based),
-- a sol2 container userdata (1-based) or an FFI int16_t[32] (0-based). 1.4.3 only accepted
-- type(list) == 'table', so any other kind silently produced an empty buff list (no Signet).
local function buff_at(list, i) return list[i]; end
local function norm_buff(v)
    v = tonumber(v);
    if (v == nil) then return nil; end
    v = floor(v);
    if (v >= 32768) then v = v - 65536; end       -- int16 read as uint16 (0xFFFF = -1)
    if (v <= 0 or v == 255) then return nil; end   -- empty slot (-1 / 255) or 0
    return v;
end
local function add_buff(b, v)
    local n = b.raw_n + 1;
    b.raw_n = n; b.raw[n] = v;                     -- raw value as read (debug line)
    local id = norm_buff(v);
    if (id ~= nil) then local k = b.ids_n + 1; b.ids_n = k; b.ids[k] = id; end
end
local function scan_buff_list(b, list)
    b.raw_n, b.ids_n = 0, 0;
    local t = type(list);
    b.list_kind = t;
    if (t == 'table') then
        local lo = (list[0] ~= nil) and 0 or 1;
        b.list_base = lo;
        for i = lo, lo + 31 do add_buff(b, list[i]); end
        -- anything outside the expected 32 slots (odd layouts): still look at it
        for k, v in pairs(list) do
            if (type(k) ~= 'number' or k < lo or k > lo + 31) then add_buff(b, v); end
        end
    elseif (t == 'cdata') then
        b.list_base = 0;
        for i = 0, 31 do add_buff(b, list[i]); end
    elseif (t == 'userdata') then
        b.list_base = 1;
        for i = 1, 32 do
            local ok, v = pcall(buff_at, list, i);
            if (not ok) then break; end
            add_buff(b, v);
        end
        local ok, v = pcall(buff_at, list, 0);     -- 0-based containers
        if (ok and v ~= nil) then b.list_base = 0; add_buff(b, v); end
    end
end

local function refresh_buffs(now)
    local b = rt.buffs;
    b.next_check = now + BUFF_CHECK_EVERY;
    b.force = false;
    b.last_scan = now;
    rt.stats.buff_scans = rt.stats.buff_scans + 1;
    local list = AshitaCore:GetMemoryManager():GetPlayer():GetBuffs();
    scan_buff_list(b, list);
    local blocked, sync, restrict, sj_off = false, false, false, false;
    local has_sig, has_sanc, has_sigil = false, false, false;
    local has_food = false;
    local B = model.BUFF;
    for j = 1, b.ids_n do
        local id = b.ids[j];
        if (id == B.FOOD) then has_food = true; end
        if (id == B.SIGNET) then has_sig = true; elseif (id == B.SANCTION) then has_sanc = true; elseif (id == B.SIGIL) then has_sigil = true; end
        for i = 1, #BLOCKED_IDS do if (id == BLOCKED_IDS[i]) then blocked = true; end end
        if (id == B.LEVEL_SYNC) then sync = true;
        elseif (id == B.LEVEL_RESTRICTION) then restrict = true;
        elseif (id == B.SJ_RESTRICTION or id == B.OBLIVISCENCE) then sj_off = true; end
    end
    -- sync/restriction started or ended: re-read levels now (cheap; only on change)
    if (sync ~= b.sync or restrict ~= b.restrict or sj_off ~= b.sj_off) then rt.jobs.next_check = 0; end
    b.signet, b.blocked, b.sync, b.restrict, b.sj_off = (has_sig or has_sanc or has_sigil), blocked, sync, restrict, sj_off;
    b.has_signet, b.has_sanction, b.has_sigil = has_sig, has_sanc, has_sigil;
    b.has_food = has_food;
    -- the Food effect ended (or was never there): its healing bonus ends too (grace period for the buff packet)
    local f = rt.food;
    local pend = rt.food_pending;
    if (has_food and pend ~= nil) then
        -- the Food effect appeared after an item was used: that item is your food
        f.id, f.hp, f.mp, f.name, f.set_at = pend.id, pend.hp, pend.mp, pend.name, rt.clock();
        rt.food_pending = nil;
        local s = rt.settings;
        s.food_id, s.food_hp, s.food_mp, s.food_name = f.id, f.hp, f.mp, f.name;
        save_now();
        if (rt.settings.food_chat) then msg(sformat('Food: %s counts +%d HP / +%d MP per heal tick while the Food effect lasts.', pend.name, pend.hp, pend.mp)); end
    elseif (pend ~= nil and rt.clock() - pend.at > 20) then
        rt.food_pending = nil;                      -- it was not food (no Food effect followed)
    end
    if (not has_food and f.id ~= 0 and b.list_kind ~= 'none' and rt.clock() - f.set_at > 6) then
        f.id, f.hp, f.mp, f.name = 0, 0, 0, '';
    end
    -- 1.1.4: the saved food is forgotten only once the Food effect has been gone for 15 s in a row (a buff list
    -- that is briefly empty after zoning or logging on must not erase it)
    local s = rt.settings;
    if (has_food or b.list_kind == 'none') then rt.food_gone_at = nil;
    elseif (rt.food_gone_at == nil) then rt.food_gone_at = rt.clock();
    elseif ((s.food_id or 0) ~= 0 and rt.clock() - rt.food_gone_at > 15) then
        s.food_id, s.food_hp, s.food_mp, s.food_name = 0, 0, 0, '';
        save_now();
    end
    -- logged back on (or reloaded) with the Food effect still up: the food saved when it was eaten
    if (has_food and f.id == 0 and pend == nil and (s.food_id or 0) > 0) then
        f.id, f.hp, f.mp, f.name, f.set_at = s.food_id, s.food_hp or 0, s.food_mp or 0, s.food_name or '', rt.clock();
    end
    if (has_food and f.id == 0 and not rt.food_warned) then
        rt.food_warned = true;
        if (rt.settings.food_chat) then msg('A Food effect is active but the food is unknown (eaten before the addon loaded, or not detected). Use /zztick bonus hp|mp <n>, or /zztick food debug and eat again.'); end
    end
    if (not has_food) then rt.food_warned = false; end
end
rt._scan_buff_list = scan_buff_list;

local function num(v) return (type(v) == 'number') and v or 0; end

local function refresh_jobs(now, player)
    local st, i, b = rt.st, rt.lv_in, rt.buffs;
    rt.jobs.next_check = now + JOB_CHECK_EVERY;
    rt.stats.job_scans = (rt.stats.job_scans or 0) + 1;
    st.main   = player:GetMainJob();
    st.sub    = player:GetSubJob();
    i.main, i.sub = num(st.main), num(st.sub);
    i.cur_main, i.cur_sub = num(player:GetMainJobLevel()), num(player:GetSubJobLevel());
    -- real (unsynced) levels from the job level table (0x01B); 0 when unavailable
    local okm, rm = pcall(player.GetJobLevel, player, i.main);
    local oks, rs = pcall(player.GetJobLevel, player, i.sub);
    i.real_main = okm and num(rm) or 0;
    i.real_sub  = (i.sub > 0 and oks) and num(rs) or 0;
    local okp, pm = pcall(function () return AshitaCore:GetMemoryManager():GetParty():GetMemberMainJobLevel(0); end);
    i.party_main = okp and num(pm) or 0;
    i.sync, i.restrict, i.sj_off = b.sync, b.restrict, b.sj_off;
    -- remember unsynced levels per job, in case the client's job table also shows the synced value
    local cache = rt.lv_cache;
    if (not (i.sync or i.restrict)) then
        if (i.main > 0 and i.real_main > 0) then cache[i.main] = i.real_main; end
        if (i.sub > 0 and i.real_sub > 0) then cache[i.sub] = i.real_sub; end
    else
        i.real_main = max(i.real_main, cache[i.main] or 0);
        if (i.sub > 0) then i.real_sub = max(i.real_sub, cache[i.sub] or 0); end
    end
    i.ratio = rt.settings.sub_ratio or 1;
    local lv = model.effective_levels(i, rt.lv);
    st.mainlv, st.sublv = lv.main, lv.sub;
end

-- Cheap per-frame reads + throttled refreshes. Writes into rt.st / rt.ctx (no allocations).
local function read_state()
    local now    = rt.now;
    local mm     = AshitaCore:GetMemoryManager();
    local player = mm:GetPlayer();
    if (player == nil) then return false; end
    local z = player:GetIsZoning();
    if (z == true or (type(z) == 'number' and z ~= 0)) then rt.fx.zoning = true; return false; end

    local party = mm:GetParty();
    local idx = party:GetMemberTargetIndex(0);
    if (idx == nil or idx == 0) then return false; end

    local st = rt.st;
    st.status = mm:GetEntity():GetStatus(idx);
    st.hp     = party:GetMemberHP(0);
    st.mp     = party:GetMemberMP(0);
    st.maxhp  = player:GetHPMax();
    st.maxmp  = player:GetMPMax();

    local s = rt.settings;
    local did_expensive = false;
    if (s.auto_gear and (rt.gear.force or now >= rt.gear.next_check)) then
        refresh_gear(now); did_expensive = true;
    end
    if (not did_expensive and (rt.buffs.force or now >= rt.buffs.next_check)) then
        refresh_buffs(now);
    end
    -- after the buff scan, so a sync start/end is applied the same frame
    if (now >= rt.jobs.next_check) then refresh_jobs(now, player); end

    local c = rt.ctx;
    c.level    = st.mainlv;
    c.maxhp    = st.maxhp;
    c.maxmp    = st.maxmp;
    c.hp_bonus = (s.auto_gear and rt.gear.hp or 0) + (s.auto_food and rt.food.hp or 0) + (s.bonus_hp or 0);
    c.mp_bonus = (s.auto_gear and rt.gear.mp or 0) + (s.auto_food and rt.food.mp or 0) + (s.bonus_mp or 0);
    c.profile  = s.profile;
    c.cm_tier  = model.clear_mind_tier(st.main, st.mainlv, st.sub, st.sublv, s.profile, s.blu_cm_tier);
    c.blocked  = rt.buffs.blocked;
    local sm = tonumber(s.signet_mode) or 0;
    if (sm == 1) then c.signet = true;
    elseif (sm == 2) then c.signet = false;
    else
        local b = rt.buffs;
        c.signet = model.signet_counts(s.profile, b.has_signet, b.has_sanction, b.has_sigil) and true or false;
    end
    return true;
end
local function read_state_safe() return read_state(); end

--[[
* Fonts
--]]
-- Loads one font family (bold file when asked and present). Returns font, family entry, error.
local function load_family(name, bold)
    if (name == nil or name == '' or name == zzfonts.DEFAULT) then return nil, nil, nil; end
    local f = zzfonts.find(rt.font_list, name);
    if (f == nil) then return nil, nil, 'Font "' .. tostring(name) .. '" not found'; end
    local path = (bold and f.bold_path) or f.path;
    local font, why = zzfonts.load(path, 32);
    if (font == nil and path ~= f.path) then font, why = zzfonts.load(f.path, 32); end
    if (font == nil) then return nil, f, 'Could not load ' .. f.name .. ' (' .. tostring(why) .. ')'; end
    return font, f, nil;
end

local function apply_font()
    rt.font_want = false;
    rt.lvalid    = false;
    rt.wgen      = rt.wgen + 1;
    local s = rt.settings;
    if (rt.font_list == nil) then rt.font_list = zzfonts.scan(addon.path); end
    local why_b, why_t, why_n, d;
    rt.font_obj, d, why_b = load_family(s.font_name, s.font_bold);
    rt.font_title, d, why_t = load_family(s.title_font, true);
    rt.font_num, d, why_n = load_family(s.num_font, s.font_bold);
    local why = why_b or why_t or why_n;
    rt.font_status = why and (why .. '; using default.') or '';
end

-- Faux bold is used when bold is on but there's no bold file (or default font).
local function faux_bold()
    local s = rt.settings;
    if (not s.font_bold) then return false; end
    if (rt.font_obj == nil) then return true; end
    local f = rt.font_list and zzfonts.find(rt.font_list, s.font_name);
    return f == nil or f.bold_path == nil;
end

local function font_base_size()
    local fb = rt.font_base;
    if (rt.now >= fb.next_check) then
        fb.next_check = rt.now + 2.0;
        local ok, gs = pcall(imgui.GetStyle);
        if (ok and gs ~= nil) then
            if (gs.FontSizeBase ~= nil) then fb.size = gs.FontSizeBase; end
            local okp, px, py = pcall(function () local wp = gs.WindowPadding; if (wp == nil) then return nil; end return wp.x or wp[1], wp.y or wp[2]; end);
            if (okp and type(px) == 'number' and not rt.in_main) then rt.style_pad = px; end
            if (okp and type(py) == 'number' and not rt.in_main) then rt.style_pad_y = py; end
        end
    end
    return fb.size;
end

-- Pushes the chosen font/size. Returns 1 if a PopFont is needed.
local function push_font()
    local s = rt.settings;
    local scale = s.scale or 1.0;
    if (rt.font_obj == nil and (s.font_size or 0) <= 0 and scale == 1.0) then return 0; end
    local size = ((s.font_size or 0) > 0 and s.font_size or font_base_size()) * scale;
    local font = rt.font_obj;
    if (font == nil) then
        -- Older Ashita v4 (imgui < 1.92): scale only.
        local has_old, fn = pcall(function () return imgui.SetWindowFontScale; end);
        if (has_old and fn ~= nil) then
            pcall(fn, size / font_base_size());
            return 0;
        end
        local ok, cur = pcall(imgui.GetFont);
        if (not ok) then return 0; end
        font = cur;
    end
    local ok = pcall(imgui.PushFont, font, size);
    return ok and 1 or 0;
end

local function outline_u32()
    if (rt.col_u32 == nil) then
        local c = rt.settings.col_outline;
        rt.col_u32 = imgui.col32(floor(c[4] * 255), floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255));
    end
    return rt.col_u32;
end

local OUT_OFFS = { -1, -1, 1, -1, -1, 1, 1, 1 };
local tmp_pos  = { 0, 0 };
local function draw_text(col, str, fbold, outline)
    if (outline or fbold) then
        local x, y = imgui.GetCursorScreenPos();
        local dl = imgui.GetWindowDrawList();
        if (dl ~= nil and x ~= nil) then
            if (outline) then
                local oc = outline_u32();
                for i = 1, #OUT_OFFS, 2 do
                    tmp_pos[1] = x + OUT_OFFS[i]; tmp_pos[2] = y + OUT_OFFS[i + 1];
                    dl:AddText(tmp_pos, oc, str);
                end
            end
            if (fbold) then
                tmp_pos[1] = x + 1; tmp_pos[2] = y;
                dl:AddText(tmp_pos, imgui.col32(floor(col[4] * 255), floor(col[1] * 255), floor(col[2] * 255), floor(col[3] * 255)), str);
            end
        end
    end
    imgui.TextColored(col, str);
end

--[[
* Cached line formatting.
--]]
-- Effective main level when Level Sync / Restriction caps it below the real level (badge on), else 0.
local function sync_level()
    if (not rt.settings.show_sync) then return 0; end
    if (rt.test_mode and not rt.resting_now) then return rt.test_sync or 0; end
    local lv = rt.lv;
    return (lv.capped and lv.main > 0) and lv.main or 0;
end
local function timer_str(rem, n)
    local c = rt.sc.timer;
    local tenths = ceil(rem * 10 - 1e-6);  -- counts down to 0.1, then rolls straight to the next interval
    if (tenths < 0) then tenths = 0; end
    local show_n = rt.settings.show_tick_no and not rt.settings.compact;
    local mode = rt.settings.compact and 1 or 0;
    local sync = sync_level();
    if (c.k1 ~= tenths or c.k2 ~= n or c.k3 ~= show_n or c.k4 ~= mode or c.k5 ~= sync) then
        c.k1, c.k2, c.k3, c.k4, c.k5 = tenths, n, show_n, mode, sync;
        local t = sformat('%d.%ds', floor(tenths / 10), tenths % 10);
        if (mode == 0) then
            t = 'Next tick: ' .. t;
            if (show_n) then t = t .. '  (#' .. tick_txt(n) .. ')'; end
            if (sync > 0) then t = t .. sformat('  Synced Lv %d', sync); end
        elseif (sync > 0) then
            t = t .. sformat(' Sync %d', sync);
        end
        c.s = t;
    end
    return c.s;
end

local function stat_str(c, label, cur, proj, gain, full)
    local s = rt.settings;
    local mode = (s.compact and 2 or 0) + (s.show_gain and 1 or 0) + (full and 4 or 0);
    if (c.k1 ~= cur or c.k2 ~= proj or c.k3 ~= gain or c.k4 ~= mode) then
        c.k1, c.k2, c.k3, c.k4 = cur, proj, gain, mode;
        local g = s.show_gain and model.fmt_gain(gain) or '';
        if (full) then
            -- full: just the value (no arrow, projection or gain)
            c.s = s.compact and sformat('%s %d', label, cur) or sformat('%s %d (Full)', label, cur);
        elseif (s.compact) then
            c.s = (g ~= '') and sformat('%s %d (%s)', label, proj, g) or sformat('%s %d', label, proj);
        else
            c.s = sformat('%s %d -> %d', label, cur, proj);
            if (g ~= '') then c.s = c.s .. '  (' .. g .. ')'; end
        end
    end
    return c.s;
end

-- which: nil = both stats still filling, 'HP' / 'MP' = only that stat is still filling.
local function full_str(ticks, secs, which)
    local c = rt.sc.full;
    local tenths = secs and ceil(secs * 10 - 1e-6) or -1;
    if (c.k1 ~= ticks or c.k2 ~= tenths or c.k3 ~= which) then
        c.k1, c.k2, c.k3 = ticks, tenths, which;
        if (ticks == 0) then c.s = 'Full';
        elseif (ticks == nil) then c.s = '';
        else
            c.s = sformat('%s in %d tick%s (%s)', which and (which .. ' full') or 'Full', ticks,
                ticks == 1 and '' or 's', model.format_time(tenths / 10));
        end
    end
    return c.s;
end

-- Time-to-full line for the current view (full stats are left out).
local function full_line(st, ctx, n, remaining, eff_hp, eff_mp, has_mp)
    local v = rt.view;
    local ticks = model.ticks_to_full(n, eff_hp, eff_mp, v.mhp, has_mp and v.mmp or 0, ctx);
    local secs = ticks and ticks > 0 and (remaining + (ticks - 1) * rt.tracker.interval) or nil;
    local which = nil;
    if (has_mp and v.fhp ~= v.fmp) then which = v.fhp and 'MP' or 'HP'; end
    return full_str(ticks, secs, which);
end

--[[
* Fake state used by /zztick test (preview/positioning).
--]]
local test_ctx = { level = 75, maxhp = 1250, maxmp = 640, hp_bonus = 0, mp_bonus = 0, signet = false,
                   profile = 'retail', cm_tier = 5, blocked = false };
local test_st  = { hp = 812, mp = 240, maxhp = 1250, maxmp = 640 };

--[[
* Rendering
--]]
local SV_ALPHA    = rawget(_G, 'ImGuiStyleVar_Alpha') or 0;
local SV_SPACING  = rawget(_G, 'ImGuiStyleVar_ItemSpacing') or 14;
local SPACEV      = { 8, 4 };
local SV_PADDING  = rawget(_G, 'ImGuiStyleVar_WindowPadding') or 2;
local SV_ROUNDING = rawget(_G, 'ImGuiStyleVar_WindowRounding') or 3;
local SV_BORDER   = rawget(_G, 'ImGuiStyleVar_WindowBorderSize') or 4;
local COL_WINDOWBG = rawget(_G, 'ImGuiCol_WindowBg') or 2;
local COL_BORDER   = rawget(_G, 'ImGuiCol_Border') or 5;
local DF_TOPLEFT   = rawget(_G, 'ImDrawFlags_RoundCornersTopLeft') or 16;

-- Reused vectors / colors (no allocations per frame).
local V1, V2, V3 = { 0, 0 }, { 0, 0 }, { 0, 0 };
local WSIZE, PADV, DUMMY = { 0, 0 }, { 8, 8 }, { 0, 0 };
local TMPC, TMPC2 = { 1, 1, 1, 1 }, { 1, 1, 1, 1 };
local WHITE = { 1, 1, 1, 1 };
local DIM_CLASSIC = { 0.7, 0.7, 0.7, 1 };

local function vec(v, x, y) v[1] = x; v[2] = y; return v; end
local function u(c, a) return style.u32(imgui.col32, c, (a or 1) * rt.fx.alpha); end
FX.init({ u = u, vec = vec, WHITE = WHITE, rt = rt });

-- While waiting for the server's tick report the bar and timer pulse in alpha (rt.fx.wait_a < 1).
local WAITC = { 1, 1, 1, 1 };
local function wait_col(c)
    local a = rt.fx.wait_a or 1;
    if (a >= 1) then return c; end
    WAITC[1], WAITC[2], WAITC[3], WAITC[4] = c[1], c[2], c[3], (c[4] or 1) * a;
    return WAITC;
end

local function calc_w(str)
    local a, b = imgui.CalcTextSize(str);
    if (type(a) == 'table') then return a.x or a[1] or 0, a.y or a[2] or 0; end
    return a or 0, b or 0;
end

-- Font sizes per role (body size x scale; title a bit larger, digits a bit smaller).
local function body_size()
    local s = rt.settings;
    return ((s.font_size or 0) > 0 and s.font_size or font_base_size()) * (s.scale or 1.0);
end
local function role_font(role)
    if (role == 'title') then return rt.font_title, body_size() * 1.18; end
    if (role == 'num') then return rt.font_num, body_size() * 0.94; end
    return nil, 0;
end
-- Pushes a role font when it loaded; returns 1 if a PopFont is needed.
local function push_role(role)
    local f, size = role_font(role);
    if (f == nil) then return 0; end
    return pcall(imgui.PushFont, f, size) and 1 or 0;
end
local function pop_role(p) if (p == 1) then imgui.PopFont(); end end

local function measure(str, role)
    local p = (role ~= 'body') and push_role(role) or 0;
    local w, h = calc_w(str);
    pop_role(p);
    return w, h;
end

-- Text slots: a cached string plus its measured width (re-measured when fonts change).
local function slot(fmt, f) return { v = nil, s = '', w = -1, g = -1, fmt = fmt, f = f }; end
local function slot_set(sl, v)
    if (sl.v ~= v) then sl.v = v; sl.s = sl.f and sl.f(v) or sformat(sl.fmt, v); sl.w = -1; end
    return sl;
end
local function slot_w(sl)
    if (sl.w < 0 or sl.g ~= rt.wgen) then sl.w = calc_w(sl.s); sl.g = rt.wgen; end
    return sl.w;
end
local SL = {
    tval = { v = nil, s = '', w = -1, g = -1 },
    hcur = slot('%d'), hproj = slot('%d'), hgain = slot(nil, model.fmt_gain),
    mcur = slot('%d'), mproj = slot('%d'), mgain = slot(nil, model.fmt_gain),
    tick = slot(nil, function (n) return 'Tick ' .. tick_txt(n); end),
    sync = slot('Synced Lv %d'),
    csync = slot('Sync %d'),
};
local function tval_slot(rem)
    local sl = SL.tval;
    local tenths = ceil(rem * 10 - 1e-6);
    if (tenths < 0) then tenths = 0; end
    if (sl.v ~= tenths) then sl.v = tenths; sl.s = sformat('%d.%ds', floor(tenths / 10), tenths % 10); sl.w = -1; end
    return sl;
end

--[[
* Countdown cells (v1.4.5). The countdown is drawn glyph by glyph in fixed cells: every digit
* gets the width of the widest digit (and is centered in it), then '.', then 's'. So the right
* edge never moves and each digit stays put, even with a proportional numbers font.
* Widths are measured once per font generation (font, size, scale or theme change), never per frame.
* If the font reports no width for a glyph, the countdown falls back to one right-aligned string.
--]]
local DIGS = { [0] = '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };
local CD = { g = -1, ok = false, dw = 0, w = { [0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, dot = 0, sw = 0 };
local CD_INT_DIGITS = 2;   -- reserved integer digits (intervals and the first delay are capped at 60 s)
-- meas(str) -> width in the numbers font (the caller makes sure that font is active).
local function cd_measure(meas, gen)
    local dw = 0;
    for d = 0, 9 do
        local w = meas(DIGS[d]) or 0;
        if (type(w) ~= 'number' or w ~= w) then w = 0; end
        CD.w[d] = w;
        if (w > dw) then dw = w; end
    end
    CD.dw, CD.dot, CD.sw = dw, meas('.') or 0, meas('s') or 0;
    CD.ok = dw > 0 and type(CD.dot) == 'number' and CD.dot > 0 and type(CD.sw) == 'number' and CD.sw > 0;
    CD.g = gen;
    rt.stats.cd_measures = (rt.stats.cd_measures or 0) + 1;
end
-- Width of a countdown with nd integer digits (cells), or nil when the cells are unusable.
local function cd_width(nd)
    if (not CD.ok) then return nil; end
    return nd * CD.dw + CD.dot + CD.dw + CD.sw;
end
-- Small gap between the countdown and the right edge (scaled).
local function cd_pad_r() return floor(3 * (rt.settings.scale or 1.0) + 0.5); end

-- Static label slots (width cached per font generation).
local LBL = {
    hp = { s = 'HP', w = -1, g = -1 }, mp = { s = 'MP', w = -1, g = -1 },
    arrow = { s = style.ARROW, w = -1, g = -1 }, next = { s = style.LABEL_TIMER, w = -1, g = -1 },
    norec = { s = 'No recovery', w = -1, g = -1 }, title = { s = style.LABEL_TITLE, w = -1, g = -1 },
    blocked = { s = style.WORST.blocked, w = -1, g = -1 },
    full = { s = 'Full', w = -1, g = -1 },
    rested = { s = 'Fully rested', w = -1, g = -1 },
};

local function current_theme()
    local t = style.find_theme(rt.settings.theme);
    return t or style.THEMES[1];
end

--[[
* Layout key: everything the fixed width depends on. Compared field by field (no strings built).
--]]
local LKEYS = { 'theme', 'compact', 'show_timer', 'show_bar', 'show_hp', 'show_mp', 'show_gain', 'show_tick_no',
                'show_full', 'show_last', 'scale', 'font_size', 'width', 'show_title', 'show_sync', 'show_icons' };
local function layout_stale(has_mp)
    local s, k = rt.settings, rt.lkey;
    if (not rt.lvalid) then return true; end
    for i = 1, #LKEYS do if (k[LKEYS[i]] ~= s[LKEYS[i]]) then return true; end end
    return k.has_mp ~= has_mp or k.fb ~= rt.font_obj or k.ft ~= rt.font_title or k.fn ~= rt.font_num
        or k.base ~= rt.font_base.size or k.pad ~= rt.style_pad;
end

local LOPTS = {};
local function rebuild_layout(classic, has_mp)
    local s, k = rt.settings, rt.lkey;
    for i = 1, #LKEYS do k[LKEYS[i]] = s[LKEYS[i]]; end
    k.has_mp, k.fb, k.ft, k.fn, k.base, k.pad = has_mp, rt.font_obj, rt.font_title, rt.font_num, rt.font_base.size, rt.style_pad;
    font_base_size();
    local sc = s.scale or 1.0;
    local o = LOPTS;
    o.classic, o.compact = classic, s.compact;
    o.show_timer, o.show_bar, o.show_hp = s.show_timer, s.show_bar, s.show_hp;
    o.show_mp = s.show_mp and has_mp;
    o.show_gain, o.show_tick_no, o.show_full, o.show_last = s.show_gain, s.show_tick_no, s.show_full, s.show_last;
    o.show_sync = s.show_sync;
    o.show_icons = s.show_icons and not classic;
    local _, bh = measure('HP', 'body');
    o.icon_w = bh * 0.95 + 3 * sc;
    -- compact mode always fits its one row (the width setting is kept and comes back when compact is off)
    o.scale, o.width_override = sc, (not s.compact) and s.width or 0;
    o.pad_x = classic and rt.style_pad or floor(10 * sc + 0.5);
    local _, th = measure(style.LABEL_TITLE, 'title');
    o.title_h = th;
    o.glyph_w = th * 1.55;
    -- countdown cells, measured in the numbers font (role push happens inside measure)
    cd_measure(function (str) return (measure(str, 'num')) end, rt.wgen + 1);
    o.timer_w = cd_width(CD_INT_DIGITS);
    o.timer_pad = classic and 0 or cd_pad_r();
    style.layout(o, measure, rt.L);
    rt.L.timer_pad = o.timer_pad;
    rt.L.pad = o.pad_x;
    rt.L.title_h = th;
    rt.L.glyph_w = o.glyph_w;
    rt.L.text_h = bh;
    rt.L.classic = classic;
    rt.lvalid = true;
    rt.wgen = rt.wgen + 1;
    rt.stats.layouts = (rt.stats.layouts or 0) + 1;
end

-- Draws a right-aligned slot so that its right edge sits at content x = right.
local function text_right(col, str, w, right, first, fb, ol)
    local x = rt.L.pad + right - w;
    if (first) then imgui.SetCursorPosX(x); else imgui.SameLine(x); end
    draw_text(col, str, fb, ol);
end

-- One countdown glyph at content-relative x (snapped to a whole pixel so glyphs stay crisp;
-- cells are fixed, so a given glyph always lands on the same pixel).
local function cd_glyph(col, str, x, first, fb, ol)
    x = floor(x + 0.5);
    if (first) then imgui.SetCursorPosX(x); else imgui.SameLine(x); end
    draw_text(col, str, fb, ol);
end

--[[
* Countdown with its right edge fixed at content x = right (call with the numbers font pushed).
* Glyphs sit in fixed cells (see CD); cell widths are cached per font generation.
--]]
local function draw_countdown(col, sl, right, first, fb, ol)
    if (CD.g ~= rt.wgen) then cd_measure(calc_w, rt.wgen); end
    local tenths = sl.v or 0;
    local ip = floor(tenths / 10);
    local nd = (ip >= 100) and 3 or ((ip >= 10) and 2 or 1);
    if (not CD.ok or nd > CD_INT_DIGITS) then
        -- fallback: whole string, still right-aligned
        rt.stats.cd_fallback = (rt.stats.cd_fallback or 0) + 1;
        text_right(col, sl.s, slot_w(sl), right, first, fb, ol);
        return;
    end
    local dw, W = CD.dw, CD.w;
    local x = rt.L.pad + right - CD.sw - dw - CD.dot - nd * dw;
    if (nd == 2) then
        local d = floor(ip / 10) % 10;
        cd_glyph(col, DIGS[d], x + (dw - W[d]) * 0.5, first, fb, ol); first = false; x = x + dw;
    end
    local d = ip % 10;
    cd_glyph(col, DIGS[d], x + (dw - W[d]) * 0.5, first, fb, ol); x = x + dw;
    cd_glyph(col, '.', x, false, fb, ol); x = x + CD.dot;
    d = tenths % 10;
    cd_glyph(col, DIGS[d], x + (dw - W[d]) * 0.5, false, fb, ol); x = x + dw;
    cd_glyph(col, 's', x, false, fb, ol);
    rt.stats.cd_draws = (rt.stats.cd_draws or 0) + 1;
end
if (rawget(_G, 'ZZTICK_TEST')) then
    rt._draw_countdown, rt._tval_slot, rt._push_role, rt._pop_role, rt._CD = draw_countdown, tval_slot, push_role, pop_role, CD;
    rt._push_font = push_font;
end

--[[
* Draw-list pieces (themes only).
--]]
local function fx_bar(dl, th, x, y, w, h, prog, remaining)
    local sc = rt.settings.scale or 1.0;
    local r = min(h * 0.5, 6 * sc);
    local fade = rt.fx.wait_a or 1.0;   -- pulses while waiting for the tick report
    dl:AddRectFilled(vec(V1, x, y), vec(V2, x + w, y + h), u(th.bar_bg), r);
    -- reset sweep: the just-finished full bar slides off to the right and fades (~120 ms)
    local fl = rt.settings.animate and (rt.snap.flash or 0) or 0;
    if (fl > 0) then
        local gx = x + w * (1 - fl);
        dl:AddRectFilled(vec(V1, gx, y), vec(V2, x + w, y + h), u(th.bar_b, 0.65 * fl * fade), r);
    end
    -- all geometry below is float (sub-pixel); ImGui anti-aliases the edges
    local fw_ = w * prog;
    if (fw_ >= 1) then
        local ua = u(th.bar_a, fade);
        local ue = u(style.mix(TMPC, th.bar_a, th.bar_b, prog), fade);
        if (fw_ <= 2 * r + 1) then
            dl:AddRectFilled(vec(V1, x, y), vec(V2, x + fw_, y + h), ue, r);
        else
            dl:AddRectFilled(vec(V1, x, y), vec(V2, x + 2 * r, y + h), ua, r);
            dl:AddRectFilled(vec(V1, x + fw_ - 2 * r, y), vec(V2, x + fw_, y + h), ue, r);
            dl:AddRectFilledMultiColor(vec(V1, x + r, y), vec(V2, x + fw_ - r, y + h), ua, ue, ue, ua);
            local hi, lo = u(WHITE, 0.30 * fade), u(WHITE, 0.0);
            dl:AddRectFilledMultiColor(vec(V1, x + r, y + 1), vec(V2, x + fw_ - r, y + h * 0.5), hi, hi, lo, lo);
        end
        if (rt.settings.animate and fw_ < w - 1) then
            dl:AddCircleFilled(vec(V3, x + fw_, y + h * 0.5), h * 0.6, u(th.glow, 0.45 * fade), 12);
        end
    end
    FX.bar(dl, th, x, y, w, h, fw_, r, remaining, (rt.fx.wait_a or 1) < 1);
    if (rt.settings.animate and remaining > 0 and remaining < 1.0) then
        local p = style.pulse(rt.now) * (1.0 - remaining * 0.5);
        dl:AddRect(vec(V1, x - 2, y - 2), vec(V2, x + w + 2, y + h + 2), u(th.glow, (0.30 + 0.55 * p) * fade), r + 2, 0, 1.5 * sc);
        dl:AddRect(vec(V1, x - 4, y - 4), vec(V2, x + w + 4, y + h + 4), u(th.glow, 0.25 * p * fade), r + 4, 0, 2.0 * sc);
    end
end

local function fx_minibar(dl, th, x, y, w, h, cur, proj, maxv, col)
    dl:AddRectFilled(vec(V1, x, y), vec(V2, x + w, y + h), u(th.bar_bg), h * 0.5);
    if (maxv == nil or maxv <= 0) then return; end
    local f1 = min(1, max(0, cur / maxv));
    local f2 = min(1, max(f1, proj / maxv));
    if (f1 > 0) then dl:AddRectFilled(vec(V1, x, y), vec(V2, x + w * f1, y + h), u(col, 0.85), h * 0.5); end
    if (f2 > f1) then
        local a = rt.settings.animate and (0.28 + 0.17 * style.pulse(rt.now)) or 0.35;
        dl:AddRectFilled(vec(V1, x + w * f1, y), vec(V2, x + w * f2, y + h), u(col, a), 0);
    end
end

--[[
* Vector glyphs (v1.4.0). All points are float (sub-pixel); triangles are wound clockwise on screen
* so ImGui's anti-aliased fringe goes outward. h = body text height.
--]]
-- Arrow centered in the reserved '->' slot [x, x + w], sized to the text height.
local function fx_arrow(dl, x, y, w, h, col)
    local len = min(w, h * 0.95);
    local x0 = x + (w - len) * 0.5;
    local x1 = x0 + len;
    local cy = y + h * 0.54;
    local hl, hh = h * 0.34, h * 0.24;              -- head length / half height
    local th = max(1.0, h * 0.11);
    dl:AddLine(vec(V1, x0, cy), vec(V2, x1 - hl * 0.6, cy), col, th);
    dl:AddTriangleFilled(vec(V1, x1, cy), vec(V2, x1 - hl, cy + hh), vec(V3, x1 - hl, cy - hh), col);
end

-- Heart: two circles + a triangle. (cx, cy) center, sz ~ text height.
local function fx_heart(dl, cx, cy, sz, col, hi)
    local r = sz * 0.25;
    local ty = cy - sz * 0.12;
    dl:AddCircleFilled(vec(V1, cx - r * 0.98, ty), r, col, 12);
    dl:AddCircleFilled(vec(V1, cx + r * 0.98, ty), r, col, 12);
    dl:AddTriangleFilled(vec(V1, cx - r * 1.95, ty + r * 0.28), vec(V2, cx + r * 1.95, ty + r * 0.28), vec(V3, cx, cy + sz * 0.42), col);
    dl:AddCircleFilled(vec(V1, cx - r * 1.05, ty - r * 0.3), r * 0.32, hi, 8);   -- highlight
end

-- Droplet: a circle with a pointed top (triangle tangent to it).
local function fx_drop(dl, cx, cy, sz, col, hi)
    local r = sz * 0.29;
    local by = cy + sz * 0.16;
    dl:AddCircleFilled(vec(V1, cx, by), r, col, 14);
    dl:AddTriangleFilled(vec(V1, cx, cy - sz * 0.46), vec(V2, cx + r * 0.94, by - r * 0.36), vec(V3, cx - r * 0.94, by - r * 0.36), col);
    dl:AddCircleFilled(vec(V1, cx - r * 0.38, by - r * 0.1), r * 0.26, hi, 8);    -- highlight
end

-- Four-point star (twinkle).
local function fx_star(dl, cx, cy, sz, col)
    local w = sz * 0.26;
    dl:AddTriangleFilled(vec(V1, cx, cy - sz), vec(V2, cx + w, cy), vec(V3, cx - w, cy), col);
    dl:AddTriangleFilled(vec(V1, cx, cy + sz), vec(V2, cx - w, cy), vec(V3, cx + w, cy), col);
    dl:AddTriangleFilled(vec(V1, cx - sz, cy), vec(V2, cx, cy - w), vec(V3, cx, cy + w), col);
    dl:AddTriangleFilled(vec(V1, cx + sz, cy), vec(V2, cx, cy + w), vec(V3, cx, cy - w), col);
end

-- Sparkle over a row at (x, y), width w, text height h; ph = 0..1 phase.
local function fx_sparkle(dl, th, sp, x, y, w, h, ph, col)
    local sc = rt.settings.scale or 1.0;
    local g = (1 - ph) * (1 - ph);
    dl:AddRectFilled(vec(V1, x - 3 * sc, y - 1), vec(V2, x + w + 3 * sc, y + h + 1), u(col, 0.22 * g), h * 0.45);
    local t = ph * model.SPARK_DUR;
    for i = 1, sp.n do
        local p = sp.P[i];
        local lt = (t - p.d) / 0.40;
        if (lt > 0 and lt < 1) then
            local k = math.sin(lt * math.pi);
            fx_star(dl, x + p.x * w, y + p.y * h, p.s * h * 0.5 * k, u(lt < 0.5 and WHITE or th.glow, 0.95 * k));
        end
    end
end

local MOON_TILT = -0.42;    -- radians (about 24 degrees counter-clockwise)
local function fx_header(dl, th, x, y, wdt, hh, show_title)
    local L = rt.L;
    local r = show_title and 0 or (rt.settings.rounding or 0) * (rt.settings.scale or 1.0);
    local x0, y0 = x - L.pad, y - floor(8 * (rt.settings.scale or 1.0) + 0.5);
    local x1, y1 = x0 + wdt, y + hh;
    local hl, hr = u(th.head_l), u(th.head_r);
    if (r > 0) then dl:AddRectFilled(vec(V1, x0, y0), vec(V2, x0 + r + 1, y1), hl, r, DF_TOPLEFT); end
    dl:AddRectFilledMultiColor(vec(V1, x0 + r, y0), vec(V2, x1, y1), hl, hr, hr, hl);
    dl:AddLine(vec(V1, x0 + L.pad * 0.5, y1), vec(V2, x1 - L.pad * 0.5, y1), u(th.rule), 1);
    -- crescent moon + "z z"
    local gr = L.title_h * 0.36;
    local cx, cy = x + gr + 1, y + L.title_h * 0.52;
    local mc = u(th.moon);
    if (FX.sleep) then
        FX.moon_halo(dl, th, cx, cy, gr);
        mc = u(th.moon, FX.moon_breath(rt.now));
    end
    local O, I = style.MOON_OUTER, style.MOON_INNER;
    -- the crescent is tilted (not straight up and down) and sways a little with the sleep effect
    local tilt = MOON_TILT + (FX.sleep and 0.07 * math.sin(rt.now * 0.7) or 0);
    local ca, sa = math.cos(tilt), math.sin(tilt);
    for i = 1, #O - 1 do
        local a, b, c, d = O[i], O[i + 1], I[i], I[i + 1];
        local ax, ay = cx + (a[1] * ca - a[2] * sa) * gr, cy + (a[1] * sa + a[2] * ca) * gr;
        local bx, by = cx + (b[1] * ca - b[2] * sa) * gr, cy + (b[1] * sa + b[2] * ca) * gr;
        local cx_, cy_ = cx + (c[1] * ca - c[2] * sa) * gr, cy + (c[1] * sa + c[2] * ca) * gr;
        local dx, dy = cx + (d[1] * ca - d[2] * sa) * gr, cy + (d[1] * sa + d[2] * ca) * gr;
        dl:AddTriangleFilled(vec(V1, ax, ay), vec(V2, bx, by), vec(V3, cx_, cy_), mc);
        dl:AddTriangleFilled(vec(V1, bx, by), vec(V2, dx, dy), vec(V3, cx_, cy_), mc);
    end
    if (FX.sleep) then
        FX.zs(dl, th, cx + gr * 0.9, cy - gr * 1.9, gr);
    else
        local zc = u(th.moon, 0.75);
        dl:AddText(vec(V1, cx + gr * 0.9, cy - gr * 1.9), zc, 'z');
        dl:AddText(vec(V1, cx + gr * 1.7, cy - gr * 2.6), u(th.moon, 0.5), 'z');
    end
end

--[[
* Classic look (v1.1): plain text lines + ImGui progress bar, now at a fixed width.
--]]
local draw_food_line, draw_food_classic;   -- defined with the food line below
local function draw_classic_body(st, ctx, remaining, progress, n, eff_hp, eff_mp, php, pmp, ghp, gmp, has_mp, fb, ol)
    local s = rt.settings;
    if (s.compact) then
        local first = true;
        if (s.show_timer) then draw_text(wait_col(s.col_timer), timer_str(remaining, n), fb, ol); first = false; end
        if (s.show_hp) then
            if (not first) then imgui.SameLine(); end
            draw_text(s.col_hp, stat_str(rt.sc.hp, 'HP', eff_hp, php, ghp, rt.view.fhp), fb, ol); first = false;
        end
        if (s.show_mp and has_mp) then
            if (not first) then imgui.SameLine(); end
            draw_text(s.col_mp, stat_str(rt.sc.mp, 'MP', eff_mp, pmp, gmp, rt.view.fmp), fb, ol);
        end
    else
        if (s.show_timer) then draw_text(wait_col(s.col_timer), timer_str(remaining, n), fb, ol); end
        if (s.show_hp) then draw_text(s.col_hp, stat_str(rt.sc.hp, 'HP', eff_hp, php, ghp, rt.view.fhp), fb, ol); end
        if (s.show_mp and has_mp) then draw_text(s.col_mp, stat_str(rt.sc.mp, 'MP', eff_mp, pmp, gmp, rt.view.fmp), fb, ol); end
        if (s.show_full) then
            -- one reserved line: blocked warning, time to full, or blank (keeps the height fixed)
            if (ctx.blocked) then draw_text(WARN_COLOR, 'No recovery (Disease/Plague/Curse)', fb, ol);
            else
                draw_text(s.col_text, full_line(st, ctx, n, remaining, eff_hp, eff_mp, has_mp), fb, ol);
            end
        elseif (ctx.blocked) then
            draw_text(WARN_COLOR, 'No recovery (Disease/Plague/Curse)', fb, ol);
        end
        if (s.show_last) then
            local tr = rt.tracker;
            if (not rt.test_mode and tr.last_gain_hp ~= nil) then
                local c = rt.sc.last;
                if (c.k1 ~= tr.last_gain_hp or c.k2 ~= tr.last_gain_mp or c.k3 ~= tr.last_exp_hp or c.k4 ~= tr.last_exp_mp) then
                    c.k1, c.k2, c.k3, c.k4 = tr.last_gain_hp, tr.last_gain_mp, tr.last_exp_hp, tr.last_exp_mp;
                    c.s = sformat('Last: %d HP / %d MP (exp %d / %d)', c.k1, c.k2, c.k3 or 0, c.k4 or 0);
                end
                imgui.TextDisabled(c.s);
            else
                imgui.TextDisabled('');
            end
        end
        draw_food_classic(fb, ol);
    end
    if (s.show_bar) then
        local fade = rt.fx.wait_a or 1.0;   -- pulses while waiting for the tick report
        local bar_col = { s.col_bar[1], s.col_bar[2], s.col_bar[3], (s.col_bar[4] or 1) * fade };
        imgui.PushStyleColor(ImGuiCol_PlotHistogram, bar_col);
        imgui.PushStyleColor(ImGuiCol_FrameBg, s.col_bar_bg);
        rt.bar_size[1] = rt.L.cw;
        rt.bar_size[2] = s.bar_height * (s.scale or 1.0);
        local bx, by = imgui.GetCursorScreenPos();
        imgui.ProgressBar(progress, rt.bar_size, '');
        imgui.PopStyleColor(2);
        -- reset sweep on every tick roll-over (same effect as the themed bar): a light wash that
        -- slides off to the right and fades
        local fl = s.animate and (rt.snap.flash or 0) or 0;
        if (fl > 0 and bx ~= nil) then
            local dl = imgui.GetWindowDrawList();
            if (dl ~= nil) then
                local c, bw = s.col_bar, rt.bar_size[1];
                local r_ = floor((c[1] + (1 - c[1]) * 0.45) * 255 + 0.5);
                local g_ = floor((c[2] + (1 - c[2]) * 0.45) * 255 + 0.5);
                local b_ = floor((c[3] + (1 - c[3]) * 0.45) * 255 + 0.5);
                local a_ = floor(255 * 0.65 * fl * rt.fx.alpha + 0.5);
                dl:AddRectFilled(vec(V1, bx + bw * (1 - fl), by), vec(V2, bx + bw, by + rt.bar_size[2]), imgui.col32(a_, r_, g_, b_), 0);
            end
        end
    end
end

--[[
* Themed look.
--]]

--[[
* Food line (v1.5.0). One line under the stats while the Food effect lasts: a small bowl, the food's name
* and the healing bonus it adds per tick. If the effect is on but the food is unknown (eaten before the
* addon loaded) it says so, because that bonus is not in the projection. Hover for the bonus breakdown.
* Not drawn in compact mode. The preview window shows a sample.
--]]
do   -- scoped (keeps the main chunk under Lua's 200-locals limit)
local FOOD_SAMPLE = { name = 'Tavnazian Taco', hp = 3, mp = 2 };
-- returns kind ('ok' | 'unknown' | 'off'), name, hp, mp, or nil when there is nothing to show
local function food_info()
    local s = rt.settings;
    if (not s.show_food) then return nil; end
    if (rt.test_mode and not rt.resting_now) then return 'ok', FOOD_SAMPLE.name, FOOD_SAMPLE.hp, FOOD_SAMPLE.mp; end
    if (not rt.buffs.has_food) then return nil; end
    if (not s.auto_food) then return 'off'; end
    local f = rt.food;
    if (f.id ~= 0) then return 'ok', f.name, f.hp, f.mp; end
    return 'unknown';
end

local FOODC = { key = nil, name = '', nw = 0, hp = '', hw = 0, mp = '', mw = 0, msg = '', mgw = 0 };
local function food_cache(kind, name, hp, mp, avail)
    local c = FOODC;
    local key = sformat('%s|%s|%s|%s|%d|%d', kind, tostring(name), tostring(hp), tostring(mp), floor(avail), rt.wgen);
    if (c.key == key) then return c; end
    c.key = key;
    if (kind == 'ok') then
        c.hp = (hp ~= 0) and sformat('%s HP', model.fmt_bonus(hp)) or '';
        c.mp = (mp ~= 0) and sformat('%s MP', model.fmt_bonus(mp)) or '';
        c.hw, c.mw = (c.hp ~= '') and calc_w(c.hp) or 0, (c.mp ~= '') and calc_w(c.mp) or 0;
        local gap = calc_w('  ');
        local bonus = (c.hw > 0 and (gap + c.hw) or 0) + (c.mw > 0 and (gap + c.mw) or 0);
        local nm = tostring(name or '');
        local w = calc_w(nm);
        while (w + bonus > avail and #nm > 3) do
            nm = nm:sub(1, -2);
            w = calc_w(nm .. '..');
        end
        c.name = (nm ~= tostring(name or '')) and (nm .. '..') or nm;
        c.nw = calc_w(c.name);
        c.gap = gap;
    else
        c.msg = (kind == 'unknown') and 'Food: unknown, bonus not counted' or 'Food active, bonus not counted';
        local nm = c.msg;
        local w = calc_w(nm);
        while (w > avail and #nm > 8) do nm = nm:sub(1, -2); w = calc_w(nm .. '..'); end
        if (nm ~= c.msg) then c.msg = nm .. '..'; end
    end
    return c;
end

-- text at an absolute screen position with the same bold / outline options as draw_text
local function abs_text(dl, x, y, col, str, fbold, outline)
    if (outline) then
        local oc = outline_u32();
        for i = 1, #OUT_OFFS, 2 do dl:AddText(vec(V3, x + OUT_OFFS[i], y + OUT_OFFS[i + 1]), oc, str); end
    end
    local c = u(col);
    dl:AddText(vec(V3, x, y), c, str);
    if (fbold) then dl:AddText(vec(V3, x + 1, y), c, str); end
end

local function food_tooltip()
    local s, c = rt.settings, rt.ctx;
    local g = rt.food;
    return sformat('Healing bonus per rest tick\n  Gear:   %s HP / %s MP\n  Food:   %s HP / %s MP\n  Manual: %s HP / %s MP\n  Total:  %s HP / %s MP',
        model.fmt_bonus(s.auto_gear and rt.gear.hp or 0), model.fmt_bonus(s.auto_gear and rt.gear.mp or 0),
        model.fmt_bonus(s.auto_food and g.hp or 0), model.fmt_bonus(s.auto_food and g.mp or 0),
        model.fmt_bonus(s.bonus_hp or 0), model.fmt_bonus(s.bonus_mp or 0),
        model.fmt_bonus(c.hp_bonus or 0), model.fmt_bonus(c.mp_bonus or 0));
end

draw_food_line = function (dl, th, fb, ol)
    local kind, name, hp, mp = food_info();
    if (kind == nil) then return; end
    local s, L = rt.settings, rt.L;
    local sc = s.scale or 1.0;
    local h = L.text_h or 13;
    local x, y = imgui.GetCursorScreenPos();
    if (x == nil or dl == nil) then return; end
    local iw = h * 0.95 + 3 * sc;
    local c = food_cache(kind, name, hp, mp, L.cw - iw);
    imgui.Dummy(vec(DUMMY, L.cw, h));               -- the hover area (and the line's height)
    local hovered = false;
    if (imgui.IsItemHovered ~= nil) then local okh, hv = pcall(imgui.IsItemHovered); hovered = okh and hv == true; end
    local anim = s.animate and s.fx_level ~= 'off';
    FX.bowl(dl, x + iw * 0.45, y + h * 0.5, h, kind == 'ok' and (th.accent or th.dim) or th.warn, th.dim, anim);
    if (kind == 'ok') then
        local tx = x + iw;
        abs_text(dl, tx, y, th.dim, c.name, fb, ol);
        tx = tx + c.nw;
        if (c.hw > 0) then tx = tx + c.gap; abs_text(dl, tx, y, th.hp, c.hp, fb, ol); tx = tx + c.hw; end
        if (c.mw > 0) then tx = tx + c.gap; abs_text(dl, tx, y, th.mp, c.mp, fb, ol); end
    else
        abs_text(dl, x + iw, y, th.warn, c.msg, fb, ol);
    end
    if (hovered and imgui.SetTooltip ~= nil) then pcall(imgui.SetTooltip, food_tooltip()); end
end

-- Classic theme: a plain text line.
draw_food_classic = function (fb, ol)
    local kind, name, hp, mp = food_info();
    if (kind == nil) then return; end
    local s = rt.settings;
    if (kind == 'ok') then
        local t = sformat('Food: %s', tostring(name));
        if (hp ~= 0) then t = t .. sformat('  %s HP', model.fmt_bonus(hp)); end
        if (mp ~= 0) then t = t .. sformat('  %s MP', model.fmt_bonus(mp)); end
        draw_text(DIM_CLASSIC, t, fb, ol);
    else
        draw_text(WARN_COLOR, (kind == 'unknown') and 'Food: unknown, bonus not counted' or 'Food active, bonus not counted', fb, ol);
    end
end
end

local function stat_row(dl, th, lbl, col, cur_sl, proj_sl, gain_sl, cur, proj, maxv, blocked, pop_s, pop_w, fb, ol, full, sp, icon)
    local s, L = rt.settings, rt.L;
    local rx, ry = imgui.GetCursorScreenPos();
    local h = L.text_h or 13;
    local fe = s.full_effect;
    local sph = (s.animate and (fe == 'sparkle' or fe == 'both') and dl ~= nil and rx ~= nil) and sp:phase(rt.now) or nil;
    local tick_t = rt.now - rt.fx.pop_at;          -- seconds since the tick that gained something
    local gained = pop_s ~= '' and tick_t >= 0;
    if (gained and FX.glint and dl ~= nil and rx ~= nil) then
        local sc_ = s.scale or 1.0;
        FX.row_glint(dl, rx, ry, rx + L.cw, ry + h + (s.show_minibars and (3 * sc_ + 3) or 0), tick_t, col);
    end
    if (sph ~= nil) then
        fx_sparkle(dl, th, sp, rx, ry, L.cw, h, sph, col);
        rt.stats.sparkle = (rt.stats.sparkle or 0) + 1; rt.stats.f_sparkle = rt.stats.f_sparkle + 1;
    end
    if (L.icon_w > 0) then
        if (dl ~= nil and rx ~= nil) then
            local f = (icon == 1) and fx_heart or fx_drop;
            f(dl, rx + L.icon_w * 0.5 - 1.5 * (s.scale or 1.0), ry + h * 0.5, h * 0.82 * (gained and FX.pop_k(tick_t) or 1), u(col), u(WHITE, 0.45));
            rt.stats.icons = (rt.stats.icons or 0) + 1; rt.stats.f_icons = rt.stats.f_icons + 1;
        end
        imgui.SetCursorPosX(L.pad + L.icon_w);
    end
    draw_text(col, lbl.s, fb, ol);
    local p = push_role('num');
    text_right(th.text, cur_sl.s, slot_w(cur_sl), L.x_cur_r, false, fb, ol);
    pop_role(p);
    if (full) then
        -- full: a quiet "Full" in the arrow/projection slots; gain slot left empty (same line, same width).
        -- Right after the sparkle it fades from the stat color down to the dim color.
        imgui.SameLine(L.pad + L.x_arrow);
        draw_text(sph and style.mix(TMPC2, col, th.dim, sph) or th.dim, LBL.full.s, fb, ol);
        p = push_role('num');
    else
        if (dl ~= nil and rx ~= nil) then
            -- vector arrow in the slot the layout reserved for '->' (same width, same alignment)
            local aw = (LBL.arrow.g == rt.wgen) and LBL.arrow.w or calc_w(style.ARROW);
            LBL.arrow.w, LBL.arrow.g = aw, rt.wgen;
            fx_arrow(dl, rx + L.x_arrow, ry, aw, h, u(th.accent or th.dim, 0.95));
            rt.stats.arrows = (rt.stats.arrows or 0) + 1; rt.stats.f_arrows = rt.stats.f_arrows + 1;
        else
            imgui.SameLine(L.pad + L.x_arrow);
            draw_text(th.dim, style.ARROW, fb, ol);
        end
        p = push_role('num');
        text_right(col, proj_sl.s, slot_w(proj_sl), L.x_proj_r, false, fb, ol);
    end
    if (s.show_gain) then
        local t = rt.now - rt.fx.pop_at;
        if (not full and gain_sl.s ~= '') then
            local gc = blocked and th.warn or th.gain;
            if (s.animate and t >= 0 and t < 0.6 and not blocked) then gc = style.mix(TMPC2, WHITE, th.gain, style.ease_out(t / 0.6)); end
            text_right(gc, gain_sl.s, slot_w(gain_sl), L.x_gain_r, false, fb, ol);
        end
        -- floating "+N" from the tick that just landed (also the final one that filled the stat)
        if (s.animate and pop_s ~= '' and t >= 0 and t < 0.9 and dl ~= nil and rx ~= nil) then
            if (pop_w < 0) then pop_w = calc_w(pop_s); end
            local e = style.ease_out(t / 0.9);
            dl:AddText(vec(V1, rx + L.x_gain_r - pop_w, ry - 10 * (s.scale or 1.0) * e), u(th.gain, 1.0 - e), pop_s);
        end
    end
    pop_role(p);
    if (s.show_minibars and dl ~= nil) then
        local bx, by = imgui.GetCursorScreenPos();
        local h = max(2, floor(3 * (s.scale or 1.0) + 0.5));
        -- no ghost segment when full
        if (bx ~= nil) then fx_minibar(dl, th, bx, by, L.cw, h, cur, full and cur or proj, maxv, col); end
        imgui.Dummy(vec(DUMMY, L.cw, h));
    end
    return pop_w;
end

local function compact_stat(first, x, lbl, col, proj_sl, gain_sl, blocked, th, fb, ol, full, icon)
    local s, L = rt.settings, rt.L;
    local lx = L.pad + x + L.icon_w;
    if (first) then imgui.SetCursorPosX(lx); else imgui.SameLine(lx); end
    if (L.icon_w > 0) then
        local dl = imgui.GetWindowDrawList();
        local sx, sy = imgui.GetCursorScreenPos();
        if (dl ~= nil and sx ~= nil) then
            local h = L.text_h or 13;
            local f = (icon == 1) and fx_heart or fx_drop;
            f(dl, sx - L.icon_w * 0.5 - 1.5 * (s.scale or 1.0), sy + h * 0.5, h * 0.82, u(col), u(WHITE, 0.45));
            rt.stats.icons = (rt.stats.icons or 0) + 1; rt.stats.f_icons = rt.stats.f_icons + 1;
        end
    end
    draw_text(col, lbl.s, fb, ol);
    local p = push_role('num');
    local r = x + L.c_label + L.gap * 0.5 + L.c_num;
    text_right(col, proj_sl.s, slot_w(proj_sl), r, false, fb, ol);
    if (s.show_gain and not full and gain_sl.s ~= '') then
        local gw = slot_w(gain_sl);
        text_right(blocked and th.warn or th.gain, gain_sl.s, gw, r + L.gap * 0.5 + gw, false, fb, ol);
    end
    pop_role(p);
end

local function draw_theme_body(th, st, ctx, remaining, progress, n, eff_hp, eff_mp, php, pmp, ghp, gmp, has_mp, fb, ol)
    local s, L, fx = rt.settings, rt.L, rt.fx;
    local dl = imgui.GetWindowDrawList();
    local sc = s.scale or 1.0;
    local blocked = ctx.blocked;

    -- progress is the display bar's fill (monotonic within an interval, see zzmodel Bar)
    local prog = progress;

    -- timer color: breathes toward the glow color in the last second
    local tcol = th.timer;
    local waiting = (rt.fx.wait_a or 1) < 1;
    if (s.animate and remaining < 1.0 and not waiting) then tcol = style.mix(TMPC, th.timer, th.glow, style.pulse(rt.now)); end
    if (waiting) then tcol = wait_col(tcol); end

    if (s.compact) then
        local first = true;
        if (s.show_timer) then
            local p = push_role('num');
            local sl = tval_slot(remaining);
            draw_countdown(blocked and th.warn or tcol, sl, L.c_timer_r, true, fb, ol);
            pop_role(p);
            first = false;
        end
        local sync = sync_level();
        if (sync > 0) then
            local sl = slot_set(SL.csync, sync);
            text_right(th.accent or th.dim, sl.s, slot_w(sl), L.c_sync_x + L.c_sync_w, first, fb, ol);
            first = false;
            rt.stats.badge = (rt.stats.badge or 0) + 1;
        end
        if (s.show_hp) then compact_stat(first, L.c_hp_x, LBL.hp, th.hp, slot_set(SL.hproj, php), slot_set(SL.hgain, ghp), blocked, th, fb, ol, rt.view.fhp, 1); first = false; end
        if (s.show_mp and has_mp) then compact_stat(first, L.c_mp_x, LBL.mp, th.mp, slot_set(SL.mproj, pmp), slot_set(SL.mgain, gmp), blocked, th, fb, ol, rt.view.fmp, 2); first = false; end
        if (first) then imgui.Text(''); end
    else
        -- header strip with moon glyph, title and tick number
        local hx, hy = imgui.GetCursorScreenPos();
        if (dl ~= nil and hx ~= nil) then fx_header(dl, th, hx, hy, L.w, L.title_h + 3 * sc, s.show_title); end
        imgui.SetCursorPosX(L.pad + L.glyph_w);
        local p = push_role('title');
        draw_text(th.title, LBL.title.s, fb, ol);
        pop_role(p);
        if (s.show_tick_no) then
            local sl = slot_set(SL.tick, n);
            text_right(th.accent or th.dim, sl.s, slot_w(sl), L.cw, false, fb, ol);
        end
        local sync = sync_level();
        if (sync > 0) then
            -- subtle pill left of the tick number, inside the slot the layout reserved
            local sl = slot_set(SL.sync, sync);
            local sw = slot_w(sl);
            local right = L.cw - (s.show_tick_no and (L.tick_w + L.gap * 2) or 0) - L.badge_pad;
            if (dl ~= nil and hx ~= nil) then
                local th_ = L.title_h;
                dl:AddRectFilled(vec(V1, hx + right - sw - L.badge_pad, hy + th_ * 0.12), vec(V2, hx + right + L.badge_pad, hy + th_ * 0.92),
                    u(th.accent or th.dim, 0.16), th_ * 0.4);
            end
            text_right(th.accent or th.dim, sl.s, sw, right, false, fb, ol);
            rt.stats.badge = (rt.stats.badge or 0) + 1;
        end
        -- spacer under the header (+ a little top padding for the countdown row, v1.4.5)
        imgui.Dummy(vec(DUMMY, 1, 2 * sc + (s.show_timer and max(1, floor(2 * sc + 0.5)) or 0)));

        if (s.show_timer) then
            draw_text(blocked and th.warn or th.dim, blocked and LBL.norec.s or LBL.next.s, fb, ol);
            p = push_role('num');
            local sl = tval_slot(remaining);
            draw_countdown(blocked and th.warn or tcol, sl, L.cw - (L.timer_pad or 0), false, fb, ol);
            pop_role(p);
        end
    end

    if (s.show_bar) then
        local bx, by = imgui.GetCursorScreenPos();
        local h = max(2, s.bar_height * sc);
        if (dl ~= nil and bx ~= nil) then fx_bar(dl, th, bx, by, L.cw, h, prog, remaining); end
        imgui.Dummy(vec(DUMMY, L.cw, h));
    end

    if (not s.compact) then
        local active_pop = rt.now - fx.pop_at < 0.9;
        if (s.show_hp) then
            fx.pop_whp = stat_row(dl, th, LBL.hp, th.hp, slot_set(SL.hcur, FX.roll('hp', eff_hp, rt.now)), slot_set(SL.hproj, php), slot_set(SL.hgain, ghp),
                eff_hp, php, rt.view.mhp, blocked, active_pop and fx.pop_hp or '', fx.pop_whp, fb, ol, rt.view.fhp, fx.spark_hp, 1);
        end
        if (s.show_mp and has_mp) then
            fx.pop_wmp = stat_row(dl, th, LBL.mp, th.mp, slot_set(SL.mcur, FX.roll('mp', eff_mp, rt.now)), slot_set(SL.mproj, pmp), slot_set(SL.mgain, gmp),
                eff_mp, pmp, rt.view.mmp, blocked, active_pop and fx.pop_mp or '', fx.pop_wmp, fb, ol, rt.view.fmp, fx.spark_mp, 2);
        end
        if (s.show_full) then
            if (blocked) then draw_text(th.warn, LBL.blocked.s, fb, ol);
            elseif (FX.rested and rt.view.fhp and (rt.view.fmp or not has_mp)) then
                -- both full: "Fully rested" in the accent color, with a few twinkling stars (full effects)
                local lx, ly = imgui.GetCursorScreenPos();
                draw_text(th.accent or th.glow, LBL.rested.s, fb, ol);
                if (lx ~= nil and dl ~= nil) then
                    if (LBL.rested.g ~= rt.wgen) then LBL.rested.w, LBL.rested.g = calc_w(LBL.rested.s), rt.wgen; end
                    FX.rested_stars(dl, th, lx, ly, LBL.rested.w, L.text_h or 13);
                end
            else
                draw_text(th.dim, full_line(st, ctx, n, remaining, eff_hp, eff_mp, has_mp), fb, ol);
            end
        end
        if (s.show_last) then
            local tr = rt.tracker;
            local c = rt.sc.last;
            if (not rt.test_mode and tr.last_gain_hp ~= nil) then
                if (c.k1 ~= tr.last_gain_hp or c.k2 ~= tr.last_gain_mp or c.k3 ~= tr.last_exp_hp or c.k4 ~= tr.last_exp_mp) then
                    c.k1, c.k2, c.k3, c.k4 = tr.last_gain_hp, tr.last_gain_mp, tr.last_exp_hp, tr.last_exp_mp;
                    c.s = sformat('Last: %d HP / %d MP (exp %d / %d)', c.k1, c.k2, c.k3 or 0, c.k4 or 0);
                end
                draw_text(th.dim, c.s, fb, ol);
            else
                draw_text(th.dim, '', fb, ol);
            end
        end
        draw_food_line(dl, th, fb, ol);
    end
end

--[[
* Border flash (v1.4.2): a comet runs one lap around the window border (HP clockwise, MP
* counter-clockwise, so two streaks run in opposite directions when both fill on the same tick),
* then the whole border glows and fades. Geometry is recomputed only when the window size or
* rounding changes; per frame it is FLASH_SEGS lines + 2 circles per streak, or 2 rects per pulse.
--]]
local FLC = { { 1, 1, 1, 1 }, { 1, 1, 1, 1 } };

--[[
* Window rect for the flash (v1.4.7). Built only from the window's own content coordinates, the same
* space every other Zztick drawing uses (header strip, bars, icons all draw at GetCursorScreenPos):
*   origin = GetCursorScreenPos() - GetCursorPos() right after Begin (screen minus window-local),
*   width  = the width Zztick sets on the window (layout width),
*   height = window-local cursor y after the last line - item spacing + bottom padding.
* GetWindowPos/GetWindowSize, the display size and the framebuffer scale are NOT used for drawing
* (1.4.6 used GetWindowPos/GetWindowSize; they are read only for /zztick debug flash).
--]]
local WR = { x = 0, y = 0, w = 0, h = 0, ok = false, why = 'not captured', frame = -1, in_win = false,
             sx = 0, sy = 0, lx = 0, ly = 0, ely = 0, pad_y = 0, sp_y = 0 };
local function index_xy(a) return a.x or a[1], a.y or a[2]; end
local function read_xy(fn)
    if (fn == nil) then return nil, nil; end
    local ok, a, b = pcall(fn);
    if (not ok) then return nil, nil; end
    local ta = type(a);
    if (ta == 'table' or ta == 'userdata') then
        local ok2, x, y = pcall(index_xy, a);
        if (ok2) then return x, y; end
        return nil, nil;
    end
    return a, b;
end
local function finite(v) return type(v) == 'number' and v == v and v > -1e7 and v < 1e7; end

-- Right after Begin: the window origin in content (screen) coordinates.
local function capture_window_rect(classic)
    WR.ok, WR.frame = false, rt.stats.frames;
    local sx, sy = read_xy(imgui.GetCursorScreenPos);
    local lx, ly = read_xy(imgui.GetCursorPos);
    WR.sx, WR.sy, WR.lx, WR.ly = sx, sy, lx, ly;
    WR.pad_y = classic and (rt.style_pad_y or 8) or PADV[2];
    WR.sp_y = (rt.style_spacing_y or 4) + (rt.settings.row_pad or 0) * (rt.settings.scale or 1.0);
    if (not (finite(sx) and finite(sy) and finite(lx) and finite(ly))) then
        WR.x, WR.y, WR.why = nil, nil, 'cursor position unavailable';
        return;
    end
    WR.x, WR.y = sx - lx, sy - ly;
    WR.why = 'not finished';
end

-- After the last line: height from the window-local cursor, width from the layout.
local function finish_window_rect()
    if (WR.x == nil or WR.frame ~= rt.stats.frames) then return; end
    local _, ely = read_xy(imgui.GetCursorPos);
    WR.ely = ely;
    if (not finite(ely)) then WR.why = 'cursor position unavailable'; return; end
    local w = rt.lvalid and rt.L.w or nil;
    if (not finite(w)) then WR.why = 'layout not ready'; return; end
    local h = ely - WR.sp_y + WR.pad_y;
    WR.w, WR.h = w, h;
    if (w < 4 or h < 4) then WR.why = 'window too small'; return; end
    local sc = rt.settings.scale or 1.0;
    local max_h = (rt.L.text_h or 16) * 16 + 96 * sc;
    if (h > max_h) then WR.why = 'height larger than the window can be'; return; end   -- static text: no per-frame garbage
    WR.ok, WR.why = true, '';
end
rt._WR = WR;

-- /zztick debug flash: one chat dump of every coordinate source (read on request only).
local function get_io_field(io, k) return io[k]; end
local function flash_debug_print()
    local gx, gy = read_xy(imgui.GetWindowPos);
    local gw, gh = read_xy(imgui.GetWindowSize);
    local dsw, dsh, fbx, fby;
    local ok, io = pcall(imgui.GetIO);
    if (ok and io ~= nil) then
        local ok1, ds = pcall(get_io_field, io, 'DisplaySize');
        if (ok1 and ds ~= nil) then local o, a, b = pcall(index_xy, ds); if (o) then dsw, dsh = a, b; end end
        local ok2, fs = pcall(get_io_field, io, 'DisplayFramebufferScale');
        if (ok2 and fs ~= nil) then local o, a, b = pcall(index_xy, fs); if (o) then fbx, fby = a, b; end end
    end
    local function n(v) return type(v) == 'number' and sformat('%.1f', v) or tostring(v); end
    msg(sformat('Flash rect (drawn): pos %s,%s size %sx%s  [%s]', n(WR.x), n(WR.y), n(WR.w), n(WR.h), WR.ok and 'ok' or ('skipped: ' .. tostring(WR.why))));
    msg(sformat('  content cursor: screen %s,%s  local %s,%s  end y %s  pad y %s  spacing y %s', n(WR.sx), n(WR.sy), n(WR.lx), n(WR.ly), n(WR.ely), n(WR.pad_y), n(WR.sp_y)));
    msg(sformat('  GetWindowPos %s,%s  GetWindowSize %sx%s  (not used for drawing)', n(gx), n(gy), n(gw), n(gh)));
    msg(sformat('  io.DisplaySize %sx%s  DisplayFramebufferScale %s,%s  layout width %s  scale %s', n(dsw), n(dsh), n(fbx), n(fby),
        n(rt.L.w), n(rt.settings.scale)));
    rt.stats.flash_dbg = (rt.stats.flash_dbg or 0) + 1;
end

-- io.DisplaySize (the game's screen in ImGui units), or nil when it can't be read.
local function display_size()
    local ok, io = pcall(imgui.GetIO);
    if (not ok or io == nil) then return nil, nil; end
    local ok1, ds = pcall(get_io_field, io, 'DisplaySize');
    if (not ok1 or ds == nil) then return nil, nil; end
    local o, w, h = pcall(index_xy, ds);
    if (o and finite(w) and finite(h) and w >= 320 and h >= 200) then return w, h; end
    return nil, nil;
end
rt._display_size = display_size;

-- 1.1.2: a saved position off the screen (another resolution, or a stray move) is pulled back so the
-- whole window shows; the window can't end up where it can't be seen or dragged.
local function keep_on_screen(s)
    local dw, dh = display_size();
    if (dw == nil) then return; end
    local w = (rt.lvalid and finite(rt.L.w)) and rt.L.w or 200;
    local h = (WR.ok and finite(WR.h)) and WR.h or 60;
    local nx = max(0, min(tonumber(s.x) or 0, dw - w));
    local ny = max(0, min(tonumber(s.y) or 0, dh - h));
    nx, ny = floor(nx), floor(ny);
    if (nx ~= s.x or ny ~= s.y) then s.x, s.y = nx, ny; mark_dirty(rt.now); end
end

local function flash_active(now)
    local ft, span = rt.fx.flash_t, style.FLASH_LAP + style.FLASH_PULSE;
    return (now - ft[1] >= 0 and now - ft[1] < span) or (now - ft[2] >= 0 and now - ft[2] < span);
end

local function flash_skip(why)
    rt.stats.flash_skipped = (rt.stats.flash_skipped or 0) + 1;
    rt.flash_skip_why = why;
    if (not rt.flash_skip_told) then
        rt.flash_skip_told = true;
        print(chat.header(addon.name):append(chat.error(sformat('Border flash skipped: the window rect looked wrong (%s; pos %s,%s size %sx%s).',
            why, tostring(WR.x), tostring(WR.y), tostring(WR.w), tostring(WR.h)))));
    end
end

local function draw_flash(th, classic, now)
    -- only inside our own Begin/End, with this frame's validated rect
    if (not WR.in_win or WR.frame ~= rt.stats.frames) then flash_skip('not inside the Zztick window'); return; end
    if (not WR.ok) then flash_skip(WR.why); return; end
    local px, py, ww, wh = WR.x, WR.y, WR.w, WR.h;
    -- 1.1.2: never a comet around something screen-sized, or around a window that isn't fully on the screen
    local dw, dh = display_size();
    if (dw ~= nil and (ww > dw * 0.6 or wh > dh * 0.6 or px < -1 or py < -1 or px + ww > dw + 1 or py + wh > dh + 1)) then
        flash_skip('window rect not inside the screen'); return;
    end
    local dl = imgui.GetWindowDrawList();     -- the Zztick window's own draw list, nothing else
    if (dl == nil) then return; end
    local s = rt.settings;
    local sc = s.scale or 1.0;
    -- the path runs just inside the border (inset = half the comet width) so the window clip keeps it whole
    local ins = 2.0 * sc;
    local r = max(0, (classic and 0 or (s.rounding or 0) * sc) - ins);
    local G = rt.perim;
    if (G.w ~= ww - 2 * ins or G.h ~= wh - 2 * ins or G.r_in ~= r) then
        style.perim_set(G, ww - 2 * ins, wh - 2 * ins, r);
        rt.stats.flash_sets = rt.stats.flash_sets + 1;
    end
    local ox, oy = px + ins, py + ins;
    local L, LAP, PULSE = G.len, style.FLASH_LAP, style.FLASH_PULSE;
    local K = style.FLASH_SEGS;
    local accent = classic and s.col_bar or (th.accent or th.glow);
    -- clipped to the window rect itself
    local clipped = pcall(dl.PushClipRect, dl, vec(V1, px, py), vec(V2, px + ww, py + wh), false);
    local ft = rt.fx.flash_t;
    for i = 1, 2 do
        local t = now - ft[i];
        if (t >= 0 and t < LAP + PULSE) then
            local col = style.mix(FLC[i], classic and (i == 1 and s.col_hp or s.col_mp) or (i == 1 and th.hp or th.mp), accent, 0.35);
            style.mix(col, col, WHITE, 0.2);   -- a touch brighter than the text so it reads on any background
            rt.stats.f_flash = rt.stats.f_flash + 1;
            if (t < LAP) then
                local ph = t / LAP;
                local head = L * style.flash_head(ph);
                local tail = L * style.FLASH_TAIL * min(1, ph * 5);
                if (tail > head) then tail = head; end
                local fade = (ph > 0.85) and (1 - (ph - 0.85) / 0.15 * 0.5) or 1;
                local seg = tail / K;
                local hx, hy = style.perim_at(G, (i == 1) and head or (L - head));
                local ax, ay = hx, hy;
                if (seg > 0) then
                    for k = 1, K do
                        local sb = head - seg * k;
                        local bx, by = style.perim_at(G, (i == 1) and sb or (L - sb));
                        local f = 1 - (k - 1) / K;
                        dl:AddLine(vec(V1, ox + ax, oy + ay), vec(V2, ox + bx, oy + by), u(col, 0.95 * f * f * fade), max(1.0, 4.0 * sc * f));
                        ax, ay = bx, by;
                    end
                end
                dl:AddCircleFilled(vec(V3, ox + hx, oy + hy), 8 * sc, u(col, 0.35 * fade), 16);
                dl:AddCircleFilled(vec(V3, ox + hx, oy + hy), 2.6 * sc, u(WHITE, 0.95 * fade), 12);
            else
                local q = (t - LAP) / PULSE;
                local a = (1 - q) * (1 - q);
                dl:AddRect(vec(V1, ox, oy), vec(V2, ox + G.w, oy + G.h), u(col, 0.85 * a), G.r, 0, 2.0 * sc);
                local g = 2.5 * sc;   -- soft inner glow (inside the window, like the rest of the flash)
                dl:AddRect(vec(V1, ox + g, oy + g), vec(V2, ox + G.w - g, oy + G.h - g), u(col, 0.30 * a), max(0, G.r - g), 0, 3.0 * sc);
            end
        end
    end
    if (clipped) then dl:PopClipRect(); end
end

local function fire_full(stat, now)
    local fe = rt.settings.full_effect;
    if (fe == 'sparkle' or fe == 'both') then
        if (stat == 1) then rt.fx.spark_hp:trigger(now); else rt.fx.spark_mp:trigger(now); end
    end
    if (fe == 'border' or fe == 'both') then rt.fx.flash_t[stat] = now; end
end

local function draw_window(st, ctx, remaining, progress, n, eff_hp, eff_mp)
    local s = rt.settings;
    local th = current_theme();
    local classic = th.classic == true;
    local has_mp = (st.maxmp or 0) > 0;
    -- Per-stat view. The max is never below the current value: HP/MP (party packet) can briefly
    -- read above GetHPMax/GetMPMax (char stats packet), which used to give a negative "+-N" gain.
    local v = rt.view;
    v.mhp = max(st.maxhp or 0, eff_hp or 0);
    v.mmp = has_mp and max(st.maxmp or 0, eff_mp or 0) or 0;
    v.fhp = model.stat_full(eff_hp, v.mhp);
    v.fmp = has_mp and model.stat_full(eff_mp, v.mmp) or false;
    local php, pmp, ghp, gmp = model.project4(n, eff_hp, eff_mp, v.mhp, v.mmp, ctx);
    rt.fx.ghp, rt.fx.gmp = ghp, gmp;
    local sc = s.scale or 1.0;

    local flags = bit.bor(ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoSavedSettings,
                          ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollbar);
    if (not s.show_title) then flags = bit.bor(flags, ImGuiWindowFlags_NoTitleBar); end
    if (s.locked) then flags = bit.bor(flags, ImGuiWindowFlags_NoMove); end

    -- 1.1.2: the saved position is set on EVERY frame, except while the user is dragging this window. ImGui
    -- hands a pending SetNextWindowPos to whichever window begins next, so another addon that set one and then
    -- skipped its own Begin could move Zztick (and pin it there, so it could not be dragged).
    if (rt.apply_pos or not rt.dragging) then
        keep_on_screen(s);
        rt.pos_vec[1], rt.pos_vec[2] = s.x, s.y;
        imgui.SetNextWindowPos(rt.pos_vec, ImGuiCond_Always);
        rt.apply_pos = false;
    end
    -- Fixed width (from the widest possible content); height auto-fits a fixed line count.
    if (rt.lvalid) then
        WSIZE[1], WSIZE[2] = rt.L.w, 0;
        imgui.SetNextWindowSize(WSIZE, ImGuiCond_Always);
    end
    imgui.SetNextWindowBgAlpha(s.bg_alpha);
    rt.main_open[1] = true;

    local nvars, ncols = 1, 0;
    imgui.PushStyleVar(SV_ALPHA, max(0.001, rt.fx.alpha));
    local extra_y = (s.row_pad or 0) * sc;
    if (extra_y > 0) then
        SPACEV[1], SPACEV[2] = rt.style_spacing_x or 8, (rt.style_spacing_y or 4) + extra_y;
        imgui.PushStyleVar(SV_SPACING, SPACEV);
        nvars = nvars + 1;
    end
    if (not classic) then
        local pad = floor(10 * sc + 0.5);
        PADV[1], PADV[2] = pad, floor(8 * sc + 0.5);
        imgui.PushStyleVar(SV_PADDING, PADV);
        imgui.PushStyleVar(SV_ROUNDING, (s.rounding or 0) * sc);
        imgui.PushStyleVar(SV_BORDER, 1);
        imgui.PushStyleColor(COL_WINDOWBG, th.bg);
        imgui.PushStyleColor(COL_BORDER, th.border);
        nvars, ncols = nvars + 3, 2;
    end

    local title = rt.test_mode and not rt.resting_now and 'Zztick (test)###zztick_main' or 'Zztick###zztick_main';
    if (imgui.Begin(title, rt.main_open, flags)) then
        WR.in_win = true;
        rt.in_main = true;
        capture_window_rect(classic);
        local pushed = push_font();
        local fb, ol = faux_bold(), s.font_outline;
        if (layout_stale(has_mp)) then rebuild_layout(classic, has_mp); end
        imgui.PushStyleColor(ImGuiCol_Text, classic and s.col_text or th.text);

        if (classic) then
            draw_classic_body(st, ctx, remaining, progress, n, eff_hp, eff_mp, php, pmp, ghp, gmp, has_mp, fb, ol);
        else
            draw_theme_body(th, st, ctx, remaining, progress, n, eff_hp, eff_mp, php, pmp, ghp, gmp, has_mp, fb, ol);
        end

        imgui.PopStyleColor(1);
        if (pushed == 1) then imgui.PopFont(); end

        finish_window_rect();
        if (not classic and WR.ok and FX.rested_active(rt.now, rt.fx.rested_at)) then
            local wdl = imgui.GetWindowDrawList();
            if (wdl ~= nil) then
                local clipped = pcall(wdl.PushClipRect, wdl, vec(V1, WR.x, WR.y), vec(V2, WR.x + WR.w, WR.y + WR.h), false);
                FX.window_glint(wdl, WR.x, WR.y, WR.x + WR.w, WR.y + WR.h, rt.now - rt.fx.rested_at, th.accent or th.glow);
                if (clipped) then wdl:PopClipRect(); end
            end
        end
        local fe = s.full_effect;
        if (s.animate and (fe == 'border' or fe == 'both' or s.tick_border) and flash_active(rt.now)) then draw_flash(th, classic, rt.now); end
        if (rt.flash_dbg_want) then rt.flash_dbg_want = false; flash_debug_print(); end

        -- Dragging (1.1.2): only a drag that starts with a click on this window (unlocked) moves it; the new
        -- position is read only during that drag and saved once it stops (debounced). Position is ImGui's own
        -- window position (the same value SetNextWindowPos takes), so it round-trips exactly.
        local okd, down = pcall(imgui.IsMouseDown, 0);
        down = okd and down == true;
        if (s.locked or not down) then
            rt.dragging = false;
        elseif (not rt.dragging) then
            local okc, clicked = pcall(imgui.IsMouseClicked, 0);
            local okh, hovered = pcall(imgui.IsWindowHovered);
            rt.dragging = okc and clicked == true and okh and hovered == true;
        end
        if (rt.dragging) then
            local px, py = read_xy(imgui.GetWindowPos);
            if (finite(px) and finite(py) and (abs(px - s.x) >= 1 or abs(py - s.y) >= 1)) then
                s.x = floor(px);
                s.y = floor(py);
                mark_dirty(rt.now);
            end
        end
    end
    WR.in_win = false;
    rt.in_main = false;
    imgui.End();
    if (ncols > 0) then imgui.PopStyleColor(ncols); end
    imgui.PopStyleVar(nvars);
end

local function draw_debug()
    local st = rt.stats;
    local c = rt.sc.dbg;
    local gc = floor(collectgarbage('count'));
    local a, p = floor(st.avg_ms * 1000), floor(st.peak_ms * 1000);
    if (c.k1 ~= a or c.k2 ~= p or c.k3 ~= st.gear_scans + st.buff_scans * 100000 or c.k4 ~= gc or c.k5 ~= st.saves) then
        c.k1, c.k2, c.k3, c.k4, c.k5 = a, p, st.gear_scans + st.buff_scans * 100000, gc, st.saves;
        c.s = sformat('Zztick: %.3f ms/frame avg, %.3f ms peak (last 1s)\ngear checks %d, item parses %d, buff scans %d, saves %d\nLua memory %d KB  fonts loaded %d  tick #%d  resyncs %d',
            st.avg_ms, st.peak_ms, st.gear_scans, st.item_parses, st.buff_scans, st.saves, gc, zzfonts.load_count,
            rt.tracker.next_n, rt.tracker.resyncs);
    end
    imgui.SetNextWindowBgAlpha(0.6);
    if (imgui.Begin('Zztick debug###zztick debug', rt.debug_open, bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
        imgui.Text(c.s);
    end
    imgui.End();
    if (rt.debug_open[1] == false) then rt.debug = false; end
end

--[[
* Chime (v1.4.0). Ashita v4: ashita.misc.play_sound(path) = PlaySoundA(SND_FILENAME | SND_ASYNC):
* .wav only, async, no volume control (the bundled chimes are pre-scaled quiet).
--]]
local function sounds_dir()
    return model.sound_path(addon.path, '');
end
local function sound_file(name)
    if (type(name) ~= 'string' or name == '') then name = 'chime_soft.wav'; end
    return model.sound_path(addon.path, name);
end

local function scan_sounds()
    local list = {};
    local ok, files = pcall(function () return ashita.fs.get_dir(sounds_dir(), '.*.wav', false); end);
    if (ok and type(files) == 'table') then
        local seen = {};
        for _, f in pairs(files) do
            if (type(f) == 'string' and f:lower():match('%.wav$')) then
                local name = f:match('[^\\/]+$');
                -- one entry per file name (Windows names are case-insensitive)
                if (name ~= nil and name ~= '' and name:sub(1, 5) ~= '_vol_' and not seen[name:lower()]) then seen[name:lower()] = true; list[#list + 1] = name; end
            end
        end
    end
    if (#list == 0) then list = { 'chime_soft.wav', 'chime_bell.wav' }; end
    table.sort(list, function (a, b) return a:lower() < b:lower(); end);
    rt.sounds = list;
    return list;
end

-- winmm PlaySoundA through LuaJIT ffi (fallback). Loaded once; rt.winmm can be injected by tests.
local SND_ASYNC, SND_NODEFAULT, SND_FILENAME = 0x0001, 0x0002, 0x00020000;
local function winmm()
    if (rt.winmm == nil) then
        local ok, lib = pcall(function ()
            local ffi = require('ffi');
            if (not rt.ffi_cdef) then
                ffi.cdef('int __stdcall PlaySoundA(const char *pszSound, void *hmod, unsigned int fdwSound);');
                rt.ffi_cdef = true;
            end
            return ffi.load('winmm');
        end);
        rt.winmm = ok and lib or false;
        rt.winmm_err = (not ok) and tostring(lib) or nil;
    end
    return rt.winmm or nil, rt.winmm_err;
end

--[[
* Plays a .wav. Returns ok, method, detail.
*   ashita: ashita.misc.play_sound(path) = PlaySoundA(SND_FILENAME | SND_ASYNC), returns nothing.
*   winmm:  PlaySoundA(path, NULL, SND_FILENAME | SND_ASYNC | SND_NODEFAULT) via ffi, returns BOOL.
* 'auto' uses Ashita and falls back to winmm when play_sound is missing or raises an error.
--]]
local function play_file(path)
    local backend = rt.settings.chime_backend or 'auto';
    local why = nil;
    if (backend ~= 'winmm') then
        local ps = (type(ashita) == 'table' and type(ashita.misc) == 'table') and ashita.misc.play_sound or nil;
        if (type(ps) == 'function') then
            local ok, e = pcall(ps, path);
            if (ok) then return true, 'ashita.misc.play_sound', 'called (returns nothing)'; end
            why = 'ashita.misc.play_sound error: ' .. tostring(e);
        else
            why = 'ashita.misc.play_sound is not available (' .. type(ps) .. ')';
        end
        if (backend == 'ashita') then return false, 'ashita.misc.play_sound', why; end
    end
    local lib, lerr = winmm();
    if (lib == nil) then return false, 'winmm PlaySoundA', (why and (why .. '; ') or '') .. 'winmm unavailable: ' .. tostring(lerr); end
    local ok, r = pcall(function () return lib.PlaySoundA(path, nil, SND_FILENAME + SND_ASYNC + SND_NODEFAULT); end);
    if (not ok) then return false, 'winmm PlaySoundA', (why and (why .. '; ') or '') .. 'PlaySoundA error: ' .. tostring(r); end
    r = tonumber(r) or 0;
    return r ~= 0, 'winmm PlaySoundA', (why and (why .. '; ') or '') .. 'PlaySoundA returned ' .. r;
end

-- Volume: PlaySound has no volume control, so a scaled copy of the .wav is written once per file and
-- volume (TEMP, else sounds/_vol_*.wav) and played instead. Copies are removed again on unload.
rt.vol_files, rt.vol_made = {}, {};
local function scaled_sound(path, vol)
    local key = path .. '|' .. vol;
    local c = rt.vol_files[key];
    if (c ~= nil) then
        if (c.path ~= nil) then return c.path; end
        return nil, c.why;
    end
    local function fail(why) rt.vol_files[key] = { why = why }; return nil, why; end
    local f = io.open(path, 'rb');
    if (f == nil) then return fail('file not found'); end
    local bytes = f:read('*a');
    f:close();
    local out, why = model.wav_scale(bytes, model.volume_gain(vol));
    if (out == nil) then return fail(why); end
    local base = (path:match('([^\\/]+)%.[Ww][Aa][Vv]$') or 'chime');
    local tmp = os.getenv('TEMP') or os.getenv('TMP');
    local dest;
    if (tmp ~= nil and tmp ~= '') then dest = tmp:gsub('[\\/]+$', '') .. '\\zztick_' .. base .. '_' .. vol .. '.wav';
    else dest = sounds_dir() .. '_vol_' .. base .. '_' .. vol .. '.wav'; end
    local w = io.open(dest, 'wb');
    if (w == nil) then return fail('could not write ' .. dest); end
    w:write(out);
    w:close();
    rt.vol_files[key] = { path = dest };
    rt.vol_made[#rt.vol_made + 1] = dest;
    return dest;
end

local function play_chime()
    rt.stats.chimes = (rt.stats.chimes or 0) + 1;
    local vol = floor((tonumber(rt.settings.chime_volume) or 100) + 0.5);
    if (vol <= 0) then
        rt.chime_last = { ok = true, method = 'muted', detail = 'volume is 0' };
        return true, 'muted', 'volume is 0';
    end
    local path, note = sound_file(rt.settings.chime_sound), nil;
    if (vol ~= 100) then
        local p2, why = scaled_sound(path, vol);
        if (p2 ~= nil) then path = p2; else note = 'volume not applied (' .. tostring(why) .. ')'; end
    end
    local ok, method, detail = play_file(path);
    if (note ~= nil) then detail = note .. '; ' .. tostring(detail); end
    rt.chime_last = { ok = ok, method = method, detail = detail };
    return ok, method, detail;
end

-- /zztick chime test: always plays (whether the chime is on or off) and prints what happened.
local function chime_test()
    local s = rt.settings;
    local path = sound_file(s.chime_sound);
    msg('Chime test: ' .. path);
    local f = io.open(path, 'rb');
    if (f == nil) then
        err('  file: NOT FOUND (is the sounds folder in addons\\zztick\\?)');
    else
        local size = f:seek('end') or 0;
        f:seek('set', 0);
        local head = f:read(4096) or '';
        f:close();
        local w = model.wav_info(head);
        if (w.ok) then
            msg(sformat('  file: found, %d bytes, PCM %d-bit, %d ch, %d Hz', size, w.bits, w.channels, w.rate));
        else
            err(sformat('  file: found, %d bytes, but not a plain PCM .wav (%s)', size, tostring(w.why)));
        end
    end
    local ok, method, detail = play_chime();
    if (ok) then msg('  played via ' .. method .. ': ' .. tostring(detail));
    else err('  NOT played via ' .. method .. ': ' .. tostring(detail)); end
    msg(sformat('  volume %d%%', floor((tonumber(s.chime_volume) or 100) + 0.5)));
    msg(sformat('  full-heal chime is %s, mode %s%s', s.chime_enabled and 'ON' or 'OFF', tostring(s.chime_mode),
        s.chime_enabled and '' or ' (turn on: /zztick chime on)'));
end

local function find_sound(q)
    q = q:lower();
    for _, f in ipairs(rt.sounds or scan_sounds()) do
        local l = f:lower();
        if (l == q or l == q .. '.wav') then return f; end
    end
    return nil;
end

--[[
* Config window helpers. Settings hold plain values; imgui wants table refs.
--]]
local ref = { false };
--[[
* Unique widget IDs (v1.4.6). ImGui identifies widgets by label, and the config window had the
* same label twice in one ID scope: the "Sound" header and the "Sound" combo, and "HP"/"MP" under
* Lines and under Colors. ImGui 1.91+ reports that as "2 visible items with conflicting ID".
* Every setting widget now gets "##<settings key>" (cached, built once), and list items get PushID.
--]]
local IDL = {};
local function uid(label, key)
    local c = IDL[key];
    if (c == nil or c.l ~= label) then c = { l = label, s = label .. '##' .. key }; IDL[key] = c; end
    return c.s;
end
local HAS_PUSHID = type(imgui.PushID) == 'function' and type(imgui.PopID) == 'function';
-- One list entry inside a combo: its own ID scope (index), so equal names can never clash.
local function list_item(i, label, selected)
    if (HAS_PUSHID) then
        imgui.PushID(i);
        local ok, r = pcall(imgui.Selectable, label, selected);
        imgui.PopID();
        if (not ok) then error(r, 0); end
        return r;
    end
    return imgui.Selectable(label .. '##' .. i, selected);
end
local function cfg_check(label, key)
    ref[1] = rt.settings[key];
    if (imgui.Checkbox(uid(label, key), ref)) then rt.settings[key] = ref[1]; mark_dirty(); return true; end
    return false;
end

local function cfg_float(label, key, lo, hi, fmt)
    ref[1] = rt.settings[key];
    if (imgui.SliderFloat(uid(label, key), ref, lo, hi, fmt or '%.2f')) then rt.settings[key] = ref[1]; mark_dirty(); return true; end
    return false;
end

local function cfg_int(label, key, lo, hi)
    ref[1] = rt.settings[key];
    if (imgui.InputInt(uid(label, key), ref)) then
        local n = floor(ref[1]);
        if (lo ~= nil and n < lo) then n = lo; end
        if (hi ~= nil and n > hi) then n = hi; end
        rt.settings[key] = n;
        mark_dirty();
        return true;
    end
    return false;
end

local function cfg_slider_int(label, key, lo, hi)
    ref[1] = rt.settings[key];
    if (imgui.SliderInt(uid(label, key), ref, lo, hi, '%d px')) then
        rt.settings[key] = max(lo, min(hi, floor(ref[1] + 0.5)));
        mark_dirty();
        return true;
    end
    return false;
end

local function cfg_color(label, key)
    local c = rt.settings[key];
    local v = { c[1], c[2], c[3], c[4] };
    if (imgui.ColorEdit4(uid(label, key), v)) then
        rt.settings[key] = T{ v[1], v[2], v[3], v[4] };
        mark_dirty();
    end
end

local function font_combo(label, key)
    local s = rt.settings;
    if (imgui.BeginCombo(uid(label, key), tostring(s[key] or zzfonts.DEFAULT))) then
        for i, f in ipairs(rt.font_list or {}) do
            if (list_item(i, tostring(f.name), f.name == s[key])) then
                s[key] = f.name; mark_dirty(); rt.font_want = true;
            end
        end
        imgui.EndCombo();
    end
end

local function draw_font_section()
    local s = rt.settings;
    if (rt.font_list == nil) then rt.font_list = zzfonts.scan(addon.path); end
    if (not zzfonts.supported()) then
        imgui.TextDisabled('This Ashita build cannot load fonts at runtime');
        imgui.TextDisabled('(needs imgui.AddFontFromFileTTF, Ashita v4.3+). Size/scale still work.');
    end
    font_combo('Body font', 'font_name');
    if (current_theme().classic ~= true) then
        font_combo('Title font', 'title_font');
        font_combo('Numbers font', 'num_font');
        imgui.ShowHelp('The countdown is drawn in fixed digit cells, so it stays put with any font. A monospace font (JetBrains Mono) also keeps the HP/MP numbers steady.', true);
    end
    if (cfg_int('Font size (0 = default)', 'font_size', 0, 72)) then end
    if (cfg_check('Bold', 'font_bold')) then rt.font_want = true; end
    imgui.ShowHelp('Uses the font\'s bold file when it has one, otherwise draws the text twice 1px apart.', true);
    cfg_check('Outline', 'font_outline');
    if (s.font_outline) then cfg_color('Outline color', 'col_outline'); end
    if (imgui.Button('Rescan fonts')) then rt.font_list = nil; rt.font_want = true; end
    imgui.ShowHelp('Drop .ttf or .otf files into addons\\zztick\\fonts\\ and press Rescan.', true);
    if (rt.font_status ~= '') then imgui.TextColored(WARN_COLOR, rt.font_status); end
end

local COL_TEXT  = rawget(_G, 'ImGuiCol_Text') or 0;
local COL_CHECK = rawget(_G, 'ImGuiCol_CheckMark') or 18;
local PREVIEW_COL = { 1.0, 0.80, 0.25, 1.0 };
local CFG_TABS;
do   -- scoped: keeps the main chunk under Lua's 200-locals limit
-- Preview helpers for the Effects tab: start the preview window if nothing is showing, then replay.
local function ensure_preview()
    if (not rt.test_mode and not rt.resting_now) then
        rt.test_mode, rt.test_start, rt.test_sync = true, rt.clock(), nil;
    end
end
local function replay_tick()
    ensure_preview();
    local fx, t = rt.fx, rt.clock();
    fx.pop_at, fx.pop_hp, fx.pop_mp, fx.pop_whp, fx.pop_wmp = t, model.fmt_gain(max(fx.ghp, 1)), model.fmt_gain(max(fx.gmp, 1)), -1, -1;
    fx.sweep_at = t;
    if (rt.settings.tick_border) then fx.flash_t[1] = t; end
end
local function replay_rested()
    ensure_preview();
    rt.fx.rested_at = rt.clock();
end
local function replay_full()
    ensure_preview();
    local t = rt.clock();
    local fe = rt.settings.full_effect;
    if (fe == 'sparkle' or fe == 'both') then rt.fx.spark_hp:trigger(t); rt.fx.spark_mp:trigger(t); end
    if (fe == 'border' or fe == 'both') then rt.fx.flash_t[1], rt.fx.flash_t[2] = t, t; end
end

local function cfg_combo(label, key, list)
    local s = rt.settings;
    if (imgui.BeginCombo(uid(label, key), tostring(s[key]))) then
        for i, v in ipairs(list) do
            if (list_item(i, v, v == s[key])) then s[key] = v; mark_dirty(); end
        end
        imgui.EndCombo();
    end
end

local OPEN = ImGuiTreeNodeFlags_DefaultOpen;
local FX_LEVELS = { 'off', 'subtle', 'full' };

-- General: the window and what it shows.
local function cfg_tab_general()
    local s = rt.settings;
    if (imgui.CollapsingHeader('Window', OPEN)) then
        cfg_check('Lock position', 'locked');
        cfg_check('Show title bar', 'show_title');
        cfg_check('Compact mode', 'compact');
        cfg_float('Scale', 'scale', 0.5, 3.0, '%.2f');
        cfg_float('Background opacity', 'bg_alpha', 0.0, 1.0, '%.2f');
        cfg_float('Bar height', 'bar_height', 2, 30, '%.0f');
        cfg_slider_int('Line padding (px)', 'row_pad', 0, 5);
        imgui.ShowHelp('Extra vertical space between the lines of the window.', true);
        cfg_slider_int('Width (px, 0 = auto)', 'width', 0, 800);
        imgui.ShowHelp('The window keeps a fixed size sized for the widest possible numbers. Set a width to override it (narrower clips). Compact mode ignores it and fits its one row; turning compact off brings this width back.', true);
        if (rt.lvalid) then imgui.TextDisabled(sformat('  Auto width: %d px', rt.L.need_w or 0)); end
        if (cfg_int('Position X', 'x')) then rt.apply_pos = true; end
        if (cfg_int('Position Y', 'y')) then rt.apply_pos = true; end
    end
    if (imgui.CollapsingHeader('Lines', OPEN)) then
        cfg_check('Countdown', 'show_timer');
        cfg_check('Progress bar', 'show_bar');
        cfg_check('HP', 'show_hp');
        cfg_check('MP', 'show_mp');
        cfg_check('Gain amounts (+N)', 'show_gain');
        cfg_check('Tick number', 'show_tick_no');
        cfg_check('Ticks / time to full', 'show_full');
        cfg_check('Food and its bonus', 'show_food');
        imgui.ShowHelp('A line with the food you ate and the healing bonus it adds, while the Food effect lasts. Hover it for the bonus breakdown.', true);
        cfg_check('Food messages in chat', 'food_chat');
        imgui.ShowHelp('Off: eating only updates the food line in this window. On: also a chat line when you eat.', true);
        cfg_check('Level Sync badge ("Synced Lv NN")', 'show_sync');
        cfg_check('Last observed gain (diagnostic)', 'show_last');
    end
end

-- Style: theme, glyphs, colors, fonts.
local function cfg_tab_style()
    local s = rt.settings;
    if (imgui.CollapsingHeader('Theme', OPEN)) then
        if (imgui.BeginCombo(uid('Theme', 'theme'), current_theme().name)) then
            for i, t in ipairs(style.THEMES) do
                if (list_item(i, t.name, t.name == current_theme().name)) then s.theme = t.name; mark_dirty(); end
            end
            imgui.EndCombo();
        end
        imgui.ShowHelp('Classic is the original plain look and uses the colors below.', true);
        if (current_theme().classic ~= true) then
            cfg_float('Corner rounding', 'rounding', 0, 16, '%.0f');
            cfg_check('HP/MP mini bars', 'show_minibars');
            cfg_check('HP/MP icons (heart / droplet)', 'show_icons');
        end
    end
    if (imgui.CollapsingHeader('Font', OPEN)) then
        draw_font_section();
    end
    if (current_theme().classic == true and imgui.CollapsingHeader('Colors (Classic theme)', OPEN)) then
        cfg_color('Text', 'col_text');
        cfg_color('Timer', 'col_timer');
        cfg_color('HP', 'col_hp');
        cfg_color('MP', 'col_mp');
        cfg_color('Bar', 'col_bar');
        cfg_color('Bar background', 'col_bar_bg');
    end
end

-- Effects: everything that moves.
local function cfg_tab_effects()
    local s = rt.settings;
    if (imgui.CollapsingHeader('Effects level', OPEN)) then
        imgui.Text('Level:');
        for _, lv in ipairs(FX_LEVELS) do
            imgui.SameLine();
            if (imgui.RadioButton(lv:sub(1, 1):upper() .. lv:sub(2) .. '##fxlvl_' .. lv, s.fx_level == lv)) then s.fx_level = lv; mark_dirty(); end
        end
        imgui.ShowHelp('Off: none of the effects below. Subtle: softer charge-up, tick glint and number roll only. Full: everything that is ticked.', true);
        cfg_float('Effect strength', 'fx_strength', 0.1, 1.0, '%.2f');
        cfg_check('Animations (smooth bar, last-second glow, +gain pop)', 'animate');
        imgui.ShowHelp('Everything on this tab moves, so it needs Animations.', true);
        cfg_int('Fade in/out (ms, 0 = off)', 'fade_ms', 0, 1000);
        if (not s.animate) then imgui.TextColored(WARN_COLOR, '  Animations are off: no effects will show.'); end
    end
    if (imgui.CollapsingHeader('Bar', OPEN)) then
        cfg_check('Moving shine (full)', 'fx_bar_shine');
        if (s.fx_bar_shine) then cfg_float('Seconds between shines', 'fx_shine_period', 2.0, 60.0, '%.0f'); end
        cfg_check('Leading-edge spark (full)', 'fx_bar_spark');
        if (s.fx_bar_spark) then
            cfg_float('Spark size', 'fx_spark_size', 0.10, 1.0, '%.2f');
            cfg_float('Spark strength', 'fx_spark_strength', 0.10, 1.0, '%.2f');
        end
        cfg_check('Charge-up (last 3 seconds)', 'fx_charge');
        imgui.ShowHelp('The bar warms and a soft halo grows around it as the tick gets close.', true);
    end
    if (imgui.CollapsingHeader('On every tick', OPEN)) then
        cfg_check('Glint across the row that gained', 'fx_glint');
        cfg_check('Heart / droplet pop (full)', 'fx_pop');
        cfg_check('Numbers roll up to the new value', 'fx_roll');
        cfg_check('Border comet on every tick', 'tick_border');
        imgui.ShowHelp('A bright streak runs once around the window border. HP clockwise.', true);
    end
    if (imgui.CollapsingHeader('Resting and full', OPEN)) then
        cfg_check('Breathing moon and floating z\'s (full)', 'fx_sleep');
        cfg_check('Fully rested: line, glint and stars', 'fx_rested');
        imgui.ShowHelp('When HP and MP are both full the status line reads "Fully rested". With full effects a soft glint crosses the window and stars twinkle by the text.', true);
        cfg_combo('When HP or MP reaches full', 'full_effect', style.FULL_EFFECTS);
        imgui.ShowHelp('border = a comet runs around the window border, sparkle = stars on the row, both, or off.', true);
    end
    if (imgui.CollapsingHeader('Preview', OPEN)) then
        if (imgui.Button('Replay tick')) then replay_tick(); end
        imgui.SameLine();
        if (imgui.Button('Replay fully rested')) then replay_rested(); end
        imgui.SameLine();
        if (imgui.Button('Replay full border/sparkle')) then replay_full(); end
        imgui.ShowHelp('Starts the preview window if nothing is showing.', true);
    end
end

local function cfg_tab_sound()
    local s = rt.settings;
    if (cfg_check('Chime when fully healed', 'chime_enabled')) then s.chime_choice = true; end
    cfg_combo('When', 'chime_mode', model.CHIME_MODES);
    imgui.ShowHelp('both = HP and MP full, any = either one, hp / mp = only that stat. Plays once per rest.', true);
    if (imgui.BeginCombo(uid('Sound', 'chime_sound'), tostring(s.chime_sound))) then
        for i, f in ipairs(rt.sounds or scan_sounds()) do
            if (list_item(i, f, f == s.chime_sound)) then s.chime_sound = f; mark_dirty(); end
        end
        imgui.EndCombo();
    end
    cfg_float('Volume', 'chime_volume', 0, 200, '%.0f%%');
    imgui.ShowHelp('100% plays the file as it is, 0% is silent, above 100% is louder (can clip). Applied to the sound itself, so the game volume is not touched.', true);
    if (imgui.Button('Test chime')) then chime_test(); end
    imgui.SameLine();
    if (imgui.Button('Rescan sounds/')) then scan_sounds(); end
    cfg_check('Also when sitting down already full', 'chime_sit_full');
end

local function cfg_tab_recovery()
    local s = rt.settings;
    if (imgui.CollapsingHeader('Bonuses', OPEN)) then
        cfg_int('Bonus HP per tick', 'bonus_hp', -100, 500);
        imgui.ShowHelp('Extra "HP recovered while healing" not detected from gear (food, conditional/latent gear).', true);
        cfg_int('Bonus MP per tick', 'bonus_mp', -100, 500);
        imgui.ShowHelp('Extra "MP recovered while healing" not detected from gear (food, conditional/latent gear).', true);
        if (cfg_check('Read healing bonuses from equipped gear', 'auto_gear')) then rt.gear.force = true; end
        if (s.auto_gear) then
            imgui.TextDisabled(sformat('  Gear detected: %s HP, %s MP', model.fmt_bonus(rt.gear.hp), model.fmt_bonus(rt.gear.mp)));
        end
        cfg_check('Count healing bonus from food you eat', 'auto_food');
        imgui.ShowHelp('Seen when you eat (food eaten before the addon loaded cannot be seen: use the bonus boxes above). Lasts while the Food effect does.', true);
        if (s.auto_food) then
            local f = rt.food;
            imgui.TextDisabled((f.id ~= 0) and sformat('  Food: %s (%s HP, %s MP)', f.name, model.fmt_bonus(f.hp), model.fmt_bonus(f.mp)) or '  Food: none seen');
        end
    end
    if (imgui.CollapsingHeader('Rules', OPEN)) then
        imgui.Text('Signet/Sigil bonus:');
        imgui.SameLine();
        if (imgui.RadioButton('Auto##sig', s.signet_mode == 0)) then s.signet_mode = 0; mark_dirty(); end
        imgui.SameLine();
        if (imgui.RadioButton('Always##sig', s.signet_mode == 1)) then s.signet_mode = 1; mark_dirty(); end
        imgui.SameLine();
        if (imgui.RadioButton('Never##sig', s.signet_mode == 2)) then s.signet_mode = 2; mark_dirty(); end
        imgui.Text('Server rules:');
        imgui.SameLine();
        if (imgui.RadioButton('Retail##prof', s.profile == 'retail')) then s.profile, s.profile_choice = 'retail', true; mark_dirty(); end
        imgui.SameLine();
        if (imgui.RadioButton('LandSandBoat (private)##prof', s.profile ~= 'retail')) then s.profile, s.profile_choice = 'lsb', true; mark_dirty(); end
        cfg_int('BLU Clear Mind tier (0-6)', 'blu_cm_tier', 0, 6);
    end
end

CFG_TABS = {
    { 'General##zz_general', cfg_tab_general },
    { 'Style##zz_style', cfg_tab_style },
    { 'Effects##zz_effects', cfg_tab_effects },
    { 'Sound##zz_sound', cfg_tab_sound },
    { 'Recovery##zz_recovery', cfg_tab_recovery },
};
end

local function draw_config()
    if (not rt.config_open[1]) then
        -- closing the settings also ends the preview
        if (rt.cfg_was_open) then
            rt.cfg_was_open = false;
            if (rt.test_mode) then rt.test_mode = false; end
        end
        return;
    end
    rt.cfg_was_open = true;
    imgui.SetNextWindowSize({ 440, 560 }, ImGuiCond_FirstUseEver);
    if (imgui.Begin('Zztick config###zztick config', rt.config_open)) then
        local preview = { rt.test_mode };
        imgui.PushStyleColor(COL_TEXT, PREVIEW_COL);
        imgui.PushStyleColor(COL_CHECK, PREVIEW_COL);
        local changed = imgui.Checkbox('Show preview window (test mode)', preview);
        imgui.PopStyleColor(2);
        if (changed) then
            rt.test_mode = preview[1];
            rt.test_start = rt.now;
        end
        imgui.ShowHelp('Shows a sample window so you can see changes while standing. It turns off when this window closes.', true);
        imgui.Separator();

        if (imgui.BeginTabBar ~= nil and imgui.BeginTabItem ~= nil) then
            if (imgui.BeginTabBar('##zz_tabs')) then
                for _, t in ipairs(CFG_TABS) do
                    if (imgui.BeginTabItem(t[1])) then t[2](); imgui.EndTabItem(); end
                end
                imgui.EndTabBar();
            end
        else
            for _, t in ipairs(CFG_TABS) do   -- older builds without tab bars: one collapsible block per tab
                if (imgui.CollapsingHeader(t[1])) then t[2](); end
            end
        end

        imgui.Separator();
        if (imgui.Button('Save')) then save_now(); msg('Settings saved.'); end
        imgui.SameLine();
        if (imgui.Button('Reset to defaults')) then
            reset_settings();
            invalidate_caches();
            rebuild_tracker();
            msg('Settings reset to defaults.');
        end
    end
    imgui.End();
end

--[[
* Help
--]]
local function print_help()
    msg('Commands:');
    local cmds = {
        { '/zztick config', 'Settings window (tabs: General, Style, Effects, Sound, Recovery).' },
        { '/zztick test', 'Toggle a preview window for positioning (works while standing).' },
        { '/zztick lock | unlock', 'Lock or unlock the window position.' },
        { '/zztick theme <name>', style.theme_list() .. ' (short names work: ember, bastok...).' },
        { '/zztick effects off|subtle|full', 'How much polish is drawn (bar shine, glints, pops...).' },
        { '/zztick chime on | off | test', 'Soft chime when fully healed (once per rest).' },
        { '/zztick info', 'Print what the tick formula is using (job, gear and food bonuses...).' },
        { '/zztick reset', 'Reset settings to defaults.' },
    };
    for _, c in ipairs(cmds) do
        print(chat.header(addon.name):append(chat.success(c[1])):append(chat.message(' - ' .. c[2])));
    end
    msg('Everything else (scale, fonts, sound, food, bonuses, effects) is in /zztick config.');
end

--[[
* Events
--]]
ashita.events.register('load', 'zztick_load', function ()
    rt.apply_pos = true;
    rt.font_want = true;
end);

ashita.events.register('unload', 'zztick_unload', function ()
    if (rt.dirty) then save_now(); end
    for _, p in ipairs(rt.vol_made or {}) do pcall(os.remove, p); end   -- scaled chime copies
end);

-- Equipment / buff packets just flag a re-check for the next throttled refresh.
ashita.events.register('packet_in', 'zztick_packet_in', function (e)
    local id = e.id;
    if (id == 0x000A) then rt.tracker:forget_phase(); end   -- the 3 s effect-check grid is per zone
    if (id == 0x0050 or id == 0x0116 or id == 0x0117) then
        rt.gear.force = true;
    elseif (id == 0x0063 or id == 0x0037) then
        rt.buffs.next_check = 0;
    elseif (id == 0x000A or id == 0x0061 or id == 0x001B or id == 0x00DD or id == 0x00DF) then
        rt.jobs.next_check = 0;   -- zone in / char stats / job info / party member (sync level)
    end
end);

--[[
* Server tick reports. The server sends the player's HP/MP in packet 0x00DF whenever they change.
* Judging that packet (with its true arrival time) instead of only polling memory once per frame
* makes the tick sync independent of frame rate and lets the tracker reject non-tick heals.
* Layout assumed: +0x04 uint32 id, +0x08 uint32 HP, +0x0C uint32 MP (verify with /zztick debug).
--]]
rt.sync = { active = false, tick_at = -1e9, accepted = 0, seen = 0 };

ashita.events.register('packet_in', 'zztick_tick_report', function (e)
    if (e.id ~= 0x00DF) then return; end
    local ffi = require('ffi');
    local party = AshitaCore:GetMemoryManager():GetParty();
    local p = ffi.cast('uint8_t*', e.data_raw);
    if (ffi.cast('uint32_t*', p + 0x04)[0] ~= party:GetMemberServerId(0)) then return; end   -- self only

    local hp = ffi.cast('uint32_t*', p + 0x08)[0];
    local mp = ffi.cast('uint32_t*', p + 0x0C)[0];
    local now = rt.clock();
    rt.sync.seen = rt.sync.seen + 1;
    if (rt.debug) then
        msg(sformat('0x00DF self HP %d MP %d (client memory still %d/%d)', hp, mp, party:GetMemberHP(0), party:GetMemberMP(0)));
    end

    local st = rt.st;
    if (rt.tracker:report(now, hp, mp, st.maxhp, st.maxmp, rt.ctx)) then
        local s = rt.sync;
        s.active, s.tick_at, s.accepted = true, now, s.accepted + 1;
    end
end);

--[[
* Eating. The buff list only says 'Food' (251), not which food, so the item is read when you use it:
*   - incoming action packet 0x0028 (your own action, category 5 or 9, param = item id), and
*   - outgoing item-use packet 0x0037 (the inventory slot is looked up).
* The item becomes a candidate; it is committed as your food once the Food effect shows up in the buff
* list (within ~20 s), and its "HP / MP recovered while healing +N" lines (anywhere in the description)
* count while the effect lasts. Food eaten before the addon loaded cannot be seen: use the bonus boxes.
* /zztick food debug prints what these packets contain, to help when a food is not picked up.
--]]
rt.food_pending = nil;
rt.food_dbg = false;
rt.food_candidate = function (id, how)
    local s = rt.settings;
    if (s == nil or not s.auto_food or type(id) ~= 'number' or id <= 0 or id >= 65535) then return; end
    local r = AshitaCore:GetResourceManager():GetItemById(id);
    if (r == nil) then return; end
    local desc = (r.Description ~= nil) and r.Description[1] or '';
    local nm = (r.Name ~= nil and r.Name[1]) or ('item ' .. id);
    local h, m = model.parse_heal_bonus(desc, true);
    local p = rt.food_pending;
    if (p ~= nil and p.id == id and rt.clock() - p.at < 10) then return; end   -- both packets for the same use
    if (rt.food.id == id and rt.clock() - rt.food.set_at < 10) then return; end   -- already committed from the other packet
    rt.food_pending = { id = id, name = nm, hp = h, mp = m, at = rt.clock() };
    rt.buffs.next_check = 0;
    if (rt.food_dbg) then
        msg(sformat('Food debug (%s): item %d "%s" -> +%d HP / +%d MP healing. Description: %s', how, id, nm, h, m,
            tostring(desc):gsub('[\r\n]+', ' / '):sub(1, 160)));
    end
end
ashita.events.register('packet_in', 'zztick_food', function (e)
    if (e.id ~= 0x0028) then return; end
    pcall(function ()
        local party = AshitaCore:GetMemoryManager():GetParty();
        local actor = ashita.bits.unpack_be(e.data_raw, 0, 40, 32);
        if (actor ~= party:GetMemberServerId(0)) then return; end
        local cat = ashita.bits.unpack_be(e.data_raw, 0, 82, 4);
        local param = ashita.bits.unpack_be(e.data_raw, 0, 86, 16);
        if (rt.food_dbg) then msg(sformat('Food debug: your action packet, category %d, param %d', cat, param)); end
        if (cat == 5) then rt.food_candidate(param, 'action ' .. cat); end     -- 9 (item start) carries a placeholder id, not the item
    end);
end);
ashita.events.register('packet_out', 'zztick_food_out', function (e)
    if (e.id ~= 0x0037) then return; end
    pcall(function ()
        local ffi = require('ffi');
        local p = ffi.cast('uint8_t*', e.data_raw);
        local idx = p[0x0E];
        local item = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, idx);
        if (rt.food_dbg) then msg(sformat('Food debug: item-use packet, inventory slot %d -> item %s', idx, tostring(item and item.Id))); end
        if (item ~= nil and item.Id ~= nil) then rt.food_candidate(item.Id, 'use'); end
    end);
end);

ashita.events.register('command', 'zztick_command', function (e)
    local args = e.command:args();
    if (#args == 0) then return; end
    local cmd = args[1]:lower();
    if (cmd ~= '/zztick') then return; end
    e.blocked = true;

    local sub = args[2] and args[2]:lower() or nil;
    local s = rt.settings;
    local a3l = args[3] and args[3]:lower() or nil;
    -- /zztick flash test = /zztick test flash
    if (sub == 'flash' and a3l == 'test') then sub, args[3] = 'test', 'flash'; end
    -- /zztick debug flash: print every coordinate source the next time the window draws
    if (sub == 'debug' and a3l == 'flash') then
        rt.flash_dbg_want = true;
        if (not rt.test_mode and not rt.resting_now) then msg('Flash debug: prints the next time the window draws (sit, or /zztick test).'); end
        return;
    end

    if (sub == nil or sub == 'help') then
        print_help();
    elseif (sub == 'config' or sub == 'cfg' or sub == 'settings') then
        rt.config_open[1] = not rt.config_open[1];
    elseif (sub == 'lock') then
        s.locked = true; save_now(); msg('Window locked.');
    elseif (sub == 'unlock') then
        s.locked = false; save_now(); msg('Window unlocked. Drag it, then /zztick lock.');
    elseif (sub == 'test' or sub == 'preview') then
        local a3 = args[3] and args[3]:lower() or nil;
        if (a3 == 'sparkle' or a3 == 'flash') then
            -- replay the full effect (preview or while resting): sparkle on both rows / both streaks
            local t = rt.clock();
            if (a3 == 'sparkle') then rt.fx.spark_hp:trigger(t); rt.fx.spark_mp:trigger(t);
            else rt.fx.flash_t[1], rt.fx.flash_t[2] = t, t; end
            if (not rt.test_mode and not rt.resting_now) then
                rt.test_mode, rt.test_start, rt.test_sync = true, t, nil;
                msg('Preview on (' .. a3 .. '). Run /zztick test to hide it.');
            end
            if (not s.animate) then msg('Animations are off (/zztick animate), so nothing will show.'); end
            return;
        end
        local want_sync = (args[3] ~= nil and args[3]:lower() == 'sync');
        if (want_sync and rt.test_mode) then rt.test_sync = 30; msg('Preview: showing the Level Sync badge (Lv 30).'); return; end
        rt.test_mode = not rt.test_mode;
        rt.test_start = rt.clock();
        rt.test_sync = want_sync and 30 or nil;
        msg(rt.test_mode and 'Preview on. Run /zztick test again to hide it.' or 'Preview off.');
    elseif (sub == 'debug') then
        rt.debug = not rt.debug;
        rt.debug_open = { rt.debug };
        rt.stats.win_start, rt.stats.acc_ms, rt.stats.max_ms, rt.stats.win_frames = rt.clock(), 0, 0, 0;
        msg('Debug readout ' .. (rt.debug and 'on.' or 'off.'));
    elseif (sub == 'reset') then
        reset_settings();
        invalidate_caches();
        rebuild_tracker();
        msg('Settings reset to defaults.');
    elseif (sub == 'bonus' and #args >= 4 and (args[3]:lower() == 'hp' or args[3]:lower() == 'mp')) then
        local n = tonumber(args[4]);
        if (n == nil) then err('Usage: /zztick bonus hp|mp <number>'); return; end
        s['bonus_' .. args[3]:lower()] = floor(n);
        save_now();
        msg(sformat('Bonus %s per tick set to %d.', args[3]:upper(), floor(n)));
    elseif (sub == 'scale' and #args >= 3) then
        local n = tonumber(args[3]);
        if (n == nil or n < 0.5 or n > 3) then err('Scale must be between 0.5 and 3.'); return; end
        s.scale = n; save_now(); msg(sformat('Scale set to %.2f.', n));
    elseif (sub == 'compact') then
        s.compact = not s.compact; save_now(); msg('Compact mode ' .. (s.compact and 'on.' or 'off.'));
    elseif (sub == 'fonts') then
        rt.font_list = zzfonts.scan(addon.path);
        msg('Fonts: ');
        for _, f in ipairs(rt.font_list) do msg('  ' .. f.name .. (f.custom and ' (fonts folder)' or '')); end
        if (not zzfonts.supported()) then err('This Ashita build cannot load fonts at runtime; update Ashita v4.'); end
    elseif (sub == 'font' and #args >= 3) then
        local name = table.concat(args, ' ', 3);
        if (name:lower() == 'default') then name = zzfonts.DEFAULT; end
        if (rt.font_list == nil) then rt.font_list = zzfonts.scan(addon.path); end
        local found = nil;
        for _, f in ipairs(rt.font_list) do if (f.name:lower() == name:lower()) then found = f; end end
        if (found == nil) then err('Font not found: ' .. name .. ' (see /zztick fonts).'); return; end
        s.font_name = found.name; rt.font_want = true; save_now(); msg('Font set to ' .. found.name .. '.');
    elseif ((sub == 'titlefont' or sub == 'numfont') and #args >= 3) then
        local name = table.concat(args, ' ', 3);
        if (name:lower() == 'default') then name = zzfonts.DEFAULT; end
        if (rt.font_list == nil) then rt.font_list = zzfonts.scan(addon.path); end
        local found = nil;
        for _, f in ipairs(rt.font_list) do if (f.name:lower() == name:lower()) then found = f; end end
        if (found == nil) then err('Font not found: ' .. name .. ' (see /zztick fonts).'); return; end
        s[sub == 'titlefont' and 'title_font' or 'num_font'] = found.name; rt.font_want = true; save_now();
        msg((sub == 'titlefont' and 'Title' or 'Numbers') .. ' font set to ' .. found.name .. '.');
    elseif (sub == 'sync' and #args >= 3) then
        local v = args[3]:lower();
        if (v ~= 'on' and v ~= 'off') then err('Usage: /zztick sync on|off'); return; end
        s.show_sync = (v == 'on'); save_now(); msg('Sync badge ' .. v .. '.');
    elseif (sub == 'subratio' and #args >= 3) then
        local n = tonumber(args[3]);
        if (n == nil or n < 0 or n > 3 or n ~= floor(n)) then err('Usage: /zztick subratio <0-3>  (0 none, 1 half, 2 two-thirds, 3 equal)'); return; end
        s.sub_ratio = n; rt.jobs.next_check = 0; save_now(); msg(sformat('Subjob ratio: %d.', n));
    elseif (sub == 'theme' and #args >= 3) then
        local t = style.find_theme(table.concat(args, ' ', 3));
        if (t == nil) then err('Themes: ' .. style.theme_list() .. '.'); return; end
        s.theme = t.name; save_now(); msg('Theme: ' .. t.name .. '.');
    elseif (sub == 'width' and #args >= 3) then
        local n = (args[3]:lower() == 'auto') and 0 or tonumber(args[3]);
        if (n == nil or n < 0 or n > 2000) then err('Usage: /zztick width <pixels> | auto'); return; end
        s.width = floor(n); save_now(); msg(n == 0 and 'Width: auto.' or sformat('Width: %d px.', floor(n)));
    elseif (sub == 'chime') then
        local a = args[3] and args[3]:lower() or nil;
        if (a == 'on' or a == 'off') then
            s.chime_enabled, s.chime_choice = (a == 'on'), true; save_now(); msg('Full-heal chime ' .. a .. '.');
        elseif (a == nil) then
            s.chime_enabled, s.chime_choice = not s.chime_enabled, true; save_now(); msg('Full-heal chime ' .. (s.chime_enabled and 'on.' or 'off.'));
        elseif (a == 'test') then
            chime_test();
        elseif (a == 'backend' and (args[4] == 'auto' or args[4] == 'ashita' or args[4] == 'winmm')) then
            s.chime_backend = args[4]; save_now(); msg('Chime playback: ' .. args[4] .. '.');
        elseif (a == 'volume' or a == 'vol') then
            local v = tonumber(args[4]);
            if (v == nil) then err('Usage: /zztick chime volume 0-200 (100 = the file as it is)'); return; end
            s.chime_volume = max(0, min(200, floor(v + 0.5))); save_now(); msg('Chime volume: ' .. s.chime_volume .. '%.');
        elseif (a == 'mode' and args[4]) then
            local m_ = args[4]:lower();
            local okm = false;
            for _, v in ipairs(model.CHIME_MODES) do if (v == m_) then okm = true; end end
            if (not okm) then err('Usage: /zztick chime mode both|any|hp|mp'); return; end
            s.chime_mode = m_; save_now(); msg('Chime when: ' .. m_ .. '.');
        elseif (a == 'list') then
            msg('Sounds (addons/zztick/sounds/): ' .. table.concat(scan_sounds(), ', '));
        elseif (a == 'sound' and args[4]) then
            scan_sounds();
            local f = find_sound(args[4]);
            if (f == nil) then err('No such .wav in sounds/. Try /zztick chime list'); return; end
            s.chime_sound = f; save_now(); msg('Chime sound: ' .. f .. '.');
        elseif (a == 'sitfull' and (args[4] == 'on' or args[4] == 'off')) then
            s.chime_sit_full = (args[4] == 'on'); save_now(); msg('Chime when sitting down already full: ' .. args[4] .. '.');
        else
            err('Usage: /zztick chime on|off|test|list | mode both|any|hp|mp | sound <file> | sitfull on|off | backend auto|ashita|winmm | volume 0-200');
        end
    elseif (sub == 'effects' or sub == 'effect') then
        local v = a3l or '';
        if (v ~= 'off' and v ~= 'subtle' and v ~= 'full') then err('Usage: /zztick effects off|subtle|full  (now: ' .. tostring(s.fx_level) .. ')'); return; end
        s.fx_level = v; save_now(); msg('Effects: ' .. v .. (s.animate and '.' or ' (Animations are off, so nothing will show).'));
    elseif (sub == 'fx') then
        local v = args[3] and args[3]:lower() or '';
        local okv = false;
        for _, e in ipairs(style.FULL_EFFECTS) do if (e == v) then okv = true; end end
        if (not okv) then err('Usage: /zztick fx border|sparkle|both|off'); return; end
        s.full_effect = v; save_now(); msg('Full effect: ' .. v .. '.');
    elseif (sub == 'tickflash') then
        local a = args[3] and args[3]:lower() or nil;
        if (a == 'on' or a == 'off') then s.tick_border = (a == 'on'); else s.tick_border = not s.tick_border; end
        save_now(); msg('Border comet on every tick: ' .. (s.tick_border and 'on.' or 'off.'));
    elseif (sub == 'sparkle') then
        -- 1.4.0 command: toggles the sparkle part of the full effect
        local nxt = { border = 'both', both = 'border', sparkle = 'off', off = 'sparkle' };
        s.full_effect = nxt[s.full_effect] or 'sparkle'; save_now(); msg('Full effect: ' .. s.full_effect .. '.');
    elseif (sub == 'icons') then
        s.show_icons = not s.show_icons; save_now();
        msg('HP/MP icons ' .. (s.show_icons and 'on.' or 'off.'));
    elseif (sub == 'animate') then
        s.animate = not s.animate; save_now(); msg('Animations ' .. (s.animate and 'on.' or 'off.'));
    elseif (sub == 'fade' and #args >= 3) then
        local n = tonumber(args[3]);
        if (n == nil or n < 0 or n > 1000) then err('Fade must be 0-1000 ms.'); return; end
        s.fade_ms = floor(n); save_now(); msg(sformat('Fade %d ms.', floor(n)));
    elseif (sub == 'fontsize' and #args >= 3) then
        local n = tonumber(args[3]);
        if (n == nil or n < 0 or n > 72) then err('Font size must be 0-72.'); return; end
        s.font_size = floor(n); save_now(); msg(sformat('Font size set to %d.', floor(n)));
    elseif (sub == 'profile' and #args >= 3 and (args[3]:lower() == 'retail' or args[3]:lower() == 'lsb')) then
        s.profile, s.profile_choice = args[3]:lower(), true; rt.buffs.force = true; save_now(); msg('Formula profile: ' .. s.profile .. '.');
    elseif (sub == 'food') then
        if (a3l == 'debug') then rt.food_dbg = not rt.food_dbg; msg('Food debug ' .. (rt.food_dbg and 'on: eat something and read the lines.' or 'off.')); return; end
        if (a3l == 'on' or a3l == 'off') then s.auto_food = (a3l == 'on'); save_now(); end
        local f = rt.food;
        msg(sformat('Food bonus: %s. Current food: %s.', s.auto_food and 'ON' or 'off',
            (f.id ~= 0) and sformat('%s (+%d HP, +%d MP)', f.name, f.hp, f.mp) or 'none seen (eat something with the addon loaded, or use /zztick bonus)'));
    elseif (sub == 'info') then
        rt.now = rt.clock();
        rt.gear.force = true;
        local ok, good = pcall(read_state_safe);
        if (not ok or not good) then err('Player data not available yet.'); return; end
        if (s.auto_gear) then pcall(refresh_gear, rt.now); end
        pcall(refresh_buffs, rt.now);
        pcall(read_state_safe);
        local st, c = rt.st, rt.ctx;
        local lv, li = rt.lv, rt.lv_in;
        msg(sformat('Job %d/%d  HP %d/%d  MP %d/%d', st.main, st.sub, st.hp, st.maxhp, st.mp, st.maxmp));
        msg(sformat('Levels: real %d/%d, effective %d/%d%s', lv.real_main, lv.real_sub, lv.main, lv.sub,
            lv.reason and (' (' .. lv.reason .. ')') or ''));
        msg(sformat('  source: %s; client %d/%d, party %d, job table %d/%d; subjob ratio %d%s',
            lv.source, li.cur_main, li.cur_sub, li.party_main, li.real_main, li.real_sub, li.ratio,
            li.sj_off and '; support job disabled' or ''));
        do
            local b = rt.buffs;
            local sm = tonumber(s.signet_mode) or 0;
            local why;
            if (sm == 1) then why = 'setting: Always';
            elseif (sm == 2) then why = 'setting: Never';
            elseif (b.has_signet) then why = 'auto: Signet buff (253) found';
            elseif (b.has_sigil) then why = 'auto: Sigil buff (268) found';
            elseif (b.has_sanction) then why = (c.profile == 'retail') and 'auto: Sanction buff (256) found' or 'auto: only Sanction (256), which gives no HP bonus on LSB';
            else why = 'auto: no Signet (253) / Sigil (268) buff in your buff list'; end
            msg(sformat('Clear Mind tier %d  Signet bonus %s (%s)  Profile %s  Blocked %s', c.cm_tier, c.signet and 'ON' or 'off', why, c.profile, tostring(c.blocked)));
            local parts = rt.info_parts or {};
            rt.info_parts = parts;
            for i = #parts, 1, -1 do parts[i] = nil; end
            for i = 1, b.raw_n do parts[i] = tostring(b.raw[i]); end
            msg(sformat('Buffs: %d active [%s]; raw %s, %d slots, %d-based: %s', b.ids_n,
                (b.ids_n > 0) and table.concat(b.ids, ' ', 1, b.ids_n) or 'none', b.list_kind, b.raw_n, b.list_base,
                (b.raw_n > 0) and table.concat(parts, ' ', 1, b.raw_n) or '(empty)'));
        end
        msg(sformat('Healing bonus: gear %s HP / %s MP, manual %s HP / %s MP', model.fmt_bonus(rt.gear.hp), model.fmt_bonus(rt.gear.mp), model.fmt_bonus(s.bonus_hp), model.fmt_bonus(s.bonus_mp)));
        msg(sformat('Tick 1 would heal %d HP / %d MP; each later tick adds more.', model.hp_gain(1, c), model.mp_gain(1, c)));
        do
            -- HP formula for the next tick, term by term (compare with what you actually get)
            local tr0 = rt.tracker;
            local n = (rt.resting_now and tr0.next_n) or 1;
            local base, lvterm, tickterm, rate, bonus = model.hp_terms(n, c);
            local gear = (s.auto_gear and (rt.gear.hp or 0) or 0) + (s.auto_food and (rt.food.hp or 0) or 0);   -- gear + food
            local b = rt.buffs;
            local sig = c.signet and (b.has_signet and 'Signet' or (b.has_sigil and 'Sigil' or (b.has_sanction and 'Sanction' or 'forced')))
                or ((b.has_sanction and c.profile ~= 'retail') and 'none (Sanction: no HP bonus on LSB)' or 'none');
            local lvtxt = c.signet and sformat('%d level (3*floor(%s%d/10))', lvterm, c.profile == 'retail' and '(Lv-1)=' or 'Lv', c.profile == 'retail' and max(0, (c.level or 1) - 1) or (c.level or 1)) or '0 level (no Signet)';
            msg(sformat('Next tick #%d HP [%s, Signet: %s]: 10 base + %s + %d tick (%d x %d) + %s gear + %s manual = %d%s',
                n, c.profile, sig, lvtxt, tickterm, n - 1, rate, model.fmt_bonus(gear), model.fmt_bonus(s.bonus_hp or 0),
                model.hp_gain(n, c), c.blocked and ' (blocked: 0)' or ''));
        end
        local cv, ch = rt.chime_view, rt.chime;
        local state;
        if (not rt.resting_now) then state = 'not resting';
        elseif (ch.fired) then state = 'played this rest';
        elseif (ch.armed) then state = 'armed, waiting for full';
        else state = 'sat down already full, waits until not full'; end
        msg(sformat('Chime: %s%s, mode %s, sound %s, via %s; %s; HP full %s, MP full %s%s; played %d',
            s.chime_enabled and 'ON' or 'OFF', s.chime_choice and '' or ' (default)', tostring(s.chime_mode), tostring(s.chime_sound),
            tostring(s.chime_backend), state, tostring(cv.fh), cv.has_mp and tostring(cv.fm) or 'n/a', cv.has_mp and '' or ' (no MP)',
            rt.stats.chimes or 0));
        local tr = rt.tracker;
        local pt = tr.pattern;
        msg(sformat('Clock: %s.  Tick timing: %s', rt.clock_name,
            pt and sformat('server 3 s grid, next intervals %d/%d/%d s', tr:interval_for(tr.next_n), tr:interval_for(tr.next_n + 1), tr:interval_for(tr.next_n + 2))
               or 'every 10 s (no 9/9/12 pattern seen yet)'));
        msg(sformat('Tick source: %s (%d self HP/MP packets seen, %d accepted as ticks)',
            rt.sync.active and 'server packet 0x00DF' or 'frame poll (no packet-confirmed tick yet)', rt.sync.seen, rt.sync.accepted));
        msg('First tick: ' .. (rt.tracker.phase_off and 'grid phase not reliable here, expecting 21.5 s'
            or rt.tracker.phase and 'predicted from this zone\'s 3 s grid'
            or 'expecting 21.5 s until a tick has been seen in this zone'));
    else
        err('Unknown command.');
        print_help();
    end
end);

local function present()
    local now = rt.now;
    local cs = rt.stats;
    cs.f_arrows, cs.f_icons, cs.f_sparkle, cs.f_flash = 0, 0, 0, 0;   -- per-frame glyph counters (debug / tests)

    -- Font loads happen here, before any window is begun.
    if (rt.font_want) then apply_font(); end
    FX.update(rt.settings);
    -- ImGui's own item spacing, read here (outside our window): PushStyleVar changes the style in place, so a
    -- read made inside the window would see our own padding and the padding would grow on every re-read.
    if (now >= (rt.spacing_next or 0)) then
        rt.spacing_next = now + 2.0;
        local oks, sx, sy = pcall(function ()
            local is = imgui.GetStyle().ItemSpacing;
            if (is == nil) then return nil; end
            return is.x or is[1], is.y or is[2];
        end);
        if (oks and type(sx) == 'number' and type(sy) == 'number') then rt.style_spacing_x, rt.style_spacing_y = sx, sy; end
    end

    -- Debounced save: only after a user change, and not while the mouse is still dragging.
    if (rt.dirty and now - rt.dirty_at > SAVE_DEBOUNCE) then
        local ok, down = pcall(imgui.IsMouseDown, 0);
        if (not (ok and down)) then save_now(); end
    end

    draw_config();

    local resting = false;
    rt.fx.zoning = false;
    rt.fx.wait_a = 1;
    local ok, good = pcall(read_state_safe);
    local st = rt.st;
    if (ok and good) then
        resting = rt.tracker:update(now, st.status, st.hp, st.mp, st.maxhp, st.maxmp, rt.ctx);
    else
        rt.tracker:update(now, -1, 0, 0, 0, 0, rt.ctx);
    end
    rt.resting_now = resting;

    -- Fade in/out (zoning hides at once).
    local fx, snap = rt.fx, rt.snap;
    local dt = fx.last_now and (now - fx.last_now) or 0;
    if (dt < 0) then dt = 0; elseif (dt > 0.1) then dt = 0.1; end
    fx.last_now, rt.fx_dt = now, dt;
    local want = resting or rt.test_mode;
    if (fx.zoning) then fx.alpha = 0;
    else
        fx.alpha = style.fade_step(fx.alpha, want and 1 or 0, dt, (rt.settings.fade_ms or 0) / 1000);
        if (want and fx.alpha < 0.02) then fx.alpha = 0.02; end   -- first frame of a fade-in still draws
    end

    if (resting) then
        local tr = rt.tracker;
        if (fx.last_n ~= nil and tr.next_n > fx.last_n and (fx.ghp > 0 or fx.gmp > 0)) then
            fx.pop_at, fx.pop_hp, fx.pop_mp, fx.pop_whp, fx.pop_wmp = now, model.fmt_gain(fx.ghp), model.fmt_gain(fx.gmp), -1, -1;
        end
        -- Every tick roll-over (a server-reported tick, or a clock tick while nothing can be observed)
        -- starts the reset sweep. It is timed from this frame, not from the tick's own timestamp, so a
        -- frame hitch or the window just fading in can no longer swallow it.
        if (fx.last_n ~= nil and tr.next_n > fx.last_n) then
            fx.sweep_at = now;
            if (rt.settings.tick_border) then fx.flash_t[1] = now; end   -- one clockwise comet per tick
        end
        fx.last_n = tr.next_n;

        local eh, em = tr:effective(st.hp, st.mp, st.maxhp, st.maxmp, rt.ctx);
        local prog = tr:progress(now);   -- linear: only a server tick report moves the schedule
        local rem = tr:remaining(now);

        -- No predictive roll-over. Once the expected tick time passes, the timer holds at 0.0 with
        -- a full bar and pulses in alpha until the server reports the tick; only that report
        -- advances the tick number and restarts the countdown (the sweep flash fires then).
        if (tr:is_waiting(now)) then
            fx.wait_a = rt.settings.animate and (0.30 + 0.70 * style.pulse(now)) or 0.55;
        end

        snap.valid, snap.st, snap.ctx, snap.rem, snap.prog, snap.n, snap.eh, snap.em =
            true, st, rt.ctx, rem, prog, tr.next_n, eh, em;
        local sw = now - fx.sweep_at;
        snap.flash = (sw >= 0 and sw < SWEEP_DUR) and (1 - sw / SWEEP_DUR) or 0;

    -- ... (full/sparkle/chime logic unchanged)
    -- full transitions: sparkle per stat, chime once per rest
        local has_mp = (st.maxmp or 0) > 0;
        -- full = current (incl. a gain whose packet is still in flight) >= max; never "full" while the
        -- max isn't known yet (0 for a frame after zoning)
        local fh = (st.maxhp or 0) > 0 and model.stat_full(eh, max(st.maxhp, eh or 0)) or false;
        local fm = has_mp and model.stat_full(em, max(st.maxmp, em or 0)) or false;
        if (((fx.was_fhp == false) or (has_mp and fx.was_fmp == false)) and fh and (fm or not has_mp)) then fx.rested_at = now; end
        if (fx.was_fhp == false and fh) then fire_full(1, now); end
        if (fx.was_fmp == false and fm and has_mp) then fire_full(2, now); end
        fx.was_fhp, fx.was_fmp = fh, fm;
        local s_ = rt.settings;
        -- rest session: survives one-frame read glitches (a tracker reset must not look like a new rest)
        local rs = rt.rest_sess;
        if (now - rs.last > REST_GAP) then rs.id = rs.id + 1; end
        rs.last = now;
        local cv = rt.chime_view;
        cv.fh, cv.fm, cv.has_mp = fh, fm, has_mp;
        cv.cond = model.chime_cond(s_.chime_mode, fh, fm, has_mp);
        if (rt.chime:update(rs.id, cv.cond, s_.chime_sit_full)) then
            if (s_.chime_enabled) then
                play_chime();
            elseif (not s_.chime_choice and not rt.chime_hinted) then
                rt.chime_hinted = true;
                msg('Fully healed. (The chime is off: /zztick chime on)');
            end
        end
    elseif (rt.test_mode) then
        fx.last_n = nil;
        local el = now - rt.test_start;
        local t = el % 30;
        local r = 10 - (t % 10);
        local k = floor(el / 10);
        local ttr = rt.test_tr;
        ttr.next_n, ttr.next_time, ttr.rest_start = 3 + k, rt.test_start + (k + 1) * 10, rt.test_start;
        local tprog = rt.test_bar:update(now, ttr);
        r = rt.test_bar.remaining;
        snap.flash = rt.test_bar:flash(now);
        if (fx.test_r ~= nil and r > fx.test_r + 3) then
            fx.pop_at, fx.pop_hp, fx.pop_mp, fx.pop_whp, fx.pop_wmp = now, model.fmt_gain(fx.ghp), model.fmt_gain(fx.gmp), -1, -1;
        end
        fx.test_r = r;
        test_ctx.hp_bonus, test_ctx.mp_bonus, test_ctx.profile = rt.settings.bonus_hp, rt.settings.bonus_mp, rt.settings.profile;
        snap.valid, snap.st, snap.ctx, snap.rem, snap.prog, snap.n, snap.eh, snap.em =
            true, test_st, test_ctx, r, tprog, 3, test_st.hp, test_st.mp;
    else
        fx.last_n, fx.test_r = nil, nil;
        FX.roll_reset();
        rt.tick_hold.holding = false;
        rt.tick_hold.last_hp, rt.tick_hold.last_mp = 0, 0;
    end
    if (not resting) then
        fx.was_fhp, fx.was_fmp = nil, nil;   -- sitting down already full is not "reaching" full
    end

    if (fx.alpha > 0 and snap.valid) then
        draw_window(snap.st, snap.ctx, snap.rem, snap.prog, snap.n, snap.eh, snap.em);
    else
        snap.valid = false;
    end
end

ashita.events.register('d3d_present', 'zztick_present', function ()
    local t0 = rt.clock();
    rt.now = t0;
    present();
    if (rt.debug) then
        local s = rt.stats;
        local dt = (rt.clock() - t0) * 1000;
        s.acc_ms = s.acc_ms + dt;
        if (dt > s.max_ms) then s.max_ms = dt; end
        s.win_frames = s.win_frames + 1;
        if (t0 - s.win_start >= 1.0) then
            s.avg_ms = s.acc_ms / max(1, s.win_frames);
            s.peak_ms = s.max_ms;
            s.acc_ms, s.max_ms, s.win_frames, s.win_start = 0, 0, 0, t0;
        end
        draw_debug();
    end
    rt.stats.frames = rt.stats.frames + 1;
end);