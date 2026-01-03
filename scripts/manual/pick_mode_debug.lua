-- Quick test script for pick mode
local logger = require('vertical-bufferline.logger')
logger.enable(vim.fn.expand("~/vbl-pick-debug.log"), "DEBUG")
print("VBL Pick mode debug logging enabled: ~/vbl-pick-debug.log")
print("Now try entering pick mode and check :messages and the log file")
