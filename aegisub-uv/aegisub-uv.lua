--[[
README
Module to manage the the uv environments for Aegisub scripts written in python, requiring complex dependency trees.
]]

local havedepCtrl, DependencyControl, depCtrl = pcall(require, 'l0.DependencyControl')
local petzutil, re, ConfigHandler

local moduleVersion = "0.0.1"

if havedepCtrl then
  depCtrl = DependencyControl({
    name = 'aegisub-uv',
    version = moduleVersion,
    description = [[Managing uv environments for Aegisub scripts.]],
    author = "Zahuczky",
    url = "https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts",
    feed = "https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/blob/main/DependencyControl.json",
    moduleName = 'zah.aegisub-uv',
    {
      "petzku.util",
      "aegisub.re",
      {
        "a-mo.ConfigHandler",
        version = "1.1.4",
        url = "https://github.com/TypesettingTools/Aegisub-Motion",
        feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/depCtrl/DependencyControl.json",
      },
    }
  })

  petzutil, re, ConfigHandler = depCtrl:requireModules()
else
  petzutil = require("petzku.util") -- this is only used for petzutil.io.run_cmd, nothing else comes from here
  re = require("aegisub.re")
  ConfigHandler = require("a-mo.ConfigHandler")
end

local DEFAULT_CONFIG = {
  provider = {
    kind = {
      value = "", -- either "system" or "managed"
      config = true,
    },
  }
}

local function is_unset(value)
  return value == nil or value == ""
end

local UvManager = {}
UvManager.__index = UvManager

function UvManager:new()
  local configFile = havedepCtrl and depCtrl.configFile or "zah.aegisub-uv.json"
  local configDir = havedepCtrl and depCtrl.configDir or "?user/automation/include/zah"

  local obj = {
    config = ConfigHandler(DEFAULT_CONFIG, configFile, false, moduleVersion, configDir),
  }

  obj.config:read()

  setmetatable(obj, self)

  aegisub.debug.out("UvManager initialized with provider kind: " .. (obj.config.configuration.provider.kind or "unset") .. "\n")

  return obj
end

function UvManager:findSystemUv()
  -- check if the host os has uv installed and available in path
  local output, status, reason, exit_code = petzutil.io.run_cmd("uv --version", false)
  if status and exit_code == 0 then
    return "system"
  end
  return nil
end

-- check if managed uv exists, its "?user/include/zah/uv.exe" on windows, and "?user/include/zah/uv" on linux/mac
function UvManager:findManagedUv()
  local zah_uv_dir = aegisub.decode_path("?user/automation/include/zah")
  local uv_executable = aegisub.decode_path("?user/automation/include/zah/uv.exe")

  aegisub.debug.out("Checking for managed uv at: " .. uv_executable .. "\n")

  -- check if file exists via io.open
  local file = io.open(uv_executable, "r")
  if file then
    file:close()
    return "managed"
  end

  return nil
end

function UvManager:get_provider_kind()
  return self.config.configuration.provider.kind
end

function UvManager:set_provider_kind(kind)
  self.config.configuration.provider.kind = kind
  self.config:write()
end

function UvManager:select_system_or_managed_uv_dialog(systemUv, managedUv)
  -- if there is no provider set (first start) inform the user, and show system and managed uv status (have or not)
  -- make the user select. If they select managed, but its not there, download from "https://releases.astral.sh/github/uv/releases/download/0.11.23/uv-x86_64-pc-windows-msvc.zip" and unzip to "?user/include/zah"

  -- create dialog
  local select_system_or_managed_uv = {
    main_label = {
      class = "label",
      x = 0, y = 0, width = 4, height = 1,
      label = "Select uv provider kind:"
    },

    system_uv_status = {
      class = "label",
      x = 0, y = 1, width = 4, height = 1,
      label = "System uv: " .. (systemUv and "found" or "not found")
    },

    managed_uv_status = {
      class = "label",
      x = 0, y = 2, width = 4, height = 1,
      label = "Managed uv: " .. (managedUv and "found" or "not found")
    },

    recommended_label = {
      class = "label",
      x = 0, y = 4, width = 4, height = 1,
      label = "Managed uv is recommended for most users."
    },

    warning_label = {
      class = "label",
      x = 0, y = 5, width = 4, height = 2,
      label = "Choose system uv only if you know what you are doing and uv is available in PATH."
    },

    download_notice_label = {
      class = "label",
      x = 0, y = 7, width = 4, height = 3,
      label = "If you choose managed uv and it is not found, it will be downloaded inside Aegisub. It will not conflict with other Python or uv installations."
    },
  }

  local btn, res = aegisub.dialog.display(select_system_or_managed_uv, {"system_uv_button", "managed_uv_button", "close_button"})
  if btn == "system_uv_button" then
    self:set_provider_kind("system")
    return "system"
  end

  if btn == "managed_uv_button" then

    -- if managedUv is not found, download and install it
    if not managedUv then
      local download_url = "https://releases.astral.sh/github/uv/releases/download/0.11.23/uv-x86_64-pc-windows-msvc.zip"
      local zah_uv_dir = aegisub.decode_path("?user/automation/include/zah")
      local zip_file = aegisub.decode_path("?user/automation/include/zah/uv.zip")

      -- download the zip file
      local output, status, reason, exit_code = petzutil.io.run_cmd('curl -L -o "' .. zip_file .. '" "' .. download_url .. '"', false)
      if not status or exit_code ~= 0 then
        aegisub.debug.out("Failed to download managed uv: " .. (reason or "unknown error") .. "\n")
        aegisub.dialog.display({{class = "label", label = "Failed to download managed uv: " .. (reason or "unknown error")}}, {"OK"})
        return nil
      end

      -- unzip the file
      local output, status, reason, exit_code = petzutil.io.run_cmd('powershell -Command "Expand-Archive -Path \'' .. zip_file .. '\' -DestinationPath \'' .. zah_uv_dir .. '\'"', false)
      if not status or exit_code ~= 0 then
        aegisub.debug.out("Failed to unzip managed uv: " .. (reason or "unknown error") .. "\n")
        aegisub.dialog.display({{class = "label", label = "Failed to unzip managed uv: " .. (reason or "unknown error")}}, {"OK"})
        return nil
      end

      -- delete the zip file
      os.remove(zip_file)

      aegisub.debug.out("Managed uv downloaded and installed successfully.\n")
    end

    self:set_provider_kind("managed")
    return "managed"
  end

  if btn == "close_button" then
    return nil
  end

  return nil
end

function UvManager:run_uv(opts)

  -- check if uv is managed of system
  local kind = self:get_provider_kind()

  if kind == "system" then
    -- run uv from system path
    local output, status, reason, exit_code = petzutil.io.run_cmd("uv " .. opts, false)
    if exit_code ~= 0 then
      self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())
    end
    return {
      output = output,
      status = status,
      reason = reason,
      exit_code = exit_code,
    }
    
  end

  if kind == "managed" then
    -- run uv from managed path
    local uv_executable = aegisub.decode_path("?user/automation/include/zah/uv.exe")
    local output, status, reason, exit_code = petzutil.io.run_cmd('"' .. uv_executable .. '" ' .. opts, false)
    if exit_code ~= 0 then
      self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())
    end
    return {
      output = output,
      status = status,
      reason = reason,
      exit_code = exit_code,
    }
  end

end


function UvManager:ensure_provider()
  local kind = self.config.configuration.provider.kind

  if is_unset(kind) then
    aegisub.debug.out("Provider kind is unset.\n")
    kind = self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())
  end

  local result = self:run_uv("--version")

  aegisub.debug.out("uv --version output: %s\n", tostring(result.output))
  aegisub.debug.out("uv --version status: %s\n", tostring(result.status))
  aegisub.debug.out("uv --version reason: %s\n", tostring(result.reason))
  aegisub.debug.out("uv --version exit_code: %s\n", tostring(result.exit_code))

  return {
    kind = kind,
    status = result.status,
    output = result.output,
    reason = result.reason,
    exit_code = result.exit_code,
  }
end








local M = {}

M.version = moduleVersion

function M.new()
  return UvManager:new()
end

if havedepCtrl then
  return depCtrl:register(M)
else
  return M
end