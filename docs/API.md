# 服务端接口与本地更新网关

接口使用 JSON，响应错误包含 `error`。修改请求使用 `Content-Type: application/json`，DELETE 也传 `{}`。示例接口根为服务器根地址，不包含 `/admin`。

## 服务端 API

| 方法 / 路径 | 权限 | 作用 |
| --- | --- | --- |
| GET /api/status | 公开 | 返回 app=zhiban-course-server、status=online，无账号数据 |
| POST /api/register | 公开 | username、password；始终创建 student |
| POST /api/login | 公开 | username、password、portal；登录并设置 Cookie |
| POST /api/logout | 当前入口 | 注销当前会话 |
| GET /api/me | 已登录 | 返回 id、username、role、active |
| GET /api/health | 已登录 | 在线状态 |
| GET /api/courses | 已登录 | 管理员列出全部；学生仅列出授权课程的 id、title、count |
| POST /api/courses | 管理员 | 新建完整课程，返回 id |
| GET /api/courses/{id} | 管理员或获授权学生 | 下载完整课程 |
| PUT /api/courses/{id} | 管理员 | 替换课程内容 |
| DELETE /api/courses/{id} | 管理员 | 删除课程及关联授权 |
| GET /api/users | 管理员 | 列出用户、状态及 courses 授权 ID 列表 |
| PUT /api/users/{id} | 管理员 | 保存学生 active、courses，并注销其所有会话 |
| DELETE /api/users/{id} | 管理员 | 删除学生及关联授权/会话，不能删除管理员 |

用户名 3–40 字符；注册密码 8–128 字符。会话有效期 8 小时。未登录返回 401，无权限返回 403，不存在返回 404；输入错误一般返回 400。

管理员页面使用 `X-Portal: admin` 和 `admin_session` Cookie；客户端入口使用 `X-Portal: client` 和 `client_session`。登录请求的 `portal=admin` 会拒绝学生；后续权限始终由会话用户角色决定，修改请求头不能获得管理员角色。测试或自写管理客户端应对登录和后续请求一致发送管理员入口请求头。

## 课程格式

```json
{
  "title": "认识水果",
  "description": "读音与拼写",
  "version": "1.0",
  "items": [
    {"id":"apple","tag":"04A10001","word":"apple","meaning":"苹果","emoji":"🍎"}
  ]
}
```

至少一个物品，字段不可为空；课程内物品 ID 和规范化后的 RFID 标签必须唯一。数字物品读音在设备本地合成，不含音频 URL。课程 ID 由服务器生成。

## 客户端本地 API

只在本机 127.0.0.1 提供服务，默认端口 8765。Host 与 Origin 必须匹配本机地址；不启用跨站访问。不是供其他设备远程管理本地档案的接口。

| 接口 | 作用 |
| --- | --- |
| GET /local/config | 返回 server_url |
| PUT /local/config | JSON 设置 server_url，并清除旧更新 Cookie |
| POST /api/register、/api/login、/api/logout | 转发到配置的远端，固定客户端入口 |
| GET /api/me、/api/health、/api/courses、/api/courses/{id} | 受限转发 |

不转发用户管理、课程创建/修改/删除。网关验证远端返回为 JSON，限制响应大小，超时或网络问题返回 503；重定向或无效响应通常返回 502。客户端地址配置仅允许不带凭据、路径、查询或片段的 HTTP(S) 根地址，拒绝将客户端自身作为远端。

本地课堂记录操作直接使用浏览器 localStorage，不通过上述 API；因此服务端不能获取、查询或同步学习记录。

## 页面与分发

服务端 `/admin` 为管理页，`/` 为入口与客户端 ZIP 下载，`/migrate` 导出旧浏览器本地数据，`/downloads/zhiban-client.zip` 下载客户端包。服务端不再托管当前课堂。

客户端 `/`、`/client`、`/robot` 均显示本地课堂。`/sw.js` 缓存课堂页面和静态资源；不缓存任何上述 API。

课程内容增加 access 字段：public（所有启用账号）、restricted（需要单独授权，旧课程默认）、hidden（管理员可见，学生即使有授权也不可下载）。所有模式仍要求登录；停用账户始终不可下载。列表和详情接口均执行权限校验，已下载离线副本不受影响。
