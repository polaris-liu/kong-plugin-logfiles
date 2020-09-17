package = "kong-plugin-logfiles" 

version = "0.1.0-1" 

local pluginName = "logfiles"

supported_platforms = {"linux", "macosx"}
source = {
  url = "https://github.com/polaris-liu/kong-plugin-logfiles.git",
  tag = "0.1.0-1"
}

description = {
  summary = "Log request message body to files",
  homepage = "https://github.com/polaris-liu/kong-plugin-logfiles",
  license = "Apache 2.0"
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..pluginName..".handler"] = "kong/plugins/"..pluginName.."/handler.lua",
    ["kong.plugins."..pluginName..".schema"] = "kong/plugins/"..pluginName.."/schema.lua",
	["kong.plugins."..pluginName..".segment_ref"] = "kong/plugins/"..pluginName.."/segment_ref.lua",
  }
}