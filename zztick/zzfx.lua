--[[
* Zztick - Released under the GNU GPL v3 or later (see LICENSE).
--]]


local M = {};
local floor, sin, cos, pi, min, max = math.floor, math.sin, math.cos, math.pi, math.min, math.max;

M.bar_shine, M.bar_spark, M.charge, M.glint, M.pop, M.roll_on, M.sleep, M.rested = false, false, false, false, false, false, false, false;
M.k = 0.8;          -- overall strength 0..1 (softer on 'subtle')
M.sk, M.ss = 1.0, 1.0   -- spark strength and size multipliers
M.zperiod = 4;      -- seconds for a floating z to rise (fixed)
M.period = 5;       -- seconds between shine passes

local E = nil;      -- helpers from the caller
local V1, V2, V3 = { 0, 0 }, { 0, 0 }, { 0, 0 };
local TINT = { 1, 1, 1, 1 };
local ROLL_DUR, GLINT_DUR, POP_DUR, RESTED_DUR = 0.25, 0.65, 0.40, 1.1;
M.GLINT_DUR, M.POP_DUR, M.RESTED_DUR = GLINT_DUR, POP_DUR, RESTED_DUR;

function M.init(env) E = env; end

local function smooth(t) if (t < 0) then t = 0; elseif (t > 1) then t = 1; end return t * t * (3 - 2 * t); end
M.smooth = smooth;

-- Called once per frame (cheap).
function M.update(s)
    local lvl = s.fx_level;
    local anim = s.animate ~= false;
    local off = (lvl == 'off' or lvl == nil or not anim);
    local full = (lvl == 'full');
    M.k = (tonumber(s.fx_strength) or 0.8) * (full and 1 or 0.65);
    M.sk = (tonumber(s.fx_spark_strength) or 0.35) * 1.25;    -- slider 0.10-1.00
    M.ss = tonumber(s.fx_spark_size) or 1.0;
    M.period = max(2, tonumber(s.fx_shine_period) or 5);
    M.charge   = not off and s.fx_charge ~= false;
    M.glint    = not off and s.fx_glint ~= false;
    M.roll_on  = not off and s.fx_roll ~= false;
    M.bar_shine = not off and full and s.fx_bar_shine ~= false;
    M.bar_spark = not off and full and s.fx_bar_spark ~= false;
    M.pop      = not off and full and s.fx_pop ~= false;
    M.sleep    = not off and full and s.fx_sleep ~= false;
    M.rested   = s.fx_rested ~= false;        -- the text line is not an animation; the shimmer/stars are (see below)
    M.rested_fx = not off and full and s.fx_rested ~= false;
end

-- Mixes white with the given color (t = share of the color) into the shared tint.
local function tint_toward(col, share)
    TINT[1], TINT[2], TINT[3] = 1, 1, 1;
    if (col ~= nil) then
        TINT[1] = 1 + (col[1] - 1) * share;
        TINT[2] = 1 + (col[2] - 1) * share;
        TINT[3] = 1 + (col[3] - 1) * share;
    end
    return TINT;
end

-- A soft vertical band of light centered on cx, hw wide each side, clipped to [xa, xb]. Two gradients.
local function hband(dl, xa, xb, ya, yb, cx, hw, a)
    local lo, hi = cx - hw, cx + hw;
    if (hi <= xa or lo >= xb or yb <= ya) then return; end
    local u = E.u;
    local x0, x1 = max(lo, xa), min(cx, xb);
    if (x1 - x0 >= 0.5) then
        local c0, c1 = u(TINT, a * (x0 - lo) / hw), u(TINT, a * (x1 - lo) / hw);
        dl:AddRectFilledMultiColor(E.vec(V1, x0, ya), E.vec(V2, x1, yb), c0, c1, c1, c0);
    end
    x0, x1 = max(cx, xa), min(hi, xb);
    if (x1 - x0 >= 0.5) then
        local c0, c1 = u(TINT, a * (1 - (x0 - cx) / hw)), u(TINT, a * (1 - (x1 - cx) / hw));
        dl:AddRectFilledMultiColor(E.vec(V1, x0, ya), E.vec(V2, x1, yb), c0, c1, c1, c0);
    end
end

--[[
* Diagonal glint across (x0,y0)-(x1,y1): a soft band cut into thin strips, each shifted along the
* diagonal, easing in and out, clipped to the rectangle. t = seconds since the start, dur = length,
* a = peak brightness, hwk = half-width as a fraction of the longer side (capped at hwmax px).
--]]
function M.glint_rect(dl, x0, y0, x1, y1, t, dur, col, a, hwk, hwmax)
    if (t < 0 or t > dur) then return; end
    local w, h = x1 - x0, y1 - y0;
    if (w < 4 or h < 4) then return; end
    local u = t / dur;
    local e = u * u * (3 - 2 * u);
    local env = sin(pi * u) ^ 0.8;
    a = a * env;
    if (a <= 0.004) then return; end
    local hw = min(hwmax or 1e9, max(4, max(w, h) * hwk));
    local slant = h * 0.8;
    local cx0 = x0 - hw - slant * 0.5 + (w + 2 * hw + slant) * e;
    local n = max(3, min(20, floor(h / 2)));
    local sh = h / n;
    tint_toward(col, 0.33);
    for i = 0, n - 1 do
        local ya = y0 + i * sh;
        local inset = (i == 0 or i == n - 1) and 1 or 0;
        hband(dl, x0 + inset, x1 - inset, ya, ya + sh, cx0 + (0.5 - (i + 0.5) / n) * slant, hw, a);
    end
end

-- Glint across a stat row after a tick that gained something (t = seconds since the tick).
function M.row_glint(dl, x0, y0, x1, y1, t, col)
    if (not M.glint) then return; end
    M.glint_rect(dl, x0, y0, x1, y1, t, GLINT_DUR, col, 0.34 * M.k, 0.30, 60);
end

-- Scale factor for the heart / droplet right after a tick.
function M.pop_k(t)
    if (not M.pop or t < 0 or t > POP_DUR) then return 1; end
    return 1 + 0.38 * sin(pi * t / POP_DUR);
end

-- Soft glint across the whole window when HP and MP are both full.
function M.window_glint(dl, x0, y0, x1, y1, t, col)
    M.glint_rect(dl, x0, y0, x1, y1, t, RESTED_DUR, col, 0.30 * M.k, 0.28, 90);
end
function M.rested_active(now, at) return M.rested_fx and now - at >= 0 and now - at < RESTED_DUR; end

--[[
* Bar effects over the filled part: x..x+fw of a bar x..x+w, height h, corner radius r.
* remaining = seconds to the tick (charge-up), waiting = the bar is holding at full for the report.
--]]
local function star(dl, cx, cy, sz, c)
    local w = sz * 0.22;
    dl:AddTriangleFilled(E.vec(V1, cx, cy - sz), E.vec(V2, cx + w, cy), E.vec(V3, cx - w, cy), c);
    dl:AddTriangleFilled(E.vec(V1, cx, cy + sz), E.vec(V2, cx - w, cy), E.vec(V3, cx + w, cy), c);
    dl:AddTriangleFilled(E.vec(V1, cx - sz, cy), E.vec(V2, cx, cy - w), E.vec(V3, cx, cy + w), c);
    dl:AddTriangleFilled(E.vec(V1, cx + sz, cy), E.vec(V2, cx, cy + w), E.vec(V3, cx, cy - w), c);
end

-- Four thin spikes (a plus sign) of length len and base half-width wd, turned by ang radians.
local function spike4(dl, cx, cy, len, wd, ang, c)
    local ca, sa = cos(ang), sin(ang);
    for i = 0, 3 do
        local t = ang + i * pi * 0.5;
        local dx, dy = cos(t), sin(t);
        local px, py = -dy * wd, dx * wd;
        dl:AddTriangleFilled(E.vec(V1, cx + dx * len, cy + dy * len), E.vec(V2, cx - px, cy - py), E.vec(V3, cx + px, cy + py), c);
    end
end

function M.bar(dl, th, x, y, w, h, fw, r, remaining, waiting)
    if (fw < 2) then return; end
    local u, k, now = E.u, M.k, E.rt.now;
    local sc = E.rt.settings.scale or 1.0;
    local WH = E.WHITE;
    -- charge-up: the last 3 seconds warm the fill and grow a soft halo around the bar
    if (M.charge and not waiting and remaining > 0 and remaining < 3) then
        local c = smooth((3 - remaining) / 3);
        dl:AddRectFilled(E.vec(V1, x, y), E.vec(V2, x + fw, y + h), u(th.glow, c * 0.34 * k), r);
        dl:AddRect(E.vec(V1, x - 3 * sc, y - 3 * sc), E.vec(V2, x + w + 3 * sc, y + h + 3 * sc), u(th.glow, c * 0.20 * k), r + 3 * sc, 0, 2 * sc);
    end
    -- moving shine
    if (M.bar_shine) then
        local P = M.period;
        local t = now % P;
        local dur = 0.9;
        if (t < dur) then
            local e = smooth(t / dur);
            local hw = max(8, h * 2.4);
            local ix = min(r * 0.5, fw * 0.4);
            local cx = x - hw + (fw + 2 * hw) * e;
            tint_toward(nil, 0);
            hband(dl, x + ix, x + fw - ix, y + 1, y + h - 1, cx, hw, 0.55 * k);
        end
    end
    -- leading-edge star spark (only while the bar is not full): a slowly turning eight-point star with a
    -- breathing halo, a shimmer on its brightness and two tiny glints orbiting it
    if (M.bar_spark and fw < w - 1) then
        local cy = y + h * 0.5;
        local ex = x + fw;
        local a = k * M.sk;
        local tw = 0.72 + 0.16 * sin(now * 7.3) + 0.12 * sin(now * 11.9 + 1.3);       -- shimmer
        local br = 0.5 + 0.5 * sin(now * 2.6);                                          -- halo breathing
        local rr = (h * 1.1 + 3 * sc) * M.ss;
        dl:AddCircleFilled(E.vec(V1, ex, cy), rr * (1.7 + 0.25 * br), u(th.glow, (0.16 + 0.08 * br) * a), 16);
        dl:AddCircleFilled(E.vec(V1, ex, cy), rr * 1.05, u(th.glow, 0.26 * a * tw), 14);
        dl:AddCircleFilled(E.vec(V1, ex, cy), rr * 0.55, u(WH, min(1, 0.55 * a * tw)), 12);
        local ang = now * 0.9;                                                          -- slow turn
        spike4(dl, ex, cy, rr * 2.0, rr * 0.16, ang, u(WH, min(1, 0.80 * a * tw)));
        spike4(dl, ex, cy, rr * 1.25, rr * 0.12, -ang * 0.7 + 0.785, u(WH, min(1, 0.45 * a * tw)));
        dl:AddCircleFilled(E.vec(V1, ex, cy), rr * 0.26, u(WH, min(1, 0.95 * a)), 10);
        for i = 0, 1 do                                                                 -- two orbiting glints
            local oa = now * 1.7 + i * pi;
            local ox, oy = ex + cos(oa) * rr * 1.15, cy + sin(oa) * rr * 0.85;
            dl:AddCircleFilled(E.vec(V1, ox, oy), max(1, rr * 0.11), u(WH, min(1, 0.7 * a * (0.5 + 0.5 * sin(now * 5 + i * 2)))), 6);
        end
    end
end

--[[
* Number roll: shows `to` after counting from the previously shown value over ROLL_DUR.
* One small state table per key ('hp', 'mp'); no allocations after the first call per key.
--]]
local R = {};
local function shown(r, now)
    local t = (now - r.at) / ROLL_DUR;
    if (t >= 1) then return r.to; end
    if (t < 0) then t = 0; end
    local e = 1 - (1 - t) * (1 - t);
    return floor(r.from + (r.to - r.from) * e + 0.5);
end
function M.roll(key, v, now)
    if (not M.roll_on or type(v) ~= 'number') then R[key] = nil; return v; end
    local r = R[key];
    if (r == nil) then R[key] = { from = v, to = v, at = -1e9 }; return v; end
    if (r.to ~= v) then
        r.from = shown(r, now);
        r.to, r.at = v, now;
    end
    return shown(r, now);
end
function M.roll_reset() for k in pairs(R) do R[k] = nil; end end

--[[
* Header: breathing moon and floating "z z".
--]]
function M.moon_breath(now) return 0.82 + 0.18 * sin(now * 1.6); end
function M.moon_halo(dl, th, cx, cy, gr)
    local now = E.rt.now;
    dl:AddCircleFilled(E.vec(V1, cx + gr * 0.2, cy), gr * 1.55, E.u(th.moon, 0.09 * M.k * (M.moon_breath(now) - 0.6) / 0.4), 18);
end
-- Three z's drifting up and to the right, each fading in and out, staggered. They wander a little
-- side to side as they rise. M.zperiod = seconds for one z to rise.
function M.zs(dl, th, bx, by, gr)
    local now, k = E.rt.now, M.k;
    local tau = 2 * pi;
    for i = 0, 2 do
        local p = (now / M.zperiod + i / 3) % 1;
        local a = sin(pi * p) ^ 1.3 * 0.85 * (0.6 + 0.4 * k);
        if (a > 0.02) then
            local wob = sin(p * tau * 1.4 + i * 2.1) * gr * 0.30 + sin(p * tau * 0.6 + i) * gr * 0.12;
            dl:AddText(E.vec(V1, bx - gr * 0.2 + p * gr * 1.4 + wob, by + gr * 0.7 - p * gr * 1.55 + sin(p * tau * 1.1 + i * 1.7) * gr * 0.08), E.u(th.moon, a), 'z');
        end
    end
end

--[[
* Fully rested line: a few small stars twinkling to the right of the text (x, y = line origin,
* w = text width, h = text height).
--]]
local STARS = { { 0.0, -0.10, 0.34, 0.0 }, { 0.9, 0.35, 0.26, 0.33 }, { 1.8, 0.0, 0.30, 0.66 } };
function M.rested_stars(dl, th, x, y, w, h)
    if (not M.rested_fx) then return; end
    local now = E.rt.now;
    for i = 1, #STARS do
        local s = STARS[i];
        local p = (now / 2.2 + s[4]) % 1;
        local a = sin(pi * p);
        if (a > 0.03) then
            star(dl, x + w + h * (0.55 + s[1] * 0.75), y + h * (0.5 + s[2]), h * s[3] * (0.5 + 0.5 * a), E.u(th.glow, 0.9 * a));
        end
    end
end

--[[
* Food glyph: a small bowl with two steam wisps (animated when effects are on). (cx, cy) = centre of the
* glyph box, sz = text height. col = bowl color.
--]]
function M.bowl(dl, cx, cy, sz, col, steam_col, animate)
    local bw, bh = sz * 0.74, sz * 0.34;
    local top = cy + sz * 0.02;
    -- trapezoid body
    local xl, xr = cx - bw * 0.5, cx + bw * 0.5;
    local xl2, xr2 = cx - bw * 0.34, cx + bw * 0.34;
    local c = E.u(col, 1);
    dl:AddTriangleFilled(E.vec(V1, xl, top), E.vec(V2, xr, top), E.vec(V3, xr2, top + bh), c);
    dl:AddTriangleFilled(E.vec(V1, xl, top), E.vec(V2, xr2, top + bh), E.vec(V3, xl2, top + bh), c);
    dl:AddLine(E.vec(V1, xl - sz * 0.05, top), E.vec(V2, xr + sz * 0.05, top), c, max(1, sz * 0.09));
    -- steam
    local now = E.rt.now;
    for i = 0, 1 do
        local sx = cx + (i == 0 and -1 or 1) * bw * 0.2;
        local p = animate and ((now * 0.9 + i * 0.5) % 1) or 0.4;
        local a = animate and (sin(pi * p) * 0.8) or 0.55;
        local dx = animate and sin(p * 6.28 + i * 2) * sz * 0.07 or 0;
        local y0 = top - sz * 0.10 - p * sz * 0.10;
        dl:AddLine(E.vec(V1, sx + dx, y0), E.vec(V2, sx - dx * 0.5, y0 - sz * 0.26), E.u(steam_col, a), max(1, sz * 0.08));
    end
end

return M;
