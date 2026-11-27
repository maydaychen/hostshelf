# HostShelf 当前进度

## 当前状态

当前公开预发布版本为 **0.2.1（6）**，最低支持 macOS 14，修复了上一版 `0.2.0（5）` 匿名包因 `ad-hoc` 签名同时开启 Hardened Runtime 导致加载 `HostShelfCore.framework` 触发 dyld Team ID 校验失败崩溃的问题。采用 `./script/package.sh --anonymous` 生成 ARM／Intel 独立匿名 DMG（外层 DMG 未签名，内部 App 与 Framework 仅采用本地 `ad-hoc` 签名：`Signature=adhoc`、`TeamIdentifier=not set`，关闭 Hardened Runtime，不含 Developer ID 证书或 Apple 公证），并在构建／打包／校验链路中接入本机架构 `--smoke-check` 启动冒烟；发布入口为 [v0.2.1 预发布 Release](https://github.com/maydaychen/hostshelf/releases/tag/v0.2.1)。全量推送前门禁与匿名双架构打包校验均已通过；Intel／macOS 14 实机运行、前台 GUI／全局热键／系统登录项审批及真实终端交接仍待实机验收。

| 范围 | 实现状态 |
| --- | --- |
| 配置索引 | 只读汇总 Host 与递归 Include，侧栏仅列含主机来源，完整来源在诊断页查看 |
| 主机管理 | 模糊搜索高亮、全局快速启动浮窗、多标签、最近入口、空分组删除、高危连接确认与防抖备注保存 |
| 原生界面 | 三栏窗口、菜单栏与全部主机二级菜单、跳板机与端口转发洞察、快速启动浮窗均已实现；前台视觉仍待复测 |
| 终端与外部协作 | 支持 Terminal／iTerm2／Ghostty 常规及 `ssh -N` 隧道交接，以及 VS Code／Cursor／Zed 跳行与 Remote-SSH |
| 刷新与自启 | 启动首次读取后仅手动刷新；支持设置页 `SMAppService` 登录自启与 Carbon 全局热键录制 |
| 分发 | ARM／Intel 独立匿名 `ad-hoc` 构建（外层 DMG 未签名），版本与应用身份一致 |

## 进行中与待验证事项

- **0.2.1 实机复测**：已生成并校验修复 `ad-hoc` 签名启动崩溃的 `0.2.1（6）` 匿名公开预发布包，并已通过本机 `arm64` Release 与挂载 DMG 下的 `--smoke-check` 动态库加载冒烟验证；当前仍仅在 ARM／macOS 27 完成离线与离屏窗口回归，千台列表加载时在 `SwiftUI.OutlineListCoordinator` / `AppKit._cacheRowSpansInRange` 仍记录 1 条框架层自动行高重入警告，**Intel 物理机与 macOS 14 实机运行、真实双击／全局热键／系统登录项交互及真实终端交接仍待实机验收**。

- **交互修复收尾**：实现及隔离回归已通过，后台补验退出成功处理函数的保存与恢复。最小窗口、整窗明暗模式、长指令、设置大字／滚动、真实快捷键、真实关窗通知及退出事件分发仍待复测；在不影响当前桌面使用的约束下保留前台验收缺口，未以离屏截图替代视觉验收。
- **终端交接**：三款终端的实际 Apple Events 允许、拒绝、恢复、新窗口和已有会话保护；Ghostty 原生选择与重启恢复的完整流程，以及 iTerm2 原生运行仍需验证。另待独立评估 `TerminalLauncher` 在后台串行队列调用主线程专用 `NSAppleScript` 的线程安全设计。参数与隔离回归通过不代表实际交接成功。
- **菜单及快捷键**：状态栏与二级菜单的完整展开、滚动、长标题显示和点击交接，搜索／分组筛选独立性的 GUI 复测，以及有选择时的 `⌘Return` 交接仍需完成。
- **系统及架构**：macOS 14 Apple Silicon、macOS 14 Intel 和 Intel 原生运行待验证；交叉编译不代替原生运行验收。
- **安装分发**：干净 Mac 及断网首次安装待验证；已有 ARM 环境的升级与启动检查不代替首次安装验收。

## 最近完成

- 2026-11-27 16:08：升版至 `0.2.1（6）` 并按 `--anonymous` 匿名流程重新构建双架构 DMG，修复 `0.2.0` 匿名构建因 `ad-hoc` 签名启用 Hardened Runtime 导致的启动崩溃，同步更新 `README.md`、`docs/acceptance.md` 与 `ROADMAP.md` 准备 `v0.2.1` 预发布上线。
- 2026-11-27 15:49：定位并修复 `0.2.0` 匿名构建因 `ad-hoc` 签名开启 Hardened Runtime 导致加载 `HostShelfCore.framework` 触发 dyld `different Team IDs` 崩溃的问题：在 `project.yml`（并同步重生成工程）、`script/package.sh` 与 `script/inspect_artifact.py` 中为 `--anonymous`／`--preview` 关闭 `--options runtime`（保留 `--developer-id`／`--signed` 实名模式的 Hardened Runtime），新增 `HostShelfEntry --smoke-check` 入口并在 `script/build.sh`、`script/package.sh`、`script/verify_packages.sh` 接入本机架构无界面动态库加载冒烟校验；同步更新 `AGENTS.md`、`README.md` 与 `docs/privacy.md`（未升版或重新发布 `dist/release/`）。
- 2026-11-25 21:26：下架原带证书的公开 `v0.1.3` Release（API 与旧附件链接已返回 404）；更新 `AGENTS.md`、`docs/privacy.md`、`README.md` 及打包校验脚本，确立 `--anonymous` 双架构匿名开源分发流程；升版至 `0.2.0（5）` 并生成 `dist/release/` 下未签名 DMG + `ad-hoc` 签名 `HostShelf.app`。
- 2026-11-25 00:32：完成下一阶段第二批功能（未发版、未推送）：新增跳板机（`ProxyJump` 传递展开／可点击跳转／菱形与循环识别）及 `ProxyCommand` 静态拓扑洞察；新增 `LocalForward`／`RemoteForward`／`DynamicForward` 端口转发解析、打开本地 TCP 端口、`ssh -N` 仅建隧道与隧道命令复制；扩展兼容旧版 `v1` 元数据的多标签（`#标签` 侧栏筛选及模糊匹配）与主机／分组级高危连接二次确认。
- 2026-11-25 00:22：完成下一阶段第一批功能（未发版、未推送）：新增全局快速启动浮窗（默认未绑定快捷键，设置页支持按键录制及一键启用推荐组合）、多字段模糊子序列匹配与快速排序、登录时自动启动开关（`SMAppService`），以及单次终端切换、外部编辑器（VS Code／Cursor／Zed／系统默认编辑器）定位打开与 Remote-SSH、复制 `HostName`／`User@HostName`／`scp` 模板等多动作连接入口。
- 2026-11-24 22:58：侧栏“配置来源”改为仅展示包含主机的配置文件（涵盖仅拆出声明的被包含文件），零主机或未能读取的已扫描来源统一归入“配置诊断与规则”；状态栏补充已扫描及含主机来源提示，选中来源失去主机或移除时自动回退至“全部主机”。
- 2026-11-21 00:31：重建同名公开 GitHub 仓库并推送清洁单根提交 `2a9a81d` 与 `v0.1.3` 标签，发布公开预发布包及校验文件；公开访问、无认证下载、sRGB 截图块结构与旧库／16 条旧历史不可读均通过独立验收。
- 2026-11-21 00:15：重拍并转换标准 sRGB 亮／暗界面截图，剥离显示器 ICC 与 EXIF／XMP 元数据；联合全库隐私审计通过，更新公开文档表述并准备清洁无父单根基线。
- 2026-11-20 23:26：发布 0.1.3（4）双架构签名公证 DMG 与校验文件，纳入大列表性能与详情收敛、配置读取安全边界、元数据冲突恢复及歧义别名拦截；源码标签、产物、认证下载及仓库私有状态通过独立验收，保留预发布标记。
- 2026-11-20 00:51：统一配置索引与来源片段的文件描述符读取及快照身份校验。元数据写入增加外部变更检查、权限设置后原子替换和显式重读。补齐歧义别名拦截、连接错误恢复动作、Include 权限分支处理及来源失效后的选择回退。
- 2026-11-20 00:12：完成大列表与详情交互候选修复（后台预排与别名索引、来源片段按需加载及取消／代次隔离、详情页外置 `GeometryReader` 断点、请求级滚动预算与轻量行视图），并新增千台主机离屏整窗回归；待 Intel 实机复测与本地样式整理一并提交。
- 2026-10-30 00:20：发布 0.1.2（3）双架构签名公证 DMG 与校验文件；源码标签、附件、认证下载及仓库私有状态通过独立验收，保留预发布标记。

- 2026-10-30 00:12：主机列表移除行级双击手势，改用原生 selection-aware context menu 主操作；保留连接、复制与收藏菜单，增加生产列表的名称／空白单击及方向键回归。

- 2026-10-25 23:40：统一“全部主机”空状态的说明、诊断按钮及动作判断，仅有提示时不显示诊断按钮；配置来源空状态仍保留提示诊断入口。
- 2026-10-25 23:22：完成终端后台交接及重复请求保护、轻量成功反馈、备注防抖与失败草稿保护；补齐最近排序、空组清理、搜索 Esc、高亮、多地址摘要和 Include 提示分级。界面改动的整窗验收仍在进行中。
- 2026-10-25 22:34：重构空状态为受控的 HostEmptyStateCard 组件，恢复侧栏导航高度基准，彻底消除系统大标题与空状态文字的重叠现象。
- 2026-10-25 22:28：优化空状态布局为居顶自然呼吸留白（Top-aligned），消除垂直居中造成的空旷感与视线断层，并更新本机安装运行。
- 2026-10-25 22:12：修复侧栏空状态上下文错乱与中间栏双层标题重叠问题，为收藏、分组和来源提供专属空状态引导。
- 2026-10-25 14:30：按全局隐私规则精简进度文档，保留项目状态、验收结论和待验证事项，移除本机操作流水与详细日志引用。
- 2026-10-25 13:52：完成 0.1.1（2）双架构 App／DMG 公证及票据装订，更新私有预发布安装包。

## 最近验证

- 2026-11-27 16:12：`0.2.1（6）` 已推送 `v0.2.1` 标签并发布公开预发布 Release；本地与无认证公开下载的四份附件字节完全一致，经 `./script/verify_packages.sh --anonymous` 确认外层 DMG 未签名、无公证票据、`hdiutil verify` 通过、内部为 `0.2.1 (6)`、`Signature=adhoc`、`TeamIdentifier=not set`、无 `Authority=`、`runtimeEnabled: false`、`privacyAudit` 零问题，且挂载内通过本机 `arm64` `--smoke-check`；全量推送前门禁通过。Intel 物理机、macOS 14 实机与前台 GUI 交互仍待验收。
- 2026-11-27 15:49：修复后源码通过 `./scripts/verify-before-push.sh` 全量 11 项门禁（Core 79 项单测、手动刷新、终端桥接、交互与千台列表回归、`arm64`／`x86_64` Debug 与 Release 构建、17 项隐私单测及 Release 路径隐私检查，54 个维护文件 0 行数警告，且 `arm64` Release 构建执行 `--smoke-check` 退出 0）；`./script/package.sh --preview` 与 `./script/verify_packages.sh --preview` 完成双架构预览包打包、只读挂载校验与挂载内 `arm64` `--smoke-check`（均已清理临时包），`inspect_artifact.py` 以 `--mode=--preview` 与 `--mode=--anonymous` 检查双架构产物均确认 `adhocSigned: true`、`runtimeEnabled: false`、`privacyAudit.status: passed`；对旧 `0.2.0` `arm64` DMG 执行 `inspect_artifact.py --mode=--anonymous` 负向回归按预期因检测到 Hardened Runtime 失败退出。仍缺 Intel 物理机运行及重打包发版验收。
- 2026-11-25 21:32：独立 `anon-release-verifier` 子 Agent 在不携带认证头与 `Authorization` 凭据、零工作区写入的条件下完成公开验收：原 `v0.1.3` Release 已下架（两份 `v0.1.3` DMG 下载链接均返回 404，`/releases` 仅列 `v0.2.0`，仅 `v0.1.3` Git 标签源码归档页面仍存）；`maydaychen/hostshelf` 与 `v0.2.0` 预发布网页及 `expanded_assets` 无认证可访问（`api.github.com` 匿名 REST 接口因 60 次/小时限流返回 403，改以公开网页及响应头核对一致）；四附件无认证下载后 `shasum -a 256 --check` 全部通过；两份外层 DMG 均未签名且无公证票据，`hdiutil verify` 通过；只读挂载后确认无多余说明文本，两个 `HostShelf.app`（`0.2.0 (5)`）均通过 `--mode=--anonymous` 校验（`Signature=adhoc`、`TeamIdentifier=not set`、零 `Authority=`、Hardened Runtime 开启、`privacyAudit` 0 问题）。未执行 Intel／macOS 14／真实终端交互实机验收。
- 2026-11-25 21:26：`0.2.0（5）` 通过 `./scripts/verify-before-push.sh` 全量 11 项推送门禁（Core 79 项单测、手动刷新 4 项、终端桥接 5 项、交互与千台列表回归 20 项、`arm64`／`x86_64` Debug 与 Release 构建、17 项隐私单测及 Release 路径隐私检查，54 个维护文件 0 行数警告）；`./script/package.sh --anonymous` 与 `./script/verify_packages.sh --anonymous` 确认双架构 DMG 均无外层签名、无公证票据、内部为 `Signature=adhoc`／`TeamIdentifier=not set`／无 `Authority=`、Hardened Runtime 开启且 `privacyAudit` 零问题。未执行 Intel／macOS 14 实机运行与前台 GUI 交互验收。
- 2026-11-25 00:32：第二批新功能通过 Core 79 项单测（含 `SSHTopology`、`tunnelCommand`、旧版 `v1` 元数据兼容解码与标签模糊匹配）、手动刷新 4 项、终端桥接 5 项（含三款终端 `ssh -N` 隧道脚本生成）、交互与千台列表回归 20 项（含多标签筛选回退、主机／分组确认拦截与隧道模式校验）、`arm64`／`x86_64` Debug 双架构构建及 Harness `task` 门禁（54 个维护文件 0 行数警告、17 项二进制隐私单测）。未重跑 Release 打包／公证及前台 GUI／系统登录项／全局快捷键实机交互验收。
- 2026-11-25 00:22：第一批新功能通过 Core 72 项单测（含 `FuzzyMatcher`、`ExternalActions`、`HotKeyShortcut`）、手动刷新 4 项、终端桥接 5 项、交互与千台列表回归 19 项（含模糊搜索高亮、浮窗排序、单次终端覆盖与注入编辑器／Remote-SSH 校验）、`arm64`／`x86_64` Debug 双架构构建及 Harness `task` 门禁（51 个维护文件 0 行数警告、17 项二进制隐私单测）。未重跑 Release 打包、公证、全局热键／开机自启真实系统弹窗与外部应用联调验收。
- 2026-11-24 22:58：工作区源码通过 Core 61 项单测、手动刷新 4 项（含零主机来源回退与纯声明 Include 计数）、终端桥接 5 项、交互与千台列表回归 18 项（含双根配置零主机来源过滤断言）、`arm64`／`x86_64` Debug 双架构构建及 Harness `task` 门禁（38 个维护文件 0 行数警告、17 项二进制隐私单测）。未重跑 Release 打包、公证与前台 GUI 视觉验收。
- 2026-11-21 00:31：独立 `public-release-verifier` 子 Agent 在不携带 `Authorization` 头的纯公开条件下完成验收：`maydaychen/hostshelf` 确认为 `public`（新仓库 ID `1465649215`），旧库 ID `1432831968` 返回 404，旧基线全部 16 条提交与 2 个旧截图 blob 在新库全部返回 404／422；公开 `README.md` 与两张标准 sRGB 截图字节匹配且仅含 `IHDR`、`sRGB`、`IDAT`、`IEND`；`v0.1.3` 预发布四附件无认证下载 SHA-256、DMG／App 严格签名、公证票据与 Gatekeeper 全部通过。未执行 Intel／macOS 14／真实终端交互实机验收。
- 2026-11-20 23:26：0.1.3（4）推送前全量门禁通过（Core 61 项单测、手动刷新 4 项、终端桥接 5 项、交互与千台列表回归 18 项、`arm64`／`x86_64` Debug 与 Release 双架构构建、17 项隐私单测及 Release 二进制路径隐私检查）；两份最终 DMG 经独立子 Agent 只读挂载，版本、纯架构、最低系统 14.0、Developer ID、Hardened Runtime、公证票据、Gatekeeper、Entitlements 与路径隐私全部通过；GitHub 四附件服务器摘要、本地与认证下载 SHA-256 一致，标签对应 `86ed7cd`。未启动安装包或完成 Intel／macOS 14／真实终端交接验收。
- 2026-11-20 00:51：Core 61 项通过，手动刷新 4 项、终端桥接 5 项、全部交互检查与 ARM／Intel Debug 构建通过。加载中刷新用例先确认截获旧内容，再刷新并等待旧任务完成后验证新内容。Harness `task` 检查 38 个维护文件、0 条行数警告，17 项隐私测试通过。离屏大列表仍记录 1 条 AppKit 重入警告。Intel／macOS 14 实机运行、真实终端交接、自动化设置跳转和 Release 产物仍待验证。
- 2026-11-20 00:12：最新工作区源码通过 Core 51 条 XCTest（含 `SourceExcerptReader` 提前中止单测）、手动刷新 3 项、终端桥接 5 项、交互与千台主机离屏整窗回归（覆盖 1,000 主机抽样单击、880×560 窄窗切换、`< 350 ms` 草稿切走落盘、折叠态首次点六位行号加载并滚入视口及加载中刷新竞争）、ARM／Intel Debug 双架构编译及 Harness `task` 门禁（17 条隐私检查与文件规模门禁）。保留缺口：测试闸门线程同步细节未再改写复测；未执行 Release 打包与公证；未完成 Intel／macOS 14 实机运行及真实终端交接验收。
- 2026-10-30 00:20：两份最终 DMG 经独立只读挂载，版本、纯架构、macOS 14 最低要求、严格签名、公证票据、Gatekeeper、权限及二进制隐私全部通过；GitHub 四附件服务器摘要、本地与认证下载 SHA-256 一致，标签对应 `8196783`。未启动安装包或完成 Intel 原生运行验收。

- 2026-10-30 00:12：生产 HostListView 隔离鼠标与键盘回归通过：名称及行空白单击切换选中主机，方向键选择正常，单击不触发终端；原生主操作已安装。最终 release 门禁通过，包含 50 条 Core 测试、17 条隐私回归、手动刷新、终端与交互检查、双架构 Debug／Release 构建及隐私检查；未验证实际双击交接、右键展开或 Intel 原生运行。

- 2026-10-26 00:08：零窗口隔离进程直接执行原退出成功处理函数，验证待处理备注落盘、重新加载恢复、重复调用及损坏文件保护通过；进程禁止激活，窗口及激活通知均为零。未覆盖真实关窗、退出事件分发、错误弹窗或整窗视觉／快捷键。
- 2026-10-25 23:40：空状态条件经无诊断、仅提示、含警告三态静态复核，ARM／Intel Debug 构建及 Harness 静态检查通过；未重复整窗运行验收。
- 2026-10-25 23:22：最终源码的 50 条 Core 测试、17 条隐私回归、手动刷新、终端及新增交互隔离回归、双架构 Debug／Release 构建、二进制路径隐私和 Harness 验证通过；只读检查确认 SSH 配置摘要一致。原生搜索组件 Esc 通过，不代表完整快捷键或真实终端验收。
- 2026-10-25 22:12：回归验证通过，覆盖 Core 47 条单测、手动刷新、终端桥接隔离测试、只读检查以及 ARM／Intel 双架构 Debug 构建。
- 2026-10-25 14:17：公证 ARM 版实际运行验收通过，覆盖启动、首次索引、主窗口响应及升级后的配置、元数据和终端偏好保留。
- 2026-10-25 13:54：两种架构的 App／DMG 独立静态验收通过，覆盖架构、最低系统、严格签名、公证票据、Gatekeeper 和路径隐私；Release 附件与认证下载文件的 SHA-256 一致。
- 2026-10-25 09:23：47 条 Core 测试、17 条隐私回归、手动刷新及终端隔离回归、ARM／Intel Debug 与 Release 构建及 Harness 检查通过。

以上为各检查点已取得的证据摘要；本轮交互修复仍缺整窗运行验收。完整范围与限制见[验收记录](docs/acceptance.md)。

## 参考入口

- [实际用法与构建入口](README.md)
- [首版施工清单](goals/20261023-2210-hostshelf-v1.md)
