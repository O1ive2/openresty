# 安装

1.在ubuntu20.04系统中的/usr/local/目录下使用

```
git clone https://github.com/O1ive2/openresty.git
```

命令克隆项目到本地

2.修改host文件

添加一行记录

`127.0.0.1			rws.com`

3.依赖项都安装在项目中，因此应该不需要额外输入命令安装依赖（如果有依赖未安装，可以根据命令行报错安装相应依赖）

# 启动

1. 首先输入sudo /usr/local/openresty/nginx/sbin/nginx
2. 之后输入sudo /usr/local/openresty/nginx/sbin/nginx -s reload
3. 完成启动，可以在浏览器端输入http://rws.com/main.htm访问网站首页
