--[[
* zztick - zzmodel.lua
*
* Pure-Lua healing (/heal) model: no Ashita dependencies, so it can be unit
* tested offline. Ashita-specific glue lives in zztick.lua.
--]]

local M = {};

M.STATUS_RESTING   = 33;  -- entity status while /heal is active
M.FIRST_TICK_DELAY = 20;  -- seconds from /heal until the first recovery tick
M.TICK_INTERVAL    = 10;  -- seconds between later recovery ticks

-- Buff ids (Windower/Ashita status effect ids).
M.BUFF = {
    DISEASE  = 8,
    CURSE_II = 20,   -- "zombie" curse
    PLAGUE   = 31,
    SIGNET   = 253,
    SANCTION = 256,
    SIGIL    = 268,
    FOOD     = 251,   -- 'Food' status (any eaten food)
    LEVEL_RESTRICTION = 143,  -- capped zones / BCNMs ("level is restricted to N")
    SJ_RESTRICTION    = 157,  -- support job disabled
    OBLIVISCENCE      = 260,  -- also disables the support job (LSB GetSLevel)
    LEVEL_SYNC        = 269,
};

-- Job ids.
M.JOB = { WHM = 3, BLM = 4, RDM = 5, SMN = 15, BLU = 16, SCH = 20, GEO = 21 };

--[[
* Clear Mind tiers: { level, MPwH base bonus, extra MP added per tick }.
* Retail values from BG-Wiki; the per-tick values match LSB's CLEAR_MIND mod.
--]]
local CM_VALUES = {
    { base = 3,  tick = 0 },  -- I
    { base = 6,  tick = 0 },  -- II
    { base = 9,  tick = 1 },  -- III
    { base = 12, tick = 1 },  -- IV
    { base = 15, tick = 2 },  -- V
    { base = 18, tick = 3 },  -- VI
};
M.CM_VALUES = CM_VALUES;

M.CLEAR_MIND_LEVELS = {
    retail = {
        [3]  = { 20, 35, 50, 65, 80, 96 },  -- WHM
        [4]  = { 15, 30, 45, 60, 75, 96 },  -- BLM
        [5]  = { 31, 53, 75, 91 },          -- RDM
        [15] = { 15, 30, 45, 60, 75, 91 },  -- SMN
        [20] = { 20, 35, 50, 65, 76, 91 },  -- SCH
        [21] = { 20, 40, 60, 80, 99 },      -- GEO
    },
    lsb = {
        [3]  = { 20, 35, 50, 65, 80, 96 },
        [4]  = { 15, 30, 45, 60, 75, 96 },
        [5]  = { 31, 53, 75, 91 },
        [15] = { 15, 30, 45, 60, 70, 91 },
        [20] = { 20, 35, 50, 65, 76, 96 },
        [21] = { 20, 40, 60, 80, 99 },
    },
};

local function floor(x) return math.floor(x); end

--[[
* Returns the Clear Mind tier (0-6) a job has at a level.
--]]
function M.clear_mind_tier_for(job, level, profile)
    local t = M.CLEAR_MIND_LEVELS[profile or 'retail'] or M.CLEAR_MIND_LEVELS.retail;
    local lv = t[job];
    if (lv == nil or level == nil) then return 0; end
    local tier = 0;
    for i = 1, #lv do
        if (level >= lv[i]) then tier = i; end
    end
    return tier;
end

--[[
* Highest Clear Mind tier across main and support job.
* BLU gets Clear Mind from set spells, which can't be read reliably, so the
* user supplies blu_tier (0-6) in the config.
--]]
function M.clear_mind_tier(main, main_lvl, sub, sub_lvl, profile, blu_tier)
    local a = M.clear_mind_tier_for(main, main_lvl, profile);
    local b = M.clear_mind_tier_for(sub, sub_lvl, profile);
    local tier = math.max(a, b);
    if ((main == M.JOB.BLU or sub == M.JOB.BLU) and (blu_tier or 0) > tier) then
        tier = math.min(6, blu_tier);
    end
    return tier;
end

function M.clear_mind_values(tier)
    local v = CM_VALUES[tier or 0];
    if (v == nil) then return 0, 0; end
    return v.base, v.tick;
end

--[[
* Level Sync / Level Restriction (LandSandBoat):
*  - scripts/effects/level_sync.lua and level_restriction.lua call target:levelRestriction(power).
*  - CLuaBaseEntity::levelRestriction sets main = min(restriction, real main level), then
*    SetSLevel(real sub level), then rebuilds stats and traits (BuildingCharTraitsTable, which uses
*    GetMLevel/GetSLevel, so Clear Mind follows the synced levels).
*  - CBattleEntity::SetSLevel caps the sub by map.SUBJOB_RATIO against the *effective* main:
*      0 = no sub, 1 = 1/2 (default), 2 = 2/3, 3 = equal; main level 1 keeps sub 1.
*  - GetSLevel is 0 under SJ Restriction or Obliviscence.
*  - healing.lua's Signet formula uses getMainLvl() = GetMLevel(), i.e. the synced level.
* Master Levels play no part in any of this.
--]]
function M.sub_cap(main_lv, sub_lv, ratio)
    main_lv, sub_lv = main_lv or 0, sub_lv or 0;
    ratio = ratio or 1;
    if (ratio == 0) then return 0; end
    local cap;
    if (ratio == 2) then cap = floor(main_lv * 2 / 3);
    elseif (ratio == 3) then cap = main_lv;
    else cap = floor(main_lv / 2); end
    if (sub_lv > cap) then return (main_lv == 1) and 1 or cap; end
    return sub_lv;
end

--[[
* Effective (synced/restricted) levels from what the client knows.
*
* i fields:
*   main, sub              job ids
*   real_main, real_sub    unrestricted job levels (IPlayer:GetJobLevel(job), from the 0x01B job info
*                          packet, which carries jobs.job[] = the real levels)
*   cur_main, cur_sub      IPlayer:GetMainJobLevel/GetSubJobLevel (0x061 char stats: GetMLevel/GetSLevel)
*   party_main             IParty:GetMemberMainJobLevel(0) (0x0DD/0x0DF: GetMLevel)
*   sync, restrict, sj_off buff flags (269 / 143 / 157 or 260)
*   ratio                  server SUBJOB_RATIO (default 1)
* Writes o.main, o.sub (effective), o.real_main, o.real_sub, o.capped (bool), o.reason, o.source.
--]]
function M.effective_levels(i, o)
    o = o or {};
    local cur_main = i.cur_main or 0;
    local rm = ((i.real_main or 0) > 0) and i.real_main or cur_main;
    local rs = ((i.real_sub or 0) > 0) and i.real_sub or (i.cur_sub or 0);
    local em, src = (cur_main > 0) and cur_main or rm, 'char stats (0x061)';
    if (i.sync or i.restrict) then
        -- whichever packet arrived first already carries the synced level
        local pm = i.party_main or 0;
        if (pm > 0 and pm < em) then em, src = pm, 'party list (0x0DD/0x0DF)'; end
    end
    if (rm > 0 and em > rm) then em = rm; end
    local es;
    if (i.sj_off or (i.sub or 0) == 0) then es = 0;
    else es = M.sub_cap(em, rs, i.ratio); end
    o.main, o.sub, o.real_main, o.real_sub = em, es, rm, rs;
    o.capped = rm > 0 and em < rm;
    o.reason = i.sync and 'Level Sync' or (i.restrict and 'Level Restriction' or (o.capped and 'level cap' or nil));
    o.source = src;
    return o;
end

--[[
* HP recovered on healing tick n (n = 1 is the first recovery, ~20s in).
*
* ctx fields: level (effective main level), maxhp, hp_bonus (gear/food hHP), signet (bool),
*             blocked (bool: Disease/Plague/Curse II), profile ('retail'|'lsb')
*
* LandSandBoat, scripts/effects/healing.lua (base branch, commit 5dce472, Oct 2026):
*   36  local healtime = effect:getTickCount()      -- incremented before onEffectTick
*   38  if healtime > 1 then                         -- so tick n has healtime = n + 1
*   75  (region <= LIMBUS and SIGNET) or (campaign region and SIGIL)
*   78  healHP = 10 + (3 * math.floor(target:getMainLvl() / 10)) +
*   79      (healtime - 2) * (1 + math.floor(target:getMaxHP() / 300)) + target:getMod(xi.mod.HPHEAL)
*   82  healHP = 10 + (healtime - 2) + target:getMod(xi.mod.HPHEAL)          -- no Signet
*   (status_effect_container.cpp TickEffects: IncrementElapsedTickCount() then OnEffectTick.)
*   => LSB Signet:  10 + 3*floor(lvl/10) + (n-1)*(1+floor(maxHP/300)) + hHP   (no cap; no Sanction)
*      LSB normal:  10 + (n-1) + hHP
* Retail (BG-Wiki): Signet level term 3*floor((lvl-1)/10), per-tick rate capped at 5.
*   At a level that is a multiple of 10 (10, 20 ... 70) the retail level term is 3 lower than LSB's.
*
* Returns base, level term, tick term, rate, bonus (all numbers; no allocation).
--]]
function M.hp_terms(n, ctx)
    n = math.max(1, n or 1);
    local bonus = ctx.hp_bonus or 0;
    if (ctx.signet) then
        local lvl = ctx.level or 1;
        local maxhp = ctx.maxhp or 0;
        local lvterm, rate;
        if (ctx.profile == 'retail') then
            lvterm = 3 * floor(math.max(0, lvl - 1) / 10);
            rate = math.min(5, 1 + floor(maxhp / 300));
        else
            lvterm = 3 * floor(lvl / 10);
            rate = 1 + floor(maxhp / 300);
        end
        return 10, lvterm, (n - 1) * rate, rate, bonus;
    end
    return 10, 0, n - 1, 1, bonus;
end

function M.hp_gain(n, ctx)
    if (ctx.blocked) then return 0; end
    local base, lvterm, tickterm, _, bonus = M.hp_terms(n, ctx);
    return math.max(0, base + lvterm + tickterm + bonus);
end

-- Which buff counts as "Signet" for the HP formula: LSB only checks SIGNET (253) and SIGIL (268), not SANCTION (256);
-- retail (BG-Wiki) treats Signet, Sanction and Sigil alike.
function M.signet_counts(profile, has_signet, has_sanction, has_sigil)
    if (profile == 'retail') then return has_signet or has_sanction or has_sigil; end
    return has_signet or has_sigil;
end

--[[
* MP recovered on healing tick n.
*
* ctx fields: maxmp, mp_bonus (gear/food hMP), cm_tier, blocked
*
* 12 + (n-1)*(1 + CM per-tick) + CM base + hMP   (BG-Wiki Clear Mind / LSB healing.lua)
--]]
function M.mp_gain(n, ctx)
    if (ctx.blocked) then return 0; end
    if ((ctx.maxmp or 0) <= 0) then return 0; end
    n = math.max(1, n or 1);
    local cm_base, cm_tick = M.clear_mind_values(ctx.cm_tier or 0);
    return math.max(0, 12 + (n - 1) * (1 + cm_tick) + cm_base + (ctx.mp_bonus or 0));
end

--[[
* Projection for tick n from current values.
--]]
function M.project(n, hp, mp, maxhp, maxmp, ctx)
    local ghp = M.hp_gain(n, ctx);
    local gmp = M.mp_gain(n, ctx);
    local php = math.min(maxhp, hp + ghp);
    local pmp = math.min(maxmp, mp + gmp);
    return {
        hp_gain = php - hp, mp_gain = pmp - mp,  -- effective (clamped) gain
        hp_raw = ghp, mp_raw = gmp,              -- unclamped formula value
        hp = php, mp = pmp,
    };
end

--[[
* Allocation-free projection: returns projected hp, mp, hp gain, mp gain.
--]]
function M.project4(n, hp, mp, maxhp, maxmp, ctx)
    -- capped at max, and never below the current value: if the client reports HP/MP above the
    -- max it knows about (max read from a different packet), the gain is 0, never negative.
    local php = math.max(hp, math.min(maxhp, hp + M.hp_gain(n, ctx)));
    local pmp = math.max(mp, math.min(maxmp, mp + M.mp_gain(n, ctx)));
    return php, pmp, php - hp, pmp - mp;
end

-- Signed bonus text: '+3', '-2', or '0' (never '+0' / '+-2').
function M.fmt_bonus(b)
    b = math.floor(b or 0);
    if (b == 0) then return '0'; end
    return string.format('%+d', b);
end

-- A stat is full when its max is known and current >= max.
function M.stat_full(cur, maxv)
    return maxv ~= nil and maxv > 0 and cur ~= nil and cur >= maxv;
end

-- Gain text: '+N' for a positive gain, '' otherwise (never '+0' or '+-N').
function M.fmt_gain(g)
    if (g == nil or g < 1) then return ''; end
    return string.format('+%d', math.floor(g));
end

--[[
* Number of ticks (starting with tick n) to reach full HP and MP.
* Returns ticks, or nil if it can never fill (no recovery possible).
--]]
function M.ticks_to_full(n, hp, mp, maxhp, maxmp, ctx, cap)
    cap = cap or 1000;
    local need_hp = hp < maxhp;
    local need_mp = maxmp > 0 and mp < maxmp;
    if (not need_hp and not need_mp) then return 0; end
    local count = 0;
    while (hp < maxhp or (maxmp > 0 and mp < maxmp)) do
        local ghp = M.hp_gain(n + count, ctx);
        local gmp = M.mp_gain(n + count, ctx);
        if ((hp < maxhp and ghp <= 0) or (maxmp > 0 and mp < maxmp and gmp <= 0)) then
            return nil;
        end
        hp = math.min(maxhp, hp + ghp);
        mp = math.min(maxmp, mp + gmp);
        count = count + 1;
        if (count >= cap) then return nil; end
    end
    return count;
end

--[[
* Tick tracker.
*
* Starts a timer when status turns to resting. The first tick is expected at first_delay plus
* part of one grid step (see _first_expect: it lands 20-23 s after /heal, not at exactly 20 s);
* later ticks every interval (or the learned 9/9/12 pattern).
*
* There is no predictive roll-over: when the expected tick time arrives the tracker WAITS
* (is_waiting() is true, remaining() is 0) until the server reports the tick (an HP/MP gain,
* see report()). Only that report advances the tick number and restarts the countdown.
* The one exception is when nothing can be observed (HP/MP full, or recovery blocked): the
* server sends no gain then, so the schedule coasts on the clock instead of waiting forever.
* After an accepted tick, a stat whose gain hasn't arrived yet is "pending" for confirm_win
* seconds, so projections treat the tick as already applied and the numbers don't flicker.
--]]
local Tracker = {};
Tracker.__index = Tracker;

function M.new_tracker(opts)
    opts = opts or {};
    local t = setmetatable({}, Tracker);
    t.first_delay  = opts.first_delay  or M.FIRST_TICK_DELAY;
    t.interval     = opts.interval     or M.TICK_INTERVAL;
    t.grace        = opts.grace        or 0;     -- seconds past expected time before rolling over (0 = immediately)
    t.confirm_win  = opts.confirm_win  or 4.0;   -- gains this soon after a modelled tick confirm it
    t.min_first    = opts.min_first    or 12.0;  -- earliest a first-tick gain is accepted
    t.min_gap      = opts.min_gap      or 7.0;   -- earliest a later tick gain is accepted after the previous one
    t.resync_min   = opts.resync_min   or 0.05;  -- ignore re-sync corrections smaller than this
    -- LSB checks status effects on a 3 s zone grid, so a 10 s healing tick lands on 9/9/12 s
    -- intervals. Once that pattern is seen in the observed gains, it is used for prediction.
    t.grid_predict = (opts.grid_predict ~= false);
    t.grid         = opts.grid or 3;
    t.grid_tol     = opts.grid_tol or 0.75;
    -- Once synced, a rise this much earlier than the predicted tick is not a tick (Cure/Regen/Refresh/food).
    t.early        = opts.early        or 2.5;
    -- Grid phase of the zone's 3 s effect check, learned from accepted ticks (client clock, mod grid).
    -- It outlives a single rest, so the first tick of the next rest can be predicted closely.
    t.phase        = nil;
    t.phase_miss   = 0;      -- consecutive first-tick predictions that missed the grid phase
    t.phase_off    = false;  -- phase prediction proved unreliable on this server: use the plain estimate
    t:reset();
    return t;
end

function Tracker:reset()
    self.resting      = false;
    self.rest_start   = nil;
    self.next_n       = 1;     -- index of the next recovery tick
    self.next_time    = nil;   -- expected time of the next tick
    self.last_tick    = nil;   -- time of the last tick (observed or modelled)
    self.unconfirmed  = false; -- last tick was modelled, not seen yet
    self.unconf_until = 0;
    self.pend_hp      = false; -- a tick happened but its HP hasn't shown up yet
    self.pend_mp      = false;
    self.pend_n       = 0;     -- tick index the pending gain belongs to
    self.pend_until   = 0;
    self.last_hp      = nil;
    self.last_mp      = nil;
    self.ticks_seen   = 0;
    self.last_gain_hp = nil;
    self.last_gain_mp = nil;
    self.last_exp_hp  = nil;
    self.last_exp_mp  = nil;
    self.synced       = false; -- true once a real tick has been observed
    self.first_expect = nil;   -- expected delay of this rest's first tick (see _first_expect)
    self.used_phase   = false; -- that expectation came from the learned grid phase
    self.resyncs      = 0;
    self.obs          = {};    -- tick index -> observed gain time (last few only)
    self.pattern      = nil;   -- learned { base = j, [0] = I(j-1), [1] = I(j), [2] = I(j+1) } or nil
    self.rep_hp       = 0;     -- last HP/MP delivered by the server packet (see Tracker:report)
    self.rep_mp       = 0;
    self.rep_until    = -1;    -- until then the frame poll must not read older client memory as a new gain
end

--[[
* 3 s grid pattern (LandSandBoat): CStatusEffectContainer::TickEffects runs only when the zone's
* m_EffectCheckTime (advanced in 3 s steps) has passed, and an effect ticks on the first check after
* start + k * 10 s. With delay d = fire - (start + 10k) in (0, 3]: d < 1 -> next interval 12 s,
* else 9 s, so intervals cycle 9, 9, 12 (30 s per 3 ticks). Learned from two consecutive observed
* intervals; anything that doesn't fit falls back to the plain interval.
--]]
function Tracker:_classify(iv)
    local short = self.grid * math.floor(self.interval / self.grid);
    if (math.abs(iv - short) <= self.grid_tol) then return 'S', short; end
    if (math.abs(iv - (short + self.grid)) <= self.grid_tol) then return 'L', short + self.grid; end
    return nil;
end

function Tracker:_learn(n)
    self.pattern = nil;
    if (not self.grid_predict or self.grid <= 0 or self.interval % self.grid ~= 1) then return; end
    local t0, t1, t2 = self.obs[n - 2], self.obs[n - 1], self.obs[n];
    if (t0 == nil or t1 == nil or t2 == nil or n - 2 < 1) then return; end
    local ca, a = self:_classify(t1 - t0);
    local cb, b = self:_classify(t2 - t1);
    if (ca == nil or cb == nil or (ca == 'L' and cb == 'L')) then return; end
    local c = 3 * self.interval - a - b;      -- one cycle = 3 intervals = 30 s
    if (self:_classify(c) == nil) then return; end
    self.pattern = { base = n, [0] = a, [1] = b, [2] = c };
end

function Tracker:interval_for(n)
    if (n <= 1) then return self.first_expect or (self.first_delay + self.grid / 2); end
    local pt = self.pattern;
    if (pt ~= nil) then
        -- interval ending at tick m is I(m); pattern[0] = I(base-1), [1] = I(base), [2] = I(base+1)
        return pt[(n - pt.base + 1) % 3];
    end
    return self.interval;
end

function Tracker:_observe(n, now)
    self.obs[n] = now;
    self.obs[n - 6] = nil;
    self:_learn(n);
end

--[[
* First tick of a rest. The server fires it on the first 3 s effect check at or after start + 20 s,
* so it lands 20-23 s after /heal (uniformly), never exactly at 20. Two cases:
*   - grid phase known (a tick was accepted earlier in this zone): predict the first grid check at or
*     after start + 20 s, which is accurate to the network jitter;
*   - otherwise expect the middle of the window (21.5 s), which halves the worst-case error.
--]]
function Tracker:_first_expect(start)
    local d = self.first_delay;
    if (self.grid > 0 and self.phase ~= nil and not self.phase_off) then
        local k = math.ceil((start + d - self.phase) / self.grid);
        self.used_phase = true;
        return self.phase + k * self.grid - start;
    end
    self.used_phase = false;
    return d + self.grid / 2;
end

-- The grid phase is per zone; call on zoning.
function Tracker:forget_phase()
    self.phase = nil;
    self.phase_miss = 0;
end

function Tracker:start(now, hp, mp)
    self:reset();
    self.resting      = true;
    self.rest_start   = now;
    self.next_n       = 1;
    self.first_expect = self:_first_expect(now);
    self.next_time    = now + self.first_expect;
    self.last_hp    = hp;
    self.last_mp    = mp;
end

-- Decide whether an HP/MP increase looks like a healing tick.
function Tracker:_looks_like_tick(now, dhp, dmp, hp, mp, maxhp, maxmp, ctx, n, confirming)
    if (not confirming) then
        if (self.last_tick == nil) then
            if (now - self.rest_start < self.min_first) then return false; end
        else
            if (now - self.last_tick < self.min_gap) then return false; end
        end
        -- Timing gate: once a real tick has been seen the schedule is trustworthy, so a rise well
        -- before the predicted time belongs to something else.
        if (self.synced and self.next_time ~= nil and now < self.next_time - self.early) then return false; end
    end
    local ehp = M.hp_gain(n, ctx);
    local emp = M.mp_gain(n, ctx);
    if (dhp > 0 and (dhp >= ehp * 0.5 or hp >= maxhp)) then return true; end
    if (dmp > 0 and (dmp >= emp * 0.5 or mp >= maxmp)) then return true; end
    return false;
end

function Tracker:_set_pending(now, n, hp, mp, maxhp, maxmp, ctx, want_hp, want_mp)
    self.pend_n     = n;
    self.pend_until = now + self.confirm_win;
    self.pend_hp    = want_hp and hp < maxhp and M.hp_gain(n, ctx) > 0;
    self.pend_mp    = want_mp and maxmp > 0 and mp < maxmp and M.mp_gain(n, ctx) > 0;
end

--[[
* Judge one HP/MP increase. Returns true if it was accepted as a healing tick (and re-syncs the
* timer to it). Shared by the frame poll (update) and the server-packet path (report).
--]]
function Tracker:_on_gain(now, dhp, dmp, hp, mp, maxhp, maxmp, ctx)
    local n = self.next_n;
    if (not self:_looks_like_tick(now, dhp, dmp, hp, mp, maxhp, maxmp, ctx, n, false)) then return false; end

    -- Was the grid-phase prediction for this first tick right? Compare modulo the grid, so a
    -- prediction that picked the neighbouring grid check still counts as a phase match.
    if (n == 1 and self.used_phase and self.next_time ~= nil) then
        local e = (now - self.next_time + self.grid / 2) % self.grid - self.grid / 2;
        if (math.abs(e) <= 0.5) then
            self.phase_miss = 0;
        else
            self.phase_miss = self.phase_miss + 1;
            if (self.phase_miss >= 2) then self.phase_off = true; end
        end
    end

    self.last_gain_hp = (dhp > 0) and dhp or 0;
    self.last_gain_mp = (dmp > 0) and dmp or 0;
    self.last_exp_hp  = M.hp_gain(n, ctx);
    self.last_exp_mp  = M.mp_gain(n, ctx);
    self.next_n = self.next_n + 1;
    self:_observe(n, now);
    -- The other stat's update may arrive a moment later.
    self:_set_pending(now, n, hp, mp, maxhp, maxmp, ctx, dhp <= 0, dmp <= 0);
    local target = now + self:interval_for(n + 1);
    if (self.next_time == nil or math.abs(target - self.next_time) >= self.resync_min) then
        self.next_time = target;
        self.resyncs = self.resyncs + 1;
    end
    self.last_tick   = now;
    if (self.grid > 0) then self.phase = now - math.floor(now / self.grid) * self.grid; end
    self.ticks_seen  = self.ticks_seen + 1;
    self.synced      = true;
    return true;
end

-- Can a tick change anything we could observe? (Full HP/MP or blocked recovery sends no gain.)
function Tracker:_gain_possible(hp, mp, maxhp, maxmp, ctx, n)
    if (maxhp > 0 and hp < maxhp and M.hp_gain(n, ctx) > 0) then return true; end
    if (maxmp > 0 and mp < maxmp and M.mp_gain(n, ctx) > 0) then return true; end
    return false;
end

--[[
* No predictive roll-over: a tick whose time has passed is simply waited for. The schedule only
* coasts forward on the clock when no gain could ever be reported (HP/MP full, recovery blocked),
* so the tick number and countdown don't freeze at 0.0 for the whole rest. Also expires stale
* pending flags.
--]]
function Tracker:_coast(now, hp, mp, maxhp, maxmp, ctx)
    while (self.next_time ~= nil and now >= self.next_time
           and not self:_gain_possible(hp, mp, maxhp, maxmp, ctx, self.next_n)) do
        local n = self.next_n;
        self.last_tick = self.next_time;
        self.next_time = self.next_time + self:interval_for(n + 1);
        self.next_n    = n + 1;
    end

    if ((self.pend_hp or self.pend_mp) and now > self.pend_until) then
        self.pend_hp = false;
        self.pend_mp = false;
    end
end

-- True while the expected tick time has passed and the server's report hasn't arrived yet.
-- (Valid after update()/report() has run for this frame.)
function Tracker:is_waiting(now)
    return self.resting and self.next_time ~= nil and now >= self.next_time;
end

-- Reset sweep: 1 right after a tick, fading to 0 over RESET_FX seconds.
M.RESET_FX = 0.12;
function Tracker:flash(now)
    if (self.last_tick == nil) then return 0; end
    local t = now - self.last_tick;
    if (t < 0 or t >= M.RESET_FX) then return 0; end
    return 1 - t / M.RESET_FX;
end

--[[
* Server-report path. Call from a packet_in handler with the HP/MP the server just sent and the time
* the packet arrived (not the frame time). Judges the change exactly like the frame poll does, but
* with the true arrival time and without waiting for the next frame. Returns true if the change was
* accepted as a healing tick.
*
* The frame poll keeps running as a fallback. After a report, it is told (rep_*) not to read older
* client memory as a fresh gain, so the same tick is never counted twice.
--]]
function Tracker:report(now, hp, mp, maxhp, maxmp, ctx)
    if (not self.resting) then return false; end
    local ohp, omp = self.last_hp or hp, self.last_mp or mp;

    self:_coast(now, ohp, omp, maxhp, maxmp, ctx);

    local dhp, dmp = hp - ohp, mp - omp;
    if (dhp > 0) then self.pend_hp = false; end
    if (dmp > 0) then self.pend_mp = false; end
    local took = false;
    if (dhp > 0 or dmp > 0) then
        took = self:_on_gain(now, dhp, dmp, hp, mp, maxhp, maxmp, ctx);
    end
    self.last_hp, self.last_mp = hp, mp;
    self.rep_hp, self.rep_mp, self.rep_until = hp, mp, now + 0.5;
    return took;
end

--[[
* Advance the tracker. Returns true if the player is resting.
* Allocation-free: safe to call every frame.
--]]
function Tracker:update(now, status, hp, mp, maxhp, maxmp, ctx)
    if (status ~= M.STATUS_RESTING) then
        if (self.resting) then self:reset(); end
        return false;
    end
    if (not self.resting) then
        self:start(now, hp, mp);
        return true;
    end

    -- A packet already reported newer values than the client memory shows yet: don't re-judge them.
    if (now <= self.rep_until) then
        if (hp < self.rep_hp) then hp = self.rep_hp; end
        if (mp < self.rep_mp) then mp = self.rep_mp; end
    end

    local dhp = hp - (self.last_hp or hp);
    local dmp = mp - (self.last_mp or mp);

    -- A gain clears the matching pending flag.
    if (dhp > 0) then self.pend_hp = false; end
    if (dmp > 0) then self.pend_mp = false; end

    if (dhp > 0 or dmp > 0) then
        self:_on_gain(now, dhp, dmp, hp, mp, maxhp, maxmp, ctx);
    end

    self:_coast(now, hp, mp, maxhp, maxmp, ctx);

    self.last_hp = hp;
    self.last_mp = mp;
    return true;
end

--[[
* Effective HP/MP for display: if a tick already happened by the clock but
* its gain hasn't arrived yet, include it so the numbers don't jump.
--]]
function Tracker:effective(hp, mp, maxhp, maxmp, ctx)
    if (self.pend_hp) then hp = math.min(maxhp, hp + M.hp_gain(self.pend_n, ctx)); end
    if (self.pend_mp) then mp = math.min(maxmp, mp + M.mp_gain(self.pend_n, ctx)); end
    return hp, mp;
end

-- Seconds until next tick (>= 0).
function Tracker:remaining(now)
    if (self.next_time == nil) then return 0; end
    return math.max(0, self.next_time - now);
end

-- Fraction of the current tick interval elapsed (0..1).
function Tracker:progress(now)
    if (self.next_time == nil) then return 0; end
    local iv = self:interval_for(self.next_n);
    local f = 1 - (self.next_time - now) / iv;
    if (f < 0) then f = 0; elseif (f > 1) then f = 1; end
    return f;
end

M.Tracker = Tracker;

--[[
* Wall clock (v1.3.1). os.clock() is CPU time by the Lua/C standard; only the MSVC runtime returns
* wall time since process start, so it is the wrong tool for a countdown. Prefers Ashita's
* ashita.time.clock() (std::chrono high_resolution_clock, micro/ms since epoch), then
* imgui.GetTime(), then os.clock as a last resort. Returns fn() -> seconds (rebased to 0), name.
--]]
function M.make_clock(at, im, osc)
    if (type(at) == 'table' and type(at.clock) == 'function') then
        local ok, c = pcall(at.clock);
        if (ok and type(c) == 'table' and (type(c.micro) == 'number' or type(c.ms) == 'number')) then
            if (type(c.micro) == 'number') then
                local base = c.micro;
                return function () return (at.clock().micro - base) / 1e6; end, 'ashita.time.clock (us)';
            end
            local base = c.ms;
            return function () return (at.clock().ms - base) / 1e3; end, 'ashita.time.clock (ms)';
        end
    end
    if (type(im) == 'table' and type(im.GetTime) == 'function') then
        local ok, v = pcall(im.GetTime);
        if (ok and type(v) == 'number') then return im.GetTime, 'imgui.GetTime'; end
    end
    return osc or os.clock, 'os.clock';
end

--[[
* Glide display bar (v1.3.1).
*
* The bar runs at a constant nominal speed of 1/L per second (L = the predicted length of the
* interval it shows: 20 s for the first tick, 10 s or the learned 9/9/12 pattern after). The error
* against the tracker's (re-synced) timeline is corrected by nudging the speed a little:
*   want  = clamp(1 + err / TAU_ERR, 1 - MAX_CORR, 1 + MAX_CORR)   (err in seconds, + = bar behind)
*   corr += (want - corr) * (1 - exp(-dt / TAU_RATE))               (eased, never a step)
* and only while more than END_WINDOW seconds are left: the last stretch of every interval always
* runs at nominal speed, so the bar never speeds up toward the end. Whatever error is left over is
* absorbed at the rollover (the new interval may start up to CATCHUP_MAX in, hidden by the reset
* sweep) and by the next interval's gentle correction.
* The bar never moves backward, never holds at full (it rolls over the moment it reaches 1), and a
* hitch (0.1-1 s frame) only advances it by DT_MAX and the lost time becomes ordinary error; after
* a gap longer than GAP (alt-tab, load screen) it realigns directly, forward only.
--]]
local G = { MAX_CORR = 0.15, TAU_ERR = 2.0, TAU_RATE = 0.35, END_WINDOW = 2.6,
            RESET_FX = 0.12, CATCHUP_MAX = 0.15, DT_MAX = 0.1, GAP = 1.0 };
M.GLIDE = G;
local Glide = {};
Glide.__index = Glide;

function M.new_glide()
    local b = setmetatable({}, Glide);
    b:reset();
    return b;
end

function Glide:reset()
    self.active, self.token = false, nil;
    self.p, self.k, self.L, self.base, self.corr, self.r = 0, 0, 10, 0.1, 1, 0.1;
    self.t, self.ro_t, self.rollovers, self.remaining = 0, -1e9, 0, 0;
end

-- Model time at which displayed interval k ends: T(n) = next_time, T(k) = T(n) +/- interval sums.
function Glide:_target(tr, k)
    local n, T = tr.next_n, tr.next_time;
    if (k >= n) then
        for j = n + 1, k do T = T + tr:interval_for(j); end
    else
        for j = n, k + 1, -1 do T = T - tr:interval_for(j); end
    end
    return T;
end

function Glide:_start(now, tr)
    self.active, self.token = true, tr.rest_start;
    self.k = tr.next_n;
    self.L = tr:interval_for(self.k); self.base = 1 / self.L;
    self.corr, self.r = 1, self.base;
    local ps = 1 - (tr.next_time - now) / self.L;
    if (ps < 0) then ps = 0; elseif (ps > 0.999) then ps = 0.999; end
    self.p, self.t = ps, now;
    self.remaining = (1 - self.p) * self.L;
    return self.p;
end

function Glide:update(now, tr)
    if (tr == nil or tr.next_time == nil or tr.next_n == nil) then self:reset(); return 0; end
    if (not self.active or tr.rest_start ~= self.token or math.abs(self.k - tr.next_n) > 3) then
        return self:_start(now, tr);
    end
    local dt = now - self.t;
    if (dt <= 0) then return self.p; end
    self.t = now;
    if (dt > G.GAP) then
        -- nobody was watching (alt-tab, load screen): realign forward-only, no animation
        if (self.k == tr.next_n) then
            local ps = 1 - (tr.next_time - now) / self.L;
            if (ps > 0.999) then ps = 0.999; end
            if (ps > self.p) then self.p = ps; end
            self.remaining = (1 - self.p) * self.L;
            return self.p;
        end
        return self:_start(now, tr);
    end
    if (dt > G.DT_MAX) then dt = G.DT_MAX; end   -- a hitch (0.1..1 s) becomes ordinary error

    local L = self.L;
    local err = ((1 - (self:_target(tr, self.k) - now) / L) - self.p) * L;
    local want = 1;
    if ((1 - self.p) * L > G.END_WINDOW) then
        want = 1 + err / G.TAU_ERR;
        if (want > 1 + G.MAX_CORR) then want = 1 + G.MAX_CORR; elseif (want < 1 - G.MAX_CORR) then want = 1 - G.MAX_CORR; end
    end
    self.corr = self.corr + (want - self.corr) * (1 - math.exp(-dt / G.TAU_RATE));
    self.r = self.base * self.corr;
    self.p = self.p + self.r * dt;

    if (self.p >= 1) then
        local carry = self.p - 1;
        self.ro_t = now - carry / self.r;
        self.rollovers = self.rollovers + 1;
        self.k = self.k + 1;
        self.L = tr:interval_for(self.k); self.base = 1 / self.L;
        self.r = self.base * self.corr;
        local ps = 1 - (self:_target(tr, self.k) - now) / self.L;   -- where the model already is
        local catch = math.min(ps, G.CATCHUP_MAX);
        if (catch > carry) then carry = catch; end
        if (carry > 0.999) then carry = 0.999; end
        self.p = carry;
    end
    self.remaining = (1 - self.p) * self.L;
    return self.p;
end

-- Reset sweep: 1 right after a rollover, fading to 0 over RESET_FX seconds.
function Glide:flash(now)
    local t = now - self.ro_t;
    if (t < 0 or t >= G.RESET_FX) then return 0; end
    return 1 - t / G.RESET_FX;
end

M.Glide = Glide;

--[[
* Display bar (v1.2.1): the bar's fill is kept separate from the model.
*
*   p      : displayed fill of the current interval (0..1), never decreases within it
*   d_n    : the tick index the current displayed interval ends at
*   target : the time the bar should reach 1 (the tracker's corrected next-tick time)
*
* Every frame the remaining fill is spread over the remaining time:
*   p += (1 - p) * min(1, dt / (target - t_prev))
* so a re-sync (target moves) changes the rate, never p itself, and the bar
* lands on exactly 1 at the corrected tick time. p goes back to 0 only at a
* rollover, i.e. after it reached 1 and the tracker has moved to the next tick.
* If the model is already past the displayed tick (early gain), the bar
* finishes quickly (FINISH seconds) and then rolls over, instead of jumping.
--]]
local Bar = {};
Bar.__index = Bar;
M.BAR_FINISH = 0.25;

function M.new_bar()
    local b = setmetatable({}, Bar);
    b:reset();
    return b;
end

function Bar:reset()
    self.active    = false;
    self.p         = 0;
    self.d_n       = 0;
    self.target    = 0;
    self.t_prev    = 0;
    self.token     = nil;
    self.rollovers = 0;
end

-- Advance p from t_prev to now toward target.
function Bar:_advance(now)
    local dt = now - self.t_prev;
    if (dt > 0 and self.p < 1) then
        local rem = self.target - self.t_prev;
        if (rem <= dt) then self.p = 1;
        else self.p = self.p + (1 - self.p) * (dt / rem); end
        if (self.p > 1) then self.p = 1; end
    end
    if (now > self.t_prev) then self.t_prev = now; end
end

--[[
* now       : clock
* n         : model's next tick index
* next_time : model's (corrected) next tick time
* token     : changes when a new rest starts (resets the bar)
* Returns the displayed fill (0..1).
--]]
function Bar:update(now, n, next_time, token)
    if (next_time == nil or n == nil) then self:reset(); return 0; end
    if (not self.active or token ~= self.token) then
        self.active, self.token = true, token;
        self.p, self.d_n, self.target, self.t_prev = 0, n, next_time, now;
        return 0;
    end
    -- At most a few rollovers per frame (normally zero or one).
    for _ = 1, 4 do
        if (n == self.d_n) then
            self.target = next_time;                       -- re-sync: only the rate changes
            if (self.target <= self.t_prev and self.p < 1) then
                self.target = now + M.BAR_FINISH;          -- target already passed: finish smoothly
            end
        elseif (n > self.d_n) then
            -- the displayed tick already happened: finish by its time, or quickly if that's later
            local fin = now + M.BAR_FINISH;
            if (self.target > fin) then self.target = fin; end
        else
            -- model went backwards (shouldn't happen): restart cleanly
            self.p, self.d_n, self.target, self.t_prev = 0, n, next_time, now;
            return 0;
        end
        local reach = self.target;
        self:_advance(math.min(now, reach));
        if (self.p >= 1 and n > self.d_n and now >= reach) then
            -- rollover at the moment the bar reached 1; carry the rest of the frame into the next interval
            self.rollovers = self.rollovers + 1;
            self.d_n = self.d_n + 1;
            self.p   = 0;
            self.t_prev = reach;
            self.target = (n == self.d_n) and next_time or (reach + M.BAR_FINISH);
            if (self.target <= reach) then self.target = reach + M.BAR_FINISH; end
        else
            self:_advance(now);
            break;
        end
    end
    return self.p;
end

M.Bar = Bar;

--[[
* Parses "HP/MP recovered while healing +N" from an item description.
* Only counts lines that start with the stat (skips conditional lines like
* "Set:", "Latent effect:", "Citizens of Bastok: ..."). Returns hp, mp.
--]]
function M.parse_heal_bonus(desc, loose)
    if (type(desc) ~= 'string' or desc == '') then return 0, 0; end
    if (loose) then
        -- food: the stat can sit mid-line ("MND+3 MP recovered while healing +2"); no conditional-line skipping
        local s = desc:gsub('\r', '');
        local hp, mp = 0, 0;
        s = s:gsub('HP and MP recovered%s+while%s+healing%s*%+(%d+)', function (v) hp = hp + tonumber(v); mp = mp + tonumber(v); return ''; end);
        s = s:gsub('HP recovered%s+while%s+healing%s*%+(%d+)', function (v) hp = hp + tonumber(v); return ''; end);
        s = s:gsub('MP recovered%s+while%s+healing%s*%+(%d+)', function (v) mp = mp + tonumber(v); return ''; end);
        return hp, mp;
    end
    local s = '\n' .. desc:gsub('\r', '');
    local hp, mp = 0, 0;
    for v in s:gmatch('\nHP and MP recovered%s+while%s+healing%s*%+(%d+)') do
        hp = hp + tonumber(v); mp = mp + tonumber(v);
    end
    for v in s:gmatch('\nHP recovered%s+while%s+healing%s*%+(%d+)') do
        hp = hp + tonumber(v);
    end
    for v in s:gmatch('\nMP recovered%s+while%s+healing%s*%+(%d+)') do
        mp = mp + tonumber(v);
    end
    return hp, mp;
end

--[[
* Does a buff list contain any of the ids?
--]]
function M.has_any_buff(buffs, ids)
    if (buffs == nil) then return false; end
    for _, b in pairs(buffs) do
        for _, id in ipairs(ids) do
            if (b == id) then return true; end
        end
    end
    return false;
end

function M.format_time(sec)
    if (sec == nil) then return '--'; end
    if (sec < 60) then return string.format('%.1fs', sec); end
    local m = math.floor(sec / 60);
    local s = math.floor(sec - m * 60);
    return string.format('%dm %02ds', m, s);
end

--[[
* Full-heal chime (v1.4.0). Plays once per rest when the condition is reached.
*   mode: 'both' (HP and MP full; MP ignored for jobs without MP), 'any', 'hp', 'mp'.
*   Sitting down with the condition already met does not count as reaching it, unless sit_full is
*   set (then it plays right away); otherwise it re-arms once the condition stops holding.
--]]
M.CHIME_MODES = { 'both', 'any', 'hp', 'mp' };

function M.chime_cond(mode, fhp, fmp, has_mp)
    if (mode == 'any') then return fhp or (has_mp and fmp) or false; end
    if (mode == 'hp') then return fhp and true or false; end
    if (mode == 'mp') then return (has_mp and fmp) and true or false; end
    return (fhp and (fmp or not has_mp)) and true or false;   -- 'both'
end

local Chime = {};
Chime.__index = Chime;
function M.new_chime() local c = setmetatable({}, Chime); c:reset(); return c; end
function Chime:reset() self.token, self.armed, self.fired, self.plays = nil, false, false, self.plays or 0; end
-- Returns true when the chime should play this frame. The caller passes a rest-session token
-- (debounced, so a one-frame read glitch does not look like a new rest).
function Chime:update(token, cond, sit_full)
    if (token ~= self.token) then
        self.token, self.fired = token, false;
        if (cond and sit_full) then self.fired, self.plays = true, self.plays + 1; return true; end
        self.armed = not cond;
        return false;
    end
    if (self.fired) then return false; end
    if (not cond) then self.armed = true; return false; end
    if (self.armed) then self.fired, self.plays = true, self.plays + 1; return true; end
    return false;
end
M.Chime = Chime;

--[[
* Full sparkle (v1.4.0): a fixed pool of star particles per row, refilled in place on trigger
* (no allocations after creation). Positions are fractions of the row (x across, y of text height).
--]]
M.SPARK_DUR = 0.6;
local Spark = {};
Spark.__index = Spark;
function M.new_spark(n)
    local sp = setmetatable({ t = -1e9, n = n or 7, seed = 12345, P = {} }, Spark);
    for i = 1, sp.n do sp.P[i] = { x = 0, y = 0, d = 0, s = 0 }; end
    return sp;
end
function Spark:_rnd()
    self.seed = (self.seed * 16807) % 2147483647;
    return self.seed / 2147483647;
end
function Spark:trigger(now)
    self.t = now;
    for i = 1, self.n do
        local p = self.P[i];
        p.x = (i - 0.5) / self.n + (self:_rnd() - 0.5) * 0.10;   -- spread across the row
        p.y = 0.05 + self:_rnd() * 0.9;
        p.d = self:_rnd() * 0.18;                                 -- staggered start
        p.s = 0.55 + self:_rnd() * 0.45;                          -- size, x text height * 0.5
    end
end
-- 0..1 progress while active, nil otherwise
function Spark:phase(now)
    local t = now - self.t;
    if (t < 0 or t >= M.SPARK_DUR) then return nil; end
    return t / M.SPARK_DUR;
end
M.Spark = Spark;

--[[
* Sound path (v1.4.1): absolute Windows path, backslashes only, exactly one separator between parts.
* Same shape as Ashita's own chatmon (addon.path .. '\sounds\' .. file); addon.path may or may not end
* with a separator, and may contain forward slashes.
--]]
function M.sound_path(addon_path, name)
    local base = tostring(addon_path or ''):gsub('/', '\\'):gsub('\\+$', '');
    name = tostring(name or ''):gsub('/', '\\'):gsub('^\\+', '');
    return base .. '\\sounds\\' .. name;
end

--[[
* Minimal WAV header check (v1.4.1). PlaySound handles plain PCM .wav reliably; returns a table
* { ok, fmt, channels, rate, bits, data_off, data_len, chunks, why } from the file bytes (header part
* is enough when data_len isn't needed exactly).
--]]
local function u16(b, i) local a, c = b:byte(i, i + 1); return a + c * 256; end
local function u32(b, i) local a, c, d, e = b:byte(i, i + 3); return a + c * 256 + d * 65536 + e * 16777216; end
function M.wav_info(b)
    local r = { ok = false, chunks = {} };
    if (type(b) ~= 'string' or #b < 44) then r.why = 'too short'; return r; end
    if (b:sub(1, 4) ~= 'RIFF' or b:sub(9, 12) ~= 'WAVE') then r.why = 'not a RIFF/WAVE file'; return r; end
    r.riff_size = u32(b, 5);
    local i = 13;
    while (i + 7 <= #b) do
        local id, sz = b:sub(i, i + 3), u32(b, i + 4);
        r.chunks[#r.chunks + 1] = id;
        if (id == 'fmt ') then
            r.fmt, r.channels, r.rate = u16(b, i + 8), u16(b, i + 10), u32(b, i + 12);
            r.byte_rate, r.align, r.bits = u32(b, i + 16), u16(b, i + 20), u16(b, i + 22);
            r.fmt_size = sz;
        elseif (id == 'data') then
            r.data_off, r.data_len = i + 8, sz;
            break;
        end
        i = i + 8 + sz + (sz % 2);
    end
    if (r.fmt == nil) then r.why = 'no fmt chunk'; return r; end
    if (r.data_off == nil) then r.why = 'no data chunk'; return r; end
    if (r.fmt ~= 1) then r.why = 'not PCM (format ' .. r.fmt .. ')'; return r; end
    if (r.bits ~= 16 and r.bits ~= 8) then r.why = r.bits .. '-bit (use 16-bit)'; return r; end
    r.ok = true;
    return r;
end

--[[
* Chime volume (v1.5). PlaySound has no volume control, so the volume is applied to the samples: the
* addon writes a scaled copy of the .wav (once per file and volume) and plays that. 100 = the file as
* it is. Below 100 the gain follows a square curve (50% is a quarter of the amplitude, which sounds
* about half as loud); above 100 it is linear up to 200 (x2, clipped at full scale).
--]]
function M.volume_gain(v)
    v = tonumber(v) or 100;
    if (v < 0) then v = 0; elseif (v > 200) then v = 200; end
    if (v <= 100) then return (v / 100) ^ 2; end
    return v / 100;
end

-- Returns a copy of the PCM .wav bytes b with every sample multiplied by gain, or nil, reason.
function M.wav_scale(b, gain)
    local w = M.wav_info(b);
    if (not w.ok) then return nil, w.why; end
    local off = w.data_off;
    local len = math.min(w.data_len, #b - off + 1);
    if (len < 0) then len = 0; end
    if (w.bits == 16) then len = len - len % 2; end
    local byte, char, floor = string.byte, string.char, math.floor;
    local parts = { b:sub(1, off - 1) };
    local i, last = off, off + len - 1;
    while (i <= last) do
        local j = math.min(i + 2047, last);
        local t, n = {}, 0;
        if (w.bits == 16) then
            for k = i, j, 2 do
                local lo, hi = byte(b, k, k + 1);
                local v = lo + hi * 256;
                if (v >= 32768) then v = v - 65536; end
                v = floor(v * gain + 0.5);
                if (v > 32767) then v = 32767; elseif (v < -32768) then v = -32768; end
                if (v < 0) then v = v + 65536; end
                n = n + 1; t[n] = char(v % 256, floor(v / 256));
            end
        else
            for k = i, j do
                local v = floor((byte(b, k) - 128) * gain + 0.5);
                if (v > 127) then v = 127; elseif (v < -128) then v = -128; end
                n = n + 1; t[n] = char(v + 128);
            end
        end
        parts[#parts + 1] = table.concat(t);
        i = j + 1;
    end
    parts[#parts + 1] = b:sub(off + len);
    return table.concat(parts);
end

return M;
