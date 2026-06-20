--[[
README
Module to manage the the uv environments for Aegisub scripts written in python, requiring complex dependency trees.
]]

local havedepCtrl, DependencyControl, depCtrl = pcall(require, 'l0.DependencyControl')
local petzutil, re, ConfigHandler

local moduleVersion = "0.0.1"

local zah_root = "?user/automation/include/zah"
local aegisub_uv_root = "?user/automation/include/zah/aegisub-uv"
local venv_root = "?user/automation/include/zah/aegisub-uv/envs"

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
  },
  debug = {
    enabled = {
      value = false,
      config = true,
    },
  },
}

local pathsep = petzutil.io.pathsep
local is_windows = pathsep == "\\"
local uv_exe = is_windows and "uv.exe" or "uv"
local debug_enabled = false

local function is_unset(value)
  return value == nil or value == ""
end

local function print_run_cmd_result(result)
  if not debug_enabled then
    return
  end
  aegisub.debug.out("output: %s\n", tostring(result.output))
  aegisub.debug.out("status: %s\n", tostring(result.status))
  aegisub.debug.out("reason: %s\n", tostring(result.reason))
  aegisub.debug.out("exit_code: %s\n", tostring(result.exit_code))
end

local UvManager = {}
UvManager.__index = UvManager

function UvManager:new()
  local configFile = havedepCtrl and depCtrl.configFile or "zah.aegisub-uv.json"
  local configDir = havedepCtrl and depCtrl.configDir or zah_root

  local obj = {
    config = ConfigHandler(DEFAULT_CONFIG, configFile, false, moduleVersion, configDir),
  }

  obj.config:read()

  setmetatable(obj, self)

  aegisub.debug.out("UvManager initialized with provider kind: " ..
  (obj.config.configuration.provider.kind or "unset") .. "\n")
  debug_enabled = obj.config.configuration.debug.enabled or false

  return obj
end

function UvManager:findSystemUv()
  -- check if the host os has uv installed and available in path
  local output, status, reason, exit_code = petzutil.io.run_cmd("uv --version", debug_enabled)
  if status and exit_code == 0 then
    return "system"
  end
  return nil
end

-- check if managed uv exists, its "?user/include/zah/uv.exe" on windows, and "?user/include/zah/uv" on linux/mac
function UvManager:findManagedUv()
  local zah_uv_dir = aegisub.decode_path(zah_root)
  local uv_executable = aegisub.decode_path(zah_root .. "/" .. uv_exe)

  aegisub.debug.out("Checking for managed uv at: " .. uv_executable .. "\n")

  -- check if file exists via io.open
  local file = io.open(uv_executable, "rb")
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
      x = 0,
      y = 0,
      width = 4,
      height = 1,
      label = "Select uv provider kind:"
    },

    system_uv_status = {
      class = "label",
      x = 0,
      y = 1,
      width = 4,
      height = 1,
      label = "System uv: " .. (systemUv and "found" or "not found")
    },

    managed_uv_status = {
      class = "label",
      x = 0,
      y = 2,
      width = 4,
      height = 1,
      label = "Managed uv: " .. (managedUv and "found" or "not found")
    },

    recommended_label = {
      class = "label",
      x = 0,
      y = 4,
      width = 4,
      height = 1,
      label = "Managed uv is recommended for most users."
    },

    warning_label = {
      class = "label",
      x = 0,
      y = 5,
      width = 4,
      height = 2,
      label = "Choose system uv only if you know what you are doing and uv is available in PATH."
    },

    download_notice_label = {
      class = "label",
      x = 0,
      y = 7,
      width = 4,
      height = 3,
      label =
      "If you choose managed uv and it is not found, it will be downloaded inside Aegisub. It will not conflict with other Python or uv installations."
    },
  }

  local btn, res = aegisub.dialog.display(select_system_or_managed_uv,
    { "system_uv_button", "managed_uv_button", "close_button" })
  if btn == "system_uv_button" then
    self:set_provider_kind("system")
    return "system"
  end

  if btn == "managed_uv_button" then
    -- if managedUv is not found, download and install it
    if not managedUv then
      local download_url = "https://releases.astral.sh/github/uv/releases/download/0.11.23/uv-x86_64-pc-windows-msvc.zip"
      local zah_uv_dir = aegisub.decode_path(zah_root)
      local zip_file = aegisub.decode_path(zah_root .. "/uv.zip")

      -- download the zip file
      local output, status, reason, exit_code = petzutil.io.run_cmd(
      'curl -L -o "' .. zip_file .. '" "' .. download_url .. '"', debug_enabled)
      if not status or exit_code ~= 0 then
        aegisub.debug.out("Failed to download managed uv: " .. (reason or "unknown error") .. "\n")
        aegisub.dialog.display(
        { { class = "label", label = "Failed to download managed uv: " .. (reason or "unknown error") } }, { "OK" })
        return nil
      end

      -- unzip the file
      local output, status, reason, exit_code = petzutil.io.run_cmd(
      'powershell -Command "Expand-Archive -Path \'' .. zip_file .. '\' -DestinationPath \'' .. zah_uv_dir .. '\'"',
        debug_enabled)
      if not status or exit_code ~= 0 then
        aegisub.debug.out("Failed to unzip managed uv: " .. (reason or "unknown error") .. "\n")
        aegisub.dialog.display(
        { { class = "label", label = "Failed to unzip managed uv: " .. (reason or "unknown error") } }, { "OK" })
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

function UvManager:run_uv(args)
  -- check if uv is managed of system
  local kind = self:get_provider_kind()

  if kind == "system" then
    -- run uv from system path
    local output, status, reason, exit_code = petzutil.io.run_cmd("uv " .. args, debug_enabled)
    -- if exit_code ~= 0 then
    --   self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())
    -- end
    return {
      output = output,
      status = status,
      reason = reason,
      exit_code = exit_code,
    }
  end

  if kind == "managed" then
    -- run uv from managed path
    local uv_executable = aegisub.decode_path(zah_root .. "/" .. uv_exe)
    local output, status, reason, exit_code = petzutil.io.run_cmd('"' .. uv_executable .. '" ' .. args, debug_enabled)
    -- if exit_code ~= 0 then
    --   self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())
    -- end
    return {
      output = output,
      status = status,
      reason = reason,
      exit_code = exit_code,
    }
  end

  return {
    output = "",
    status = false,
    reason = "invalid provider kind: " .. tostring(kind),
    exit_code = -1,
  }
end

function UvManager:ensure_provider()
  local kind = self.config.configuration.provider.kind

  if is_unset(kind) then
    aegisub.debug.out("Provider kind is unset.\n")
    kind = self:select_system_or_managed_uv_dialog(self:findSystemUv(), self:findManagedUv())

    if is_unset(kind) then
      return {
        kind = nil,
        status = false,
        reason = "provider selection cancelled",
        exit_code = -1,
      }
    end
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

-- UvEnv XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

local UvEnv = {}
UvEnv.__index = UvEnv

--[[
Create an environment object from a spec.

Expected spec shape:

{
  id = "zah.autoclip",
  python = "3.12",
  packages = {
    "ass-autoclip",
    "vapoursynth",
  },
  checks = {
    imports = {
      "vapoursynth",
    },
  },
}
]]
function UvManager:env(spec)
  spec = spec or {}

  if is_unset(spec.id) then
    aegisub.debug.out("UvEnv spec is missing required field: id\n")
    return nil
  end

  if is_unset(spec.python) then
    spec.python = "3.12"
  end

  if spec.packages == nil then
    spec.packages = {}
  end

  if type(spec.packages) ~= "table" then
    aegisub.debug.out("UvEnv spec.packages must be a table.\n")
    return nil
  end

  if spec.checks == nil then
    spec.checks = {}
  end

  local obj = {
    manager = self,
    spec = spec,
  }

  setmetatable(obj, UvEnv)
  return obj
end

function UvEnv:id()
  return self.spec.id
end

function UvEnv:venv_dir()
  if self:id() then
    return aegisub.decode_path(venv_root .. "/" .. self:id() .. "/" .. ".venv")
  end
end

function UvEnv:python_exe()
  if is_windows then
    return self:venv_dir() .. "/Scripts/python.exe"
  else
    return self:venv_dir() .. "/bin/python"
  end
end

function UvEnv:script_exe(name)
  if is_windows then
    return self:venv_dir() .. pathsep .. "Scripts" .. pathsep .. name .. ".exe"
  else
    return self:venv_dir() .. pathsep .. "bin" .. pathsep .. name
  end
end

function UvEnv:run_script(name, args)
  local output, status, reason, exit_code =
      petzutil.io.run_cmd('"' .. self:script_exe(name) .. '" ' .. args, debug_enabled)

  return {
    output = output,
    status = status,
    reason = reason,
    exit_code = exit_code,
  }
end

function UvEnv:exists()
  local python_exe = self:python_exe()
  local file = io.open(python_exe, "rb")
  if file then
    file:close()
    return true
  end
  aegisub.debug.out("UvEnv python executable not found at: " .. python_exe .. "\n")
  return false
end

function UvEnv:create()
  local provider = self.manager:ensure_provider()
  if not provider.status then
    aegisub.debug.out("UvEnv:ensure_provider failed: %s\n", tostring(provider.reason or "unknown error"))
    return provider
  end

  local result = self.manager:run_uv(
    'venv "' .. self:venv_dir() .. '" --python ' .. self.spec.python
  )

  print_run_cmd_result(result)
  return result
end

function UvEnv:run_python(args)
  local python_exe = self:python_exe()

  local output, status, reason, exit_code =
      petzutil.io.run_cmd('"' .. python_exe .. '" ' .. args, debug_enabled)

  return {
    output = output,
    status = status,
    reason = reason,
    exit_code = exit_code,
  }
end

function UvEnv:install()
  if #self.spec.packages == 0 then
    return {
      output = "",
      status = true,
      reason = "no packages configured",
      exit_code = 0,
    }
  end

  local result = self.manager:run_uv(
    'pip install --python "' .. self:venv_dir() .. '" ' .. table.concat(self.spec.packages, " ")
  )

  print_run_cmd_result(result)
  return result
end

function UvEnv:check()
  local result = {
    output = "",
    status = true,
    reason = "no checks configured",
    exit_code = 0,
  }

  for _, module in ipairs(self.spec.checks.imports or {}) do
    result = self:run_python('-c "import ' .. module .. '"')

    print_run_cmd_result(result)

    if result.exit_code ~= 0 then
      aegisub.debug.out("UvEnv import check failed for module: %s\n", module)
      return result
    end
  end

  return result
end

function UvEnv:ensure()
  -- if not exists: create
  if not self:exists() then
    local create_result = self:create()
    if create_result.exit_code ~= 0 then
      return create_result
    end
  end
  -- install packages
  local install_result = self:install()
  if install_result.exit_code ~= 0 then
    return install_result
  end
  -- check imports
  local check_result = self:check()
  if check_result.exit_code ~= 0 then
    return check_result
  end

  return {
    output = check_result.output,
    status = check_result.status,
    reason = check_result.reason,
    exit_code = check_result.exit_code,
  }
end

function UvEnv:run_module(module, args)
  -- "<python_exe>" -m <module> <args>
  local result = self:run_python("-m " .. module .. " " .. args)
  print_run_cmd_result(result)
  return result
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
