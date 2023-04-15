local text = [[
    <a href="http://www.example.com">Example</a>
    <img src="http://www.example.com/images/logo.png">
    <form action="/submit">
]]
local patterns = {
    '(href)=["\']([^"\']+)["\']',
    '(src)=["\']([^"\']+)["\']',
    '(action)=["\']([^"\']+)["\']'
}
for _, pattern in ipairs(patterns) do
    for attribute, value in text:gmatch(pattern) do
        print(attribute, value)
    end
end
