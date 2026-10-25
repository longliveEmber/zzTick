--[[
* zztick - zzstyle.lua
*
* Themes, animation helpers and the fixed-size layout for the zztick window.
* Pure Lua (no Ashita calls) so it can be tested offline. The layout takes a
* measure(str, role) function, which the addon backs with imgui.CalcTextSize
* under the font for that role ('body', 'num' or 'title').
--]]

local M = {};
local floor, max, min, sin = math.floor, math.max, math.min, math.sin;

M.CLASSIC = 'Classic';
M.DEFAULT_THEME = "Vana'diel Gold";
M.THEMES = {
    {
        name = "Vana'diel Gold",
        bg = { 0.09, 0.07, 0.05, 1 }, border = { 0.62, 0.47, 0.20, 0.70 },
        head_l = { 0.42, 0.29, 0.09, 0.85 }, head_r = { 0.42, 0.29, 0.09, 0.00 }, rule = { 0.85, 0.66, 0.28, 0.55 },
        title = { 1.00, 0.86, 0.48, 1 }, text = { 0.95, 0.91, 0.82, 1 }, dim = { 0.68, 0.62, 0.50, 1 },
        timer = { 1.00, 0.90, 0.58, 1 }, bar_a = { 0.78, 0.50, 0.12, 1 }, bar_b = { 1.00, 0.84, 0.36, 1 },
        bar_bg = { 0.20, 0.15, 0.09, 1 }, glow = { 1.00, 0.86, 0.40, 1 },
        hp = { 0.56, 0.92, 0.48, 1 }, mp = { 0.52, 0.76, 1.00, 1 }, gain = { 0.45, 1.00, 0.52, 1 },
        moon = { 1.00, 0.88, 0.55, 1 }, warn = { 1.00, 0.42, 0.38, 1 }, accent = { 0.95, 0.72, 0.30, 1 },
    },
    {
        name = 'Crystal Blue',
        bg = { 0.04, 0.08, 0.13, 1 }, border = { 0.35, 0.70, 0.95, 0.60 },
        head_l = { 0.10, 0.32, 0.52, 0.85 }, head_r = { 0.10, 0.32, 0.52, 0.00 }, rule = { 0.45, 0.85, 1.00, 0.50 },
        title = { 0.78, 0.94, 1.00, 1 }, text = { 0.90, 0.95, 1.00, 1 }, dim = { 0.55, 0.68, 0.80, 1 },
        timer = { 0.80, 0.95, 1.00, 1 }, bar_a = { 0.12, 0.42, 0.85, 1 }, bar_b = { 0.50, 0.90, 1.00, 1 },
        bar_bg = { 0.08, 0.15, 0.24, 1 }, glow = { 0.60, 0.95, 1.00, 1 },
        hp = { 0.55, 0.95, 0.70, 1 }, mp = { 0.55, 0.80, 1.00, 1 }, gain = { 0.50, 1.00, 0.75, 1 },
        moon = { 0.85, 0.96, 1.00, 1 }, warn = { 1.00, 0.45, 0.45, 1 }, accent = { 0.45, 0.85, 1.00, 1 },
    },
    {
        name = 'Midnight',
        bg = { 0.05, 0.05, 0.09, 1 }, border = { 0.45, 0.40, 0.75, 0.55 },
        head_l = { 0.22, 0.17, 0.42, 0.85 }, head_r = { 0.22, 0.17, 0.42, 0.00 }, rule = { 0.62, 0.52, 1.00, 0.45 },
        title = { 0.86, 0.82, 1.00, 1 }, text = { 0.88, 0.87, 0.95, 1 }, dim = { 0.58, 0.56, 0.72, 1 },
        timer = { 0.90, 0.86, 1.00, 1 }, bar_a = { 0.36, 0.26, 0.78, 1 }, bar_b = { 0.74, 0.58, 1.00, 1 },
        bar_bg = { 0.12, 0.11, 0.20, 1 }, glow = { 0.80, 0.70, 1.00, 1 },
        hp = { 0.55, 0.90, 0.60, 1 }, mp = { 0.55, 0.72, 1.00, 1 }, gain = { 0.55, 1.00, 0.65, 1 },
        moon = { 0.95, 0.92, 0.75, 1 }, warn = { 1.00, 0.45, 0.50, 1 }, accent = { 0.72, 0.62, 1.00, 1 },
    },
    {
        -- deep red/orange, molten glow (warn is yellow so it stands out on red)
        name = 'Ember Forge',
        bg = { 0.10, 0.04, 0.03, 1 }, border = { 0.85, 0.35, 0.12, 0.70 },
        head_l = { 0.55, 0.14, 0.05, 0.88 }, head_r = { 0.80, 0.35, 0.05, 0.00 }, rule = { 1.00, 0.55, 0.20, 0.55 },
        title = { 1.00, 0.78, 0.50, 1 }, text = { 0.98, 0.90, 0.84, 1 }, dim = { 0.80, 0.62, 0.54, 1 },
        timer = { 1.00, 0.80, 0.55, 1 }, bar_a = { 0.72, 0.10, 0.04, 1 }, bar_b = { 1.00, 0.66, 0.14, 1 },
        bar_bg = { 0.24, 0.08, 0.05, 1 }, glow = { 1.00, 0.55, 0.15, 1 },
        hp = { 0.62, 0.95, 0.50, 1 }, mp = { 0.55, 0.80, 1.00, 1 }, gain = { 0.72, 1.00, 0.55, 1 },
        moon = { 1.00, 0.72, 0.42, 1 }, warn = { 1.00, 0.92, 0.35, 1 }, accent = { 1.00, 0.50, 0.18, 1 },
    },
    {
        -- greens/teal, leafy
        name = 'Windurst Verdant',
        bg = { 0.03, 0.09, 0.07, 1 }, border = { 0.35, 0.78, 0.55, 0.60 },
        head_l = { 0.08, 0.34, 0.24, 0.88 }, head_r = { 0.10, 0.45, 0.42, 0.00 }, rule = { 0.55, 0.95, 0.70, 0.50 },
        title = { 0.80, 1.00, 0.78, 1 }, text = { 0.90, 0.98, 0.92, 1 }, dim = { 0.60, 0.76, 0.66, 1 },
        timer = { 0.78, 1.00, 0.86, 1 }, bar_a = { 0.10, 0.50, 0.38, 1 }, bar_b = { 0.62, 0.95, 0.45, 1 },
        bar_bg = { 0.07, 0.18, 0.14, 1 }, glow = { 0.70, 1.00, 0.60, 1 },
        hp = { 0.82, 1.00, 0.45, 1 }, mp = { 0.55, 0.82, 1.00, 1 }, gain = { 0.98, 1.00, 0.60, 1 },
        moon = { 0.92, 1.00, 0.75, 1 }, warn = { 1.00, 0.50, 0.42, 1 }, accent = { 0.40, 0.92, 0.80, 1 },
    },
    {
        -- steel/copper steampunk
        name = 'Bastok Steam',
        bg = { 0.07, 0.075, 0.08, 1 }, border = { 0.72, 0.45, 0.25, 0.65 },
        head_l = { 0.30, 0.32, 0.36, 0.90 }, head_r = { 0.55, 0.30, 0.14, 0.00 }, rule = { 0.85, 0.55, 0.30, 0.60 },
        title = { 0.96, 0.78, 0.55, 1 }, text = { 0.90, 0.91, 0.93, 1 }, dim = { 0.64, 0.67, 0.70, 1 },
        timer = { 0.95, 0.82, 0.62, 1 }, bar_a = { 0.42, 0.46, 0.52, 1 }, bar_b = { 0.92, 0.58, 0.28, 1 },
        bar_bg = { 0.16, 0.17, 0.19, 1 }, glow = { 1.00, 0.70, 0.40, 1 },
        hp = { 0.58, 0.92, 0.55, 1 }, mp = { 0.56, 0.78, 1.00, 1 }, gain = { 0.62, 1.00, 0.62, 1 },
        moon = { 0.88, 0.90, 0.92, 1 }, warn = { 1.00, 0.42, 0.38, 1 }, accent = { 0.88, 0.56, 0.30, 1 },
    },
    {
        -- purple/rose dusk over the city
        name = 'Jeuno Twilight',
        bg = { 0.08, 0.05, 0.10, 1 }, border = { 0.80, 0.50, 0.75, 0.60 },
        head_l = { 0.38, 0.16, 0.42, 0.88 }, head_r = { 0.70, 0.30, 0.45, 0.00 }, rule = { 1.00, 0.62, 0.78, 0.50 },
        title = { 1.00, 0.82, 0.90, 1 }, text = { 0.96, 0.90, 0.96, 1 }, dim = { 0.74, 0.62, 0.76, 1 },
        timer = { 1.00, 0.84, 0.92, 1 }, bar_a = { 0.45, 0.22, 0.70, 1 }, bar_b = { 1.00, 0.55, 0.70, 1 },
        bar_bg = { 0.18, 0.10, 0.21, 1 }, glow = { 1.00, 0.68, 0.85, 1 },
        hp = { 0.60, 0.95, 0.62, 1 }, mp = { 0.58, 0.80, 1.00, 1 }, gain = { 0.66, 1.00, 0.70, 1 },
        moon = { 1.00, 0.90, 0.80, 1 }, warn = { 1.00, 0.50, 0.40, 1 }, accent = { 1.00, 0.60, 0.78, 1 },
    },
    {
        -- near-black with neon cyan/magenta
        name = 'Abyssea',
        bg = { 0.02, 0.02, 0.04, 1 }, border = { 0.00, 0.90, 1.00, 0.65 },
        head_l = { 0.30, 0.00, 0.40, 0.88 }, head_r = { 0.00, 0.45, 0.55, 0.00 }, rule = { 0.00, 1.00, 0.95, 0.55 },
        title = { 0.55, 1.00, 1.00, 1 }, text = { 0.92, 0.95, 1.00, 1 }, dim = { 0.60, 0.64, 0.78, 1 },
        timer = { 0.45, 1.00, 1.00, 1 }, bar_a = { 0.85, 0.00, 0.85, 1 }, bar_b = { 0.00, 0.95, 1.00, 1 },
        bar_bg = { 0.09, 0.07, 0.14, 1 }, glow = { 1.00, 0.30, 1.00, 1 },
        hp = { 0.45, 1.00, 0.60, 1 }, mp = { 0.45, 0.80, 1.00, 1 }, gain = { 0.62, 1.00, 0.78, 1 },
        moon = { 0.85, 0.60, 1.00, 1 }, warn = { 1.00, 0.40, 0.50, 1 }, accent = { 1.00, 0.25, 0.90, 1 },
    },
    { name = 'Classic', classic = true },
};

-- "Vana'diel Gold, Crystal Blue, ..." for help/error text.
function M.theme_list()
    local t = {};
    for i, th in ipairs(M.THEMES) do t[i] = th.name; end
    return table.concat(t, ', ');
end

function M.find_theme(name)
    if (type(name) == 'string') then
        local l = name:lower();
        for _, t in ipairs(M.THEMES) do
            if (t.name:lower() == l) then return t; end
        end
        -- loose match for commands: "gold", "crystal", "ember", "windurst", "bastok", "jeuno", "abyssea"...
        for _, t in ipairs(M.THEMES) do
            if (t.name:lower():find(l, 1, true)) then return t; end
        end
    end
    return nil;
end

--[[
* Animation helpers.
--]]
function M.clamp01(x) if (x < 0) then return 0; elseif (x > 1) then return 1; end return x; end
function M.lerp(a, b, t) return a + (b - a) * t; end
function M.ease_out(t) t = M.clamp01(t); return 1 - (1 - t) * (1 - t); end

-- Moves a fade value toward target (0 or 1) at 1/dur per second; dur in seconds (0 = instant).
function M.fade_step(cur, target, dt, dur)
    if (dur == nil or dur <= 0) then return target; end
    local step = dt / dur;
    if (cur < target) then return min(target, cur + step); end
    if (cur > target) then return max(target, cur - step); end
    return cur;
end

-- 0..1 pulse used for the last-second glow (3 Hz breathing).
function M.pulse(now) return 0.5 + 0.5 * sin(now * 6.2831853 * 1.5); end

-- Packs a float color times alpha into ImGui's u32 (ABGR) using the supplied col32(a, r, g, b).
function M.u32(col32, c, alpha)
    local a = (c[4] or 1) * (alpha or 1);
    return col32(floor(M.clamp01(a) * 255 + 0.5), floor(M.clamp01(c[1]) * 255 + 0.5),
                 floor(M.clamp01(c[2]) * 255 + 0.5), floor(M.clamp01(c[3]) * 255 + 0.5));
end

-- Mixes two colors into out (reused table).
function M.mix(out, a, b, t)
    out[1] = a[1] + (b[1] - a[1]) * t; out[2] = a[2] + (b[2] - a[2]) * t;
    out[3] = a[3] + (b[3] - a[3]) * t; out[4] = (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t;
    return out;
end

--[[
* Crescent moon glyph as a triangle strip between two arcs (unit size, opening right).
* Precomputed once; the addon scales/translates it with reused vectors.
--]]
do
    local N = 10;
    local outer, inner = {}, {};
    local a0, a1 = math.rad(70), math.rad(290);
    local cx, r2 = 0.5, 0.953;
    local b0, b1 = math.atan2(0.940, 0.342 - cx), math.rad(360) - math.atan2(0.940, 0.342 - cx);
    for i = 0, N do
        local t = i / N;
        local a = a0 + (a1 - a0) * t;
        local b = b0 + (b1 - b0) * t;
        outer[#outer + 1] = { math.cos(a), -math.sin(a) };
        inner[#inner + 1] = { cx + r2 * math.cos(b), -r2 * math.sin(b) };
    end
    M.MOON_OUTER, M.MOON_INNER = outer, inner;
end

--[[
* Worst-case strings for the fixed width. Countdown <= 88.8s (first delay and interval
* are capped at 60s), HP/MP up to 4 digits, gains up to 3 digits.
--]]
M.WORST = {
    timer_val   = '88.8s',
    num         = '9999',
    gain        = '+999',
    tick        = 'Tick 888',
    sync        = 'Synced Lv 88',    -- header badge (Level Sync / Level Restriction)
    csync       = 'Sync 88',         -- compact badge
    full        = 'MP full in 888 ticks (88m 88s)',  -- per-stat wording (1.2.2)
    blocked     = 'No recovery (Disease/Plague/Curse)',
    last        = 'Last: +999 HP / +999 MP (exp 999 / 999)',
    -- classic lines
    c_timer     = 'Next tick: 88.8s',
    c_tick      = '  (#888)',
    c_sync      = '  Synced Lv 88',
    c_csync     = ' Sync 88',
    c_stat      = 'HP 9999 -> 9999',
    c_gain      = '  (+999)',
    c_cstat     = 'HP 9999 (+999)',
    c_cstat_ng  = 'HP 9999',
};
M.LABEL_TIMER = 'Next tick';
M.LABEL_TITLE = 'Resting';
M.ARROW = '->';

--[[
* Computes the fixed layout.
*   o: { classic, compact, show_timer, show_bar, show_hp, show_mp (and has MP), show_gain,
*        show_tick_no, show_full, show_last, scale, pad_x, spacing, width_override }
*   measure(str, role) -> width in pixels for the font of that role.
* Returns L (reused if given) with the window width and column positions (relative to the
* content start). Column x values are right edges for right-aligned numbers.
--]]
function M.layout(o, measure, L)
    L = L or {};
    local sc = o.scale or 1;
    local gap = 8 * sc;
    local sp = o.spacing or (8 * sc);
    local W = M.WORST;
    local cw = 0;
    L.gap = gap;
    L.icon_w = 0;

    if (o.classic) then
        if (o.compact) then
            local w, items = 0, 0;
            if (o.show_timer) then w = w + measure('88.8s' .. (o.show_sync and W.c_csync or ''), 'body'); items = items + 1; end
            local stat = o.show_gain and W.c_cstat or W.c_cstat_ng;
            if (o.show_hp) then w = w + measure(stat, 'body'); items = items + 1; end
            if (o.show_mp) then w = w + measure(stat, 'body'); items = items + 1; end
            cw = w + max(0, items - 1) * sp;
            if (o.show_bar) then cw = max(cw, 160 * sc); end
        else
            if (o.show_timer) then cw = max(cw, measure(W.c_timer .. (o.show_tick_no and W.c_tick or '') .. (o.show_sync and W.c_sync or ''), 'body')); end
            local stat = W.c_stat .. (o.show_gain and W.c_gain or '');
            if (o.show_hp or o.show_mp) then cw = max(cw, measure(stat, 'body')); end
            if (o.show_full) then cw = max(cw, measure(W.full, 'body'), measure(W.blocked, 'body')); end
            if (o.show_last) then cw = max(cw, measure(W.last, 'body')); end
            if (o.show_bar) then cw = max(cw, 200 * sc); end
        end
    else
        local num = measure(W.num, 'num');
        local gain = measure(W.gain, 'num');
        local label = max(measure('HP', 'body'), measure('MP', 'body'));
        -- drawn heart / droplet left of the labels (v1.4.0): reserved only while icons are on
        L.icon_w = o.show_icons and (o.icon_w or 14 * sc) or 0;
        label = label + L.icon_w;
        local arrow = measure(M.ARROW, 'body');
        -- countdown slot: fixed cells from the addon (v1.4.5), else the worst-case string
        local tval = o.timer_w or measure(W.timer_val, 'num');
        if (o.compact) then
            -- [timer] [HP proj +g] [MP proj +g], each in a fixed slot
            local x = 0;
            L.c_timer_r = 0;
            if (o.show_timer) then x = tval; L.c_timer_r = x; x = x + gap * 1.5; end
            L.c_sync_x = x;
            if (o.show_sync) then L.c_sync_w = measure(W.csync, 'body'); x = x + L.c_sync_w + gap * 1.5; end
            local slot = label + gap * 0.5 + num + (o.show_gain and (gap * 0.5 + gain) or 0);
            L.c_hp_x = x;
            if (o.show_hp) then x = x + slot + gap * 1.5; end
            L.c_mp_x = x;
            if (o.show_mp) then x = x + slot + gap * 1.5; end
            L.c_label, L.c_num = label, num;
            cw = max(0, x - gap * 1.5);
            if (o.show_bar) then cw = max(cw, 150 * sc); end
        else
            -- rows: label | cur (right) | arrow | proj (right) | gain (right)
            L.x_cur_r  = label + gap + num;
            L.x_arrow  = L.x_cur_r + gap * 0.75;
            L.x_proj_r = L.x_arrow + arrow + gap * 0.75 + num;
            L.x_gain_r = L.x_proj_r + (o.show_gain and (gap + gain) or 0);
            if (o.show_hp or o.show_mp) then cw = max(cw, L.x_gain_r); end
            -- header: moon + title ... tick
            local title_w = measure(M.LABEL_TITLE, 'title');
            L.title_h = o.title_h or 0;
            L.tick_w = o.show_tick_no and measure(W.tick, 'body') or 0;
            L.sync_w = o.show_sync and measure(W.sync, 'body') or 0;
            L.badge_pad = 4 * sc;
            local head = (o.glyph_w or 18 * sc) + title_w + (o.show_tick_no and (gap * 2 + L.tick_w) or 0)
                + (o.show_sync and (gap * 2 + L.sync_w + 2 * L.badge_pad) or 0);
            cw = max(cw, head);
            if (o.show_timer) then cw = max(cw, measure(M.LABEL_TIMER, 'body') + gap * 2 + tval + (o.timer_pad or 0)); end
            if (o.show_full) then cw = max(cw, measure(W.full, 'body'), measure(W.blocked, 'body')); end
            if (o.show_last) then cw = max(cw, measure(W.last, 'body')); end
            if (o.show_bar) then cw = max(cw, 170 * sc); end
        end
    end
    local pad = floor((o.pad_x or 8) + 0.5);
    L.need_w = floor(cw + 0.999) + 2 * pad;          -- width the content needs
    if ((o.width_override or 0) > 0) then
        -- absolute window width in pixels; narrower than need_w clips the right side
        L.w = max(floor(o.width_override), 2 * pad + 40);
    else
        L.w = L.need_w;
    end
    L.cw = L.w - 2 * pad;
    if (L.x_gain_r and o.show_gain) then L.x_gain_r = max(L.x_gain_r, L.cw); end
    return L;
end

--[[
* Window perimeter as a path parametrized by arc length (v1.4.2 border flash).
* perim_set(G, w, h, r) stores the geometry (call only when the size/rounding changes);
* perim_at(G, s) returns the point at arc length s, clockwise from the end of the top-left corner
* (r, 0), with 0 <= s <= G.len (wraps). Segments: top, TR arc, right, BR arc, bottom, BL arc, left,
* TL arc. Coordinates are relative to the rect's top-left; screen y points down. No allocations.
--]]
local PI_2 = math.pi * 0.5;
function M.perim_set(G, w, h, r)
    G.w, G.h, G.r_in = w, h, r;
    r = math.max(0, math.min(r or 0, w * 0.5, h * 0.5));
    G.r = r;
    G.a = w - 2 * r;            -- top / bottom straight length
    G.b = h - 2 * r;            -- left / right straight length
    G.q = PI_2 * r;             -- quarter arc length
    G.len = 2 * G.a + 2 * G.b + 4 * G.q;
    return G;
end

function M.perim_at(G, s)
    local L = G.len;
    if (L <= 0) then return 0, 0; end
    s = s % L;
    local a, b, q, r, w, h = G.a, G.b, G.q, G.r, G.w, G.h;
    if (s <= a) then return r + s, 0; end
    s = s - a;
    if (s <= q) then local t = -PI_2 + (r > 0 and s / r or 0); return w - r + r * math.cos(t), r + r * math.sin(t); end
    s = s - q;
    if (s <= b) then return w, r + s; end
    s = s - b;
    if (s <= q) then local t = (r > 0 and s / r or 0); return w - r + r * math.cos(t), h - r + r * math.sin(t); end
    s = s - q;
    if (s <= a) then return w - r - s, h; end
    s = s - a;
    if (s <= q) then local t = PI_2 + (r > 0 and s / r or 0); return r + r * math.cos(t), h - r + r * math.sin(t); end
    s = s - q;
    if (s <= b) then return 0, h - r - s; end
    s = s - b;
    local t = math.pi + (r > 0 and math.min(s, q) / r or 0);
    return r + r * math.cos(t), r + r * math.sin(t);
end

-- Border flash timing (seconds): one lap, then a whole-border glow pulse.
M.FLASH_LAP, M.FLASH_PULSE, M.FLASH_TAIL, M.FLASH_SEGS = 0.6, 0.25, 0.24, 18;
-- Head position along the lap (0..1) for lap phase u: mild ease-out, ends exactly at 1.
function M.flash_head(u)
    if (u <= 0) then return 0; end
    if (u >= 1) then return 1; end
    return u * (1.3 - 0.3 * u);
end
M.FULL_EFFECTS = { 'border', 'sparkle', 'both', 'off' };

return M;
