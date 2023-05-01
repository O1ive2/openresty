local uuid = require "resty.jit-uuid"
local response_handle = require("my_modules.response_handle")
uuid.seed()

local response_body = ngx.arg[1]
local is_first_access = ngx.var.is_first_access

local modified_body = response_handle.response_handle(response_body,is_first_access)

ngx.arg[1] = modified_body

ngx.arg[2] = ngx.arg[2]
