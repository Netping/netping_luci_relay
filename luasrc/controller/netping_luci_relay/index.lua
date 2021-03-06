module("luci.controller.netping_luci_relay.index", package.seeall)

local config = "settings"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local util = require "luci.util"

function index()
	if nixio.fs.access("/etc/config/settings") then
		entry({"admin", "system", "relay"}, cbi("netping_luci_relay/relay"), "Relays", 30)
		entry({"admin", "system", "relay", "action"}, call("do_action"), nil).leaf = true
		entry({"admin", "system", "alerts"}, cbi("netping_luci_relay/alert"), nil).leaf = true
	end
end

function do_action(action, relay_id)
	local payload = {}
	payload["relay_data"] = luci.jsonc.parse(luci.http.formvalue("relay_data"))
	for _, k in pairs({".name", ".anonymous", ".type", ".index"}) do payload["relay_data"][k] = nil end
	payload["globals_data"] = luci.jsonc.parse(luci.http.formvalue("globals_data"))
	local commands = {
		add = function(...)
			local prototype = uci:get_all(config, "prototype")
			local globals = uci:get_all(config, "globals")
			local count = 0
			uci:foreach(config, "relay", function() count = count + 1 end)
			prototype["name"] = globals["default_name"] .. " " .. count
			prototype["dest_port"] = globals["default_port"]
			prototype["restart_time"] = globals["restart_time"]
			for _, k in pairs({".name", ".anonymous", ".type"}) do prototype[k] = nil end
			
			uci:section(config, "relay", nil, prototype)
			uci:commit(config)
		end,
		rename = function(relay_id, payload)
			util.perror("-- HEREE --")
			util.perror(payload["relay_data"]["name"])
			if payload["relay_data"]["name"] then
				uci:set(config, relay_id, "name", payload["relay_data"]["name"])
				uci:commit(config)
			end
		end,
		delete = function(relay_id, ...)
			-- protect embedded relays from deleting
			local embedded = uci:get(config, relay_id, "embedded") == "1"
			if not embedded then
				uci:delete(config, relay_id)
				uci:commit(config)
			end
		end,
		switch = function(relay_id, ...)
			local old_state = tonumber(uci:get(config, relay_id, "state"))
			local new_state = (old_state + 1) % 2
			uci:set(config, relay_id, "state", new_state)
			uci:commit(config)
		end,
		edit = function(relay_id, payloads)
			-- apply settings.<relay_id>
			local allowed_relay_options = util.keys(uci:get_all(config, "prototype"))
			for key, value in pairs(payloads["relay_data"]) do
				if util.contains(allowed_relay_options, key) then
					uci:set(config, relay_id, key, value)
				end
				uci:commit(config)
			end
			-- apply settings.globals
			local allowed_global_options = util.keys(uci:get_all(config, "globals"))
			for key, value in pairs(payloads["globals_data"]) do
				if util.contains(allowed_global_options, key) then
					if type(value) == "table" then
						uci:set_list(config, "globals", key, value)
					else
						uci:set(config, "globals", key, value)
					end
				end
				uci:commit(config)
			end
		end,
		default = function(...)
			http.prepare_content("text/plain")
			http.write("0")
		end
	}
	if commands[action] then
		commands[action](relay_id, payload)
		commands["default"]()
	end
end