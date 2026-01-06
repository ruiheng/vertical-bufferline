-- Quick test script for pick mode
local logger = require('buffer-nexus.logger')
logger.enable(vim.fn.expand("~/bn-pick-debug.log"), "DEBUG")
print("BN Pick mode debug logging enabled: ~/bn-pick-debug.log")
print("Now try entering pick mode and check :messages and the log file")
