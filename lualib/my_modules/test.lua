local css_content = [=[
/* Other CSS rules */
@import url("styles/global.css");
/* More CSS rules */
@import url('http://rws.com/styles/theme.css');
@import url("global.css");
@import url("cms.min.css");
@import url("cms-ie6.min.css");
@import "system_editor.css";
@import 'another_style.css';
@import "system_editor.css";
.headerbg{height: 120px;background: url(Header_Bg.png) no-repeat center center;}
    #nav .home {float:left;width: 118px;line-height:35px;display:block;text-align:center; color:#fff;background:#062723 url(slide-panel_03.png) 0 0 repeat-x;}
]=]

local patterns = {
    '@import%s+url%("([^"]*)"%)',
        "@import%s+url%('([^']*)'%)",
        '@import%s+"([^"]*)"%s*',
        "@import%s+'([^']*)'%s*",
        'url%(([^"\'%s]+)%)'
}

local url_infos = {}

-- 提取 URL 信息
for _, pattern in ipairs(patterns) do
    css_content = string.gsub(css_content, pattern, function(url)
        table.insert(url_infos, {url = url})
        return '@import url("' .. url .. '");'
    end)
end

-- 打印提取到的 URL 信息
for _, url_info in ipairs(url_infos) do
    print("Imported URL:", url_info.url)
end