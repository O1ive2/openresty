local new_uri= ngx.ctx.new_uri
ngx.req.set_uri("/rewrite"..new_uri)
-- if uri ~= "/new_uri" then
--     ngx.req.set_uri("/new_uri")
-- end