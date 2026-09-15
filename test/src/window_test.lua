-- AntiBug's window entry: what the Start menu reads, what the compositor asks
-- before opening it, and the trust shape the window depends on.
--
-- AntiBug runs builds and test suites on the server through its runner's
-- broad policy, whoever logged on. Under a terminal.ssh host anyone with an
-- account logs on, so the entry names `meta.requires: windows.admin` and the
-- base's compositor asks the logged-on person's scope before opening it. An
-- entry without the field opens for everyone, silently — the shell's
-- admin_windows_test checked this while AntiBug lived in the shell.
local test = require("test")
local registry = require("registry")
local images = require("images")

local function meta_of(id: string): any
    local entry, err = registry.get(id)
    test.is_nil(err, id .. ": " .. tostring(err))
    local record: any = entry
    return record and type(record.meta) == "table" and record.meta or {}
end

local function define_tests()
    test.describe("AntiBug window entry", function()
        test.it("is AntiBug in Programs with Find's picture, for administrators only", function()
            local meta = meta_of("windows.antibug:window")
            test.eq(table.concat({tostring(meta.type), tostring(meta.title), tostring(meta.group), tostring(meta.image),
                tostring(meta.pixel_render), tostring(meta.pixel_state)}, "|"),
                "tui_desktop.window|AntiBug|Programs|find|windows.shell.sdk:render|windows.antibug:window")
            test.eq(meta.requires, "windows.admin", "AntiBug must name windows.admin in meta.requires")
            for _, size in ipairs({32, 16}) do
                local picture, why = images.get("find", size)
                test.not_nil(picture, "find@" .. tostring(size) .. ": " .. tostring(why))
            end
        end)

        test.it("the window may call only the runner, and the runner runs under its own actor with the wide policy", function()
            local window: any = assert(registry.get("windows.antibug:window"))
            local window_policies = (window.data and window.data.security and window.data.security.policies) or {}
            test.eq(table.concat(window_policies, ","), "windows.antibug:window_scope,windows.antibug:runner_call")

            local call: any = assert(registry.get("windows.antibug:runner_call"))
            local grant: any = call.data and call.data.policy or {}
            test.eq(table.concat(grant.actions or {}, ",") .. " on " .. table.concat(grant.resources or {}, ","),
                "funcs.call on windows.antibug:runner", "the window's one funcs grant names the runner alone")

            local runner: any = assert(registry.get("windows.antibug:runner"))
            local security: any = runner.data and runner.data.security or {}
            test.eq(tostring(security.actor and security.actor.id), "windows.antibug:runner")
            test.eq(table.concat(security.policies or {}, ","), "windows.antibug:runner_policy")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
