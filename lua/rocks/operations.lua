--- operations.lua --- rocks.nvim operations module
--
-- Copyright (C) 2023 NTBBloodbath
--
-- Version:    0.1.0
-- License:    GPLv3
-- Created:    05 Jul 2023
-- Updated:    05 Jul 2023
-- Homepage:   https://github.com/NTBBloodbath/rocks.nvim
-- Maintainer: NTBBloodbath <bloodbathalchemist@protonmail.com>
--
-------------------------------------------------------------------------------
--
--- Commentary:
--
-- This module handles all the operations that has something to do with
-- luarocks. Installing, uninstalling, updating, etc
--
-------------------------------------------------------------------------------
--
--- Code:

local operations = {}

local toml = require("toml")

local fs = require("rocks.fs")
local constants = require("rocks.constants")

local cfg = _G.__rocks_config

--- Get installed rocks list
---@param rocks_path string Path to luarocks tree
---@param add_metadata boolean If should return extra metadata and not only the rock name
---@return table
---@private
local function get_installed_rocks(rocks_path, add_metadata)
  local installed_rocks = vim.split(vim.fn.system({
    "luarocks",
    "--lua-version=" .. constants.LUA_VERSION,
    "--tree",
    rocks_path,
    "list",
    "--porcelain"
  }), "\n")

  -- If there is only one rock installed then fast return it
  if installed_rocks[2] == "" then
    local rock = vim.split(installed_rocks[1], "\t")

    if not add_metadata then
      return { rock[1] }
    end

    return {
      rock[1], -- name
      rock[2], -- version
      -- rock[4], -- install path (is it really required for us?)
    }
  end

  local rocks = {}
  for idx, rock in ipairs(installed_rocks) do
    -- Last table item will always be an empty string
    if rock ~= "" then
      ---@diagnostic disable-next-line
      rock = vim.split(rock, "\t")

      -- NOTE: perhaps this should be refactored later to add consistency? Idk, I haven't sleep
      if not add_metadata then
        rocks[idx] = rock[1]
      else
        rocks[idx] = {
          rock[1], -- name
          rock[2], -- version
          -- rock[4], -- install path (is it really required for us?)
        }
      end
    end
  end

  return rocks
end

--- Install a Lua rock, return a boolean depending on the succeed or failure
---@param name string Rock name
---@param version string Rock version
---@return boolean
---@private
local function install(name, version)
  -- If not using a valid version then scream at the user
  -- TODO: provide a better error message
  if version:match("%d%.%d%.%d%-%w+") == nil then
    error("Invalid rock version provided")
  end

  vim.notify("Installing '" .. name .. "@" .. version .. "' by using luarocks, please wait ...")
  vim.fn.system({
    "luarocks",
    "--lua-version=" .. constants.LUA_VERSION,
    "install",
    "--tree",
    cfg.rocks_path,
    name,
    version,
  })

  vim.cmd.redraw()
  if vim.v.shell_error ~= 0 then
    -- TODO: find a way to purge this if required?
    -- -- As toml is the first thing that gets installed it is safe to completely nuke the Neovim luarocks tree
    -- -- if the installation failed so we do not keep any kind of residual junk when retrying the installation
    -- vim.fn.delete(cfg.rocks_path, "rf")

    vim.notify(
      "Failed to install '" .. name .. "@" .. version .. "', please relaunch Neovim to try again.",
      vim.log.levels.ERROR
    )
    return false
  else
    vim.notify(
      "Successfully installed '" .. name .. "@" .. version .. "' at '" .. cfg.rocks_path .. "'.",
      vim.log.levels.INFO
    )
    return true
  end
end

--- Uninstall a Lua rock, return a boolean
---@param name string Rock name
---@return boolean
---@private
local function remove(name)
  vim.notify("Removing '" .. name .. "' rock by using luarocks, please wait ...")
  vim.fn.system({
    "luarocks",
    "--lua-version=" .. constants.LUA_VERSION,
    "remove",
    "--tree",
    cfg.rocks_path,
    name,
  })

  -- NOTE: perhaps add error checking here too?
  vim.cmd.redraw()
  vim.notify("Successfully removed '" .. name .. "' rock.")

  return true
end

--- Read configuration file and make operations work
--- FIXME: this should not be automagically doing stuff I think, this is just for testing purposes so might need a refactor later
function operations.read_config()
  -- Read or create a new config file and decode it
  local config = toml.decode(fs.read_or_create(cfg.config_path, constants.DEFAULT_CONFIG))

  -- Merge `rocks` and `plugins` fields as they are just an eye-candy separator for clarity purposes
  local config_rocks = vim.tbl_deep_extend("force", config.rocks, config.plugins)

  -- Get the installed rocks in the rocks.nvim Luarocks tree
  local installed_rocks = get_installed_rocks(cfg.rocks_path, true)
  local installed_rock_names = get_installed_rocks(cfg.rocks_path, false)

  --- Operations process ---
  --------------------------
  -- ops structure:
  -- {
  --   install = {
  --     foo = "version"
  --   },
  --   remove = {
  --     "bar",
  --     "fizzbuzz",
  --   }
  -- }
  local ops = {
    install = {},
    remove = {},
  }
  for rock, metadata in pairs(config_rocks) do
    if not vim.tbl_contains(installed_rock_names, rock) then
      ops.install[rock] = metadata
    end
  end
  for _, installed_rock in ipairs(installed_rock_names) do
    if not vim.tbl_contains(vim.tbl_keys(config_rocks), installed_rock) then
      ops.remove[#ops.remove + 1] = installed_rock
    end
  end

  -- Installation process
  for rock, metadata in pairs(ops.install) do
    -- NOTE: perhaps we can simplify the was_installed logic?
    local was_installed = false
    if type(metadata) == "table" then
      -- only pass the rock name and its version as we do not need whole metadata from the config file
      was_installed = install(rock, metadata.version)
      if was_installed then
        installed_rocks[#installed_rocks + 1] = { rock, metadata.version }
      end
    else
      -- rock, version
      was_installed = install(rock, metadata)
      if was_installed then
        installed_rocks[#installed_rocks + 1] = { rock, metadata }
      end
    end
  end

  -- Remove process
  for _, rock in ipairs(ops.remove) do
    remove(rock)
  end

  --- Hijack Neovim runtimepath ---
  ---------------------------------
  for _, rock in pairs(installed_rocks) do
    vim.opt.runtimepath:append(table.concat({
      cfg.rocks_path,
      "lib",
      "luarocks",
      "rocks-" .. constants.LUA_VERSION,
      rock[1], -- plugin name
      rock[2], -- plugin version
    }, constants.SYS_SEPARATOR))
  end
end

return operations

--- operations.lua ends here
