local target_url = ngx.var.arg_target_url
if not target_url then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say("Missing target_url argument")
    return
end

local res = ngx.location.capture(target_url)

if res.status == ngx.HTTP_OK then
    ngx.status = res.status
    ngx.say(res.body)
else
    ngx.status = res.status
    ngx.say("Error occurred: ", res.status)
end