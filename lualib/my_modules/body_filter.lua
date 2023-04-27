local modified_body = ngx.ctx.modified_body
ngx.log(ngx.ERR, "modified_body:",modified_body)
if modified_body then
    -- 使用修改后的响应数据替换原始响应数据
    ngx.arg[1] = modified_body
end