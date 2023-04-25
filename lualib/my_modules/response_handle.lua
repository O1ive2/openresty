local response_body = ngx.arg[1]
ngx.log(ngx.ERR,response_body)
ngx.arg[1] = string.upper(response_body)