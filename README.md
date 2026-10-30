# oneapp

扫书 App 的骨架工程。方案 B：书库为根页面，底部「扫描一本书」拉起全屏扫码。

## 当前进度

- [x] 里程碑 0：空壳工程 + CI 出未签名 IPA
- [x] 里程碑 1：相机权限 + 取景预览
- [x] 里程碑 2：扫码识别 ISBN
- [x] 里程碑 3a：确认上传 + 结果反馈（长等待）
- [x] 里程碑 3b：书库改为读取 `/history`，含分页、下拉刷新、状态标记
- [x] 里程碑 4：左滑删除（`POST /delete`）
- [x] 里程碑 5：App 图标 + 连续扫描 / 批量上传
- [x] 里程碑 6：设置页（服务器地址 / 用户名 / 连接测试）
- [x] 里程碑 7：内容简介 + 封面图
- [x] 里程碑 8：失败记录可重试、可清除（`/history/delete`）

## 首次启动要配置

源码里不含任何真实地址或身份标识。第一次打开时书库显示「还没连接服务器」，
需要先在设置（书库标题右侧齿轮）里填：

| 字段 | 说明 |
|---|---|
| 服务器地址 | 只填到端口，不带路径，必须 https |
| 用户名 | 服务端用来识别调用方的值，需在允许名单内 |

填完可点「测试连接」同时验证地址可达与身份有效。两项都存本地 UserDefaults，
改完立即生效并自动重载书库。


## 连续扫描

```
扫码页打开 → 扫一本登记一本（震动 + 绿色 ISBN 提示），相机不关闭
  ↓ 扫够后点「完成 N」
BatchUploadView：确认清单（可左滑移除）→「开始上传」
  ↓ 逐本上传，每本单独显示状态
结果汇总 →「完成」→ 书库刷新
```

**手动输入是旁路，不进扫描列表**：

```
点「手动输入 ISBN」→ 输入 → 「上传」
  ↓ 校验通过（位数 + 校验位 + 978/979 前缀，与扫码同一套规则）
立刻开始单本上传 → 结果 →「完成」→ 回到相机继续扫
```

- 同一本书在画面里停留不会重复登记；离开再扫同一本可以第二次识别（2.5 秒去抖）
- 重复扫到的书震动反馈改为 warning，不重复加进列表
- 已扫了书再点 ✕ 会先问「放弃已扫描的 N 本？」
- 失败条目可「重试失败的 N 本」，**复用原 requestId** 走服务端幂等


## 数据流

```
启动 → GET /history?username=…&limit=30      → 书库列表
下拉刷新 / 上传结束 → 重新拉第一页
滚到底 → GET /history?…&before_id=next_before_id
扫码 → POST /upload → 成功后刷新书库
左滑删除 → POST /delete {"book_ids":[book_id]} → 刷新书库
```

书库不再有本地缓存，唯一数据源是后端 `/history`。所以杀掉 App 重开不会丢数据。

## 接口约定（实测）

文档见后端仓库。以下几条是实测确认或易踩的地方：

**1. Base URL 与路径**

```
https://<你的服务器地址>     ← TLS 正常（ZeroSSL，机构根受信）
  GET  /upload?username=…     权限预检
  POST /upload              上传
  GET  /history?username=…    上传历史 / 我的书单
  POST /delete              删除
  GET  /status?username=…     排错
```

**2. 统一响应信封**

所有接口都返回 `success` / `code` / `message`（**没有** `ok` / `msg`，旧版格式已废弃）。

- `POST /upload` 用**真实 HTTP 状态码**（200 / 400 / 403 / 502）
- 其余接口**始终 HTTP 200**，必须读 `success` 判断

**3. `/history` 的行为**
- 缺 `用户名` 或不在白名单 → `success:false` + `code:403`，但 **HTTP 仍是 200**，`items` 为空
- `limit` 默认 20，最大 100
- 分页游标：把上一页的 `next_before_id` 作为下次的 `before_id`；没有下一页时该字段不返回
- **失败记录也会返回**（`status = failed`），需要前端自己区分展示
- `status` 取值：`success` / `failed` / `pending`（`duplicate` 是历史遗留数据）

**4. 删除有两个接口，按 `success` 分流**

| 记录类型 | 接口 | 需要 | 对 Calibre |
|---|---|---|---|
| `success: true`（书在书单里） | `POST /delete` | `book_id` | **真的删书** |
| `success: false`（失败 / 处理中） | `POST /history/delete` | `isbn` | **完全不碰** |

`/history/delete` 的删除粒度是 `(用户名, ISBN)`，一次清掉这本书的全部失败行；
它**绝不删成功记录**，也不需要 `book_id` —— 失败记录不再是死数据。

失败的书可以在详情页直接「重试上传」，走的是和扫码相同的 `/upload` 流程。
后端在重试成功后会自动合并掉之前的失败记录，前端不需要额外清理。

**5. `/delete` 的行为**
- **始终 HTTP 200**，看 `success`
- 请求体：`{"用户名字段": "…", "book_ids": [42]}`，`book_ids` 支持单值、数组或 `"42,43"` 字符串
- **只能删自己书单里的书**，否则 `code:403` + `只能删除自己上传过的书`
- 引用计数：还有别的用户 拥有这本书时，只移除自己的记录，`kept_in_library` 里会列出来，库里保留
- 删除成功后 `/history` 里这些行（含 failed / pending）都会消失

**6. `/history/delete` 的行为**
- **始终 HTTP 200**，看 `success`；`removed_records: 0`（没有可删的记录）也算成功，**幂等**
- 请求体：`{"用户名字段": "…", "isbn": "978…"}`（也支持 `ids: [记录 id]`）
- **只删 failed / pending**，传 success 行的 id 只会得到 `没有可删除的记录`
- 完全不碰 Calibre

**7. 超时与幂等**
- 上传服务端最长等 50 秒，客户端超时设为 90 秒
- 502 且 `message` 含「超时」→ 后台通常仍在跑，**不自动重试**；重试必须复用同一个 `requestId`

**8. 响应字段易踩的坑**
- `cost` 是字符串（`"23.4s"`），不是数字
- `book_id` 可能为 `null`
- `dup` 只在「你的书单里早就有、这次没重新处理」时为 `true`；**第一次（哪怕别人传的）不带这个字段**
- `authors` 是字符串数组，但 iOS 侧对单字符串也做了兼容
- `created_at` 是 `"2026-10-29 12:40:11"` 这种格式，不是 ISO8601，按原样展示

**9. 内容简介**
`/history` 的每条记录带 `description`，基本是纯文本。详情页按 6 行折叠并提供「展开全文」。

**10. 封面**
`GET /cover?username=…&book_id=…&isbn=…`，三个参数都必填，**成功时返回二进制图片**（不是 JSON），
失败才返回 JSON。**这个接口不需要 Authorization 头**。

两个实测发现：

- **`has_cover` 不可靠**：有记录标着 `false`，但 `/cover` 依然返回图片。所以只要 `book_id` 存在就一直尝试
- **封面尺寸不统一**：实测有 800×800（正方形）和 500×453，不是标准 2:3。列表和详情用固定框 + `.fill` 裁切

服务端给了 `ETag` 和 `Cache-Control: max-age=604800`，客户端再加一层内存缓存和失败记忆，
所以滚动不会重复请求，撞过 404 的书也不再重试。

**11. 认证**
当前未启用 `api_token`，不带 `Authorization` 也能调。若将来启用，token **不能进仓库**（仓库是公开的）。
认证（token）与授权（用户名允许名单）是两层，前者管"能不能访问服务"，后者管"这个用户能不能用"。



## 本地没有 Xcode 时的工作流

工程文件由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，仓库里不存 `.xcodeproj`。编译在 GitHub Actions 上完成。

```
push → Actions 编译检查 → 出未签名 IPA → 下载 → 本地签名装机
```

在 Mac 上首次打开需要：

```sh
brew install xcodegen
xcodegen generate
open OneApp.xcodeproj
```

## 目录结构

```
project.yml                 工程定义（改这个，不是 .xcodeproj）
Sources/
  OneApp.swift              App 入口
  Assets.xcassets/          App 图标（1024 单尺寸）
  Settings/AppSettings.swift  服务器地址与用户名（可配置、本地持久化）
  Models/
    Book.swift              与 /history 记录一一对应（含 description）
    ISBNValidator.swift     ISBN-10/13 校验位验证
  Networking/
    APIClient.swift         上传 / 历史 / 删除 / 封面 URL
    CoverImageLoader.swift  封面图加载（内存缓存 + 失败记忆）
    LibraryStore.swift      书库数据源（加载 / 刷新 / 分页 / 删除）
  Theme/Palette.swift       配色与封面色板
  Camera/
    CameraSession.swift     AVCaptureSession + 条码识别（带去抖）
    CameraPreview.swift     预览层 UIViewRepresentable
  Views/
    LibraryView.swift       书库（根）+ 自绘标题行 + 未配置态 + 左滑删除
    BookRowView.swift       列表行 + 封面（网络图，失败回落渐变）
    BookDetailView.swift    书籍详情
    ScannerView.swift       连续扫码（权限门 + 取景 + 手电筒 + 计数）
    CameraGateViews.swift   权限说明 / 被拒引导
    ManualInputView.swift   手动输入 ISBN（校验后直接上传）
    BatchUploadView.swift   批量确认 / 逐本上传 / 结果汇总
    SettingsView.swift        设置（地址 / 用户名 / 连接测试）
tools/make_icon_variants.py 重新生成图标候选
.github/workflows/ios.yml   编译 + 打包
```

## 装机

IPA 是**未签名**的，需要本地重签后安装（Sideloadly / AltStore），免费 Apple ID 签出的证书 7 天有效。
