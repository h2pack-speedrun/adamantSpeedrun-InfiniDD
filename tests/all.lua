package.path = "./?.lua;./?/init.lua;" .. package.path

dofile("tests/test_logic.lua")

local lu = require("luaunit")
os.exit(lu.LuaUnit.run())
