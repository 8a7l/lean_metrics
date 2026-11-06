-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_metrics: серверні метрики продуктивності
-- Читає дані на вимогу, не впливає на гру, не реєструє вузлів.

local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)

-- Локалізація функцій для швидкодії
local chat_send = minetest.chat_send_player
local after = minetest.after

-- Інтервал між зразками (сек)
local sample_interval = tonumber(
    minetest.settings:get("lean_metrics_sample_interval")) or 2.0
if sample_interval < 0.5 then sample_interval = 0.5 end

-- ============================================================
-- Стан вимірювань
-- ============================================================
local tick_count = 0       -- тіків з останнього зразка
local dtime_sum = 0        -- сума dtime (сек)
local dtime_max = 0        -- максимальний dtime (сек)

local cur_tps = 60.0
local cur_avg_dtime_ms = 16.67
local cur_max_dtime_ms = 16.67

-- ============================================================
-- Globalstep — ЄДИНЕ виправдане використання в цьому моді.
-- Мета: порахувати dtime для TPS. Подієвої альтернативи немає.
-- Навантаження: 2-3 арифметичні операції за тік (нікчемно).
-- ============================================================
minetest.register_globalstep(function(dtime)
    tick_count = tick_count + 1
    dtime_sum = dtime_sum + dtime
    if dtime > dtime_max then
        dtime_max = dtime
    end
end)

-- ============================================================
-- Періодичний семплер (self-rescheduling)
-- ============================================================
local function sample()
    if tick_count > 0 then
        local avg_dtime = dtime_sum / tick_count
        -- TPS = 1 / середній dtime (наприклад, 1 / 0.01667 = 60)
        cur_tps = 1 / avg_dtime
        cur_avg_dtime_ms = avg_dtime * 1000
        cur_max_dtime_ms = dtime_max * 1000
    end

    -- Скидання акумуляторів
    tick_count = 0
    dtime_sum = 0
    dtime_max = 0

    after(sample_interval, sample)
end

after(sample_interval, sample)

-- ============================================================
-- Збір метрик
-- ============================================================

-- Кількість активних Lua-сутностей
local function get_entity_count()
    local le = minetest.luaentities
    if type(le) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(le) do count = count + 1 end
    return count
end

-- Lua-пам'ять у МБ
local function get_lua_memory_mb()
    return collectgarbage("count") / 1024
end

-- Кількість зареєстрованих об'єктів
local function get_registered_counts()
    local nodes, items, tools = 0, 0, 0
    for _ in pairs(minetest.registered_nodes) do nodes = nodes + 1 end
    for _ in pairs(minetest.registered_items) do items = items + 1 end
    for _ in pairs(minetest.registered_tools) do tools = tools + 1 end
    return nodes, items, tools
end

-- Хелпер: топ модів за кількістю вузлів
local function get_top_mods_by_nodes(limit)
    local counts = {}
    for name in pairs(minetest.registered_nodes) do
        local mod = name:match("^([^:]+):") or "core"
        counts[mod] = (counts[mod] or 0) + 1
    end
    local list = {}
    for mod, count in pairs(counts) do
        list[#list + 1] = { mod = mod, count = count }
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    local result = {}
    for i = 1, math.min(limit, #list) do
        result[i] = list[i]
    end
    return result
end

-- Хелпер: топ модів за кількістю сутностей
local function get_top_mods_by_entities(limit)
    local counts = {}
    local le = minetest.luaentities
    if type(le) ~= "table" then return {} end
    for _, ent in pairs(le) do
        local name = ent.name
        if name then
            local mod = name:match("^([^:]+):") or name
            counts[mod] = (counts[mod] or 0) + 1
        end
    end
    local list = {}
    for mod, count in pairs(counts) do
        list[#list + 1] = { mod = mod, count = count }
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    local result = {}
    for i = 1, math.min(limit, #list) do
        result[i] = list[i]
    end
    return result
end

-- ============================================================
-- Вивід
-- ============================================================

local function cmd_metrics_main(name)
    local tps = cur_tps
    local avg = cur_avg_dtime_ms
    local mx = cur_max_dtime_ms
    local lag = minetest.get_server_max_lag() or 0
    local uptime = minetest.get_server_uptime() or 0
    local players = #minetest.get_connected_players()
    local entities = get_entity_count()
    local lua_mem = get_lua_memory_mb()
    local nodes, items, tools = get_registered_counts()
    local mods = #minetest.get_modnames()

    local hours = math.floor(uptime / 3600)
    local mins = math.floor((uptime % 3600) / 60)

    -- Реалістичні пороги для Luanti:
    -- TPS: ok >= 55, warn >= 40, bad < 40
    local tps_status = "BAD"
    if tps >= 55 then tps_status = "ok"
    elseif tps >= 40 then tps_status = "warn" end

    -- Avg dtime: ok <= 19, warn <= 26, bad > 26
    local avg_status = "BAD"
    if avg <= 19 then avg_status = "ok"
    elseif avg <= 26 then avg_status = "warn" end

    -- Max dtime: ok <= 50, warn <= 200, bad > 200
    local mx_status = "BAD"
    if mx <= 50 then mx_status = "ok"
    elseif mx <= 200 then mx_status = "warn" end

    chat_send(name, "=== Server Metrics ===")
    chat_send(name, string.format(
        "TPS:            %.1f / 60.0  [%s]",
        tps, tps_status))
    chat_send(name, string.format(
        "Avg dtime:      %.2f ms     [%s]",
        avg, avg_status))
    chat_send(name, string.format(
        "Max dtime:      %.2f ms     [%s]",
        mx, mx_status))
    chat_send(name, string.format(
        "Max lag:        %.2f s", lag))
    chat_send(name, string.format(
        "Uptime:         %dh %dm", hours, mins))
    chat_send(name, string.format(
        "Players:        %d", players))
    chat_send(name, string.format(
        "Lua entities:   %d", entities))
    chat_send(name, string.format(
        "Lua memory:     %.2f MB", lua_mem))
    chat_send(name, string.format(
        "Mods loaded:    %d", mods))
    chat_send(name, string.format(
        "Registered:     %d nodes, %d items, %d tools",
        nodes, items, tools))
    chat_send(name, "See: /metrics mods | entities | help")
end

local function cmd_metrics_mods(name)
    local top = get_top_mods_by_nodes(10)
    chat_send(name, "=== Top mods by node count ===")
    for i, entry in ipairs(top) do
        chat_send(name, string.format(
            "%2d. %-25s %d", i, entry.mod, entry.count))
    end
end

local function cmd_metrics_entities(name)
    local top = get_top_mods_by_entities(10)
    local total = get_entity_count()
    chat_send(name, string.format(
        "=== Top mods by entity count (total %d) ===", total))
    if #top == 0 then
        chat_send(name, "(no entities)")
        return
    end
    for i, entry in ipairs(top) do
        chat_send(name, string.format(
            "%2d. %-25s %d", i, entry.mod, entry.count))
    end
end

local function cmd_metrics_help(name)
    chat_send(name, "=== /metrics help ===")
    chat_send(name, "/metrics           main metrics")
    chat_send(name, "/metrics mods      top mods by node count")
    chat_send(name, "/metrics entities  top mods by entity count")
    chat_send(name, "/metrics help      this help")
end

-- ============================================================
-- Реєстрація привілею та команди
-- ============================================================

minetest.register_privilege("metrics", {
    description = S("View server performance metrics"),
    give_to_singleplayer = true,
})

minetest.register_chatcommand("metrics", {
    params = "[mods|entities|help]",
    description = S("Show server performance metrics"),
    privs = { metrics = true },
    func = function(name, param)
        param = (param or ""):lower()
        param = param:match("^%s*(.-)%s*$") or ""
        if param == "" then
            cmd_metrics_main(name)
        elseif param == "mods" then
            cmd_metrics_mods(name)
        elseif param == "entities" then
            cmd_metrics_entities(name)
        elseif param == "help" then
            cmd_metrics_help(name)
        else
            return false, "Unknown subcommand. Try /metrics help"
        end
        return true
    end,
})

-- ============================================================
-- Лог завантаження
-- ============================================================
minetest.log("action", string.format(
    "[%s] loaded (sample interval %.1fs)", modname, sample_interval))