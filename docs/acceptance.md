# HostShelf 验收记录

## 0.1.3（4）发布、大列表优化与配置读取边界修复

2026-11-20 23:26（北京时间）：[v0.1.3](https://github.com/maydaychen/hostshelf/releases/tag/v0.1.3) 已发布，`draft=false`、`prerelease=true`，源码为 `86ed7cd7897c3e5c79af40603752a7275706a9b8`。纳入本版的改动与门禁范围如下：

- 发布前 `./scripts/verify-before-push.sh` 全量 11 项检查通过，覆盖 Core 61 项单测、手动刷新 4 项、终端桥接 5 项、交互与 1,000 台主机离屏回归 18 项、`arm64`／`x86_64` Debug 与 Release 双架构构建、17 项隐私单元测试及 Release 二进制路径隐私检查。千台列表离屏窗口仍记录 1 条 AppKit `NSTableView` 代理重入警告，未发生阻塞或卡死。
- 独立 `release-verifier` 子 Agent 只读挂载两份公证 DMG，确认内部 `HostShelf.app`（`0.1.3` / 构建 `4`）与 `HostShelfCore` 的单架构约束、最低系统 `14.0`、Developer ID 签名与团队身份、`Hardened Runtime`、Entitlements（仅 `com.apple.security.automation.apple-events`）、公证票据、Gatekeeper 及二进制路径隐私全项通过；GitHub 四附件服务器摘要与无认证重定向下载 SHA-256 与本地原件完全一致，仓库保持私有。

| 架构 | App 公证 ID | DMG 公证 ID |
| --- | --- | --- |
| arm64 | `bdeab33e-960a-43a3-96ec-fa8aeb6b0afd` | `edbb445d-ceb2-461d-be7d-50f6e6632ec8` |
| x86_64 | `758a4096-9ad3-4949-a70c-0aa2ba43b44b` | `85250b1d-5ed2-4f55-9c32-a031d45b3607` |

| 安装包 | SHA-256 |
| --- | --- |
| `HostShelf-0.1.3-macos-arm64.dmg` | `c3971154679c867f2e126d791d862ce50550ae93f4756acb22cf27cafc4df49e` |
| `HostShelf-0.1.3-macos-x86_64.dmg` | `fa65c8f4680bfbca707eb1a3cfa975fa54e10dfb398f3ec27ea1d2c0e9298486` |

本次未启动 DMG 内安装包或更换本机安装版；Intel 原生运行、macOS 14 实机运行、三款终端的真实 Apple Events 授权与系统设置跳转、真实双击交接以及干净 Mac／断网首次安装继续待验。证据保存在已忽略的 `.tmp/release-0.1.3/`。

## 0.1.2（3）发布与列表选择修复

2026-10-30 00:12（北京时间）：用户报告 Intel Mac 主窗口中间列表单击无响应、双击仍能打开 SSH。当前 ARM／macOS 27 隔离环境未复现旧故障；根据此症状和 Apple 原生列表契约，将行级双击手势改为 `contextMenu(forSelectionType:menu:primaryAction:)`，由原生列表管理单击选择与双击主操作，右键菜单继续绑定目标主机。

- 生产 `HostListView` 隔离运行通过：点击名称、点击行空白、切换选中主机及方向键正常，选择不执行终端。测试宿主直接消费生产文件，不复制列表实现。
- 原生双击主操作已安装；既有终端替身、备注、搜索及状态流转回归通过，没有读取个人 SSH 配置、发送真实 Apple Events 或连接服务器。
- 最终 release 门禁通过，包含 50 条 Core 测试、17 条隐私回归、手动刷新、终端与交互检查、双架构 Debug／Release 构建及路径隐私检查；两种架构的 App／DMG 已完成签名、公证及票据装订，并发布至私有仓库预发布 Release。Intel 实机、真实双击交接及右键展开未验收，不以本机 ARM 结果代替。
- 原生交互语义依据 [Apple 文档](https://developer.apple.com/documentation/swiftui/view/contextmenu(forselectiontype:menu:primaryaction:))。

2026-10-30 00:20（北京时间）：[v0.1.2](https://github.com/maydaychen/hostshelf/releases/tag/v0.1.2) 已发布，`draft=false`、`prerelease=true`，源码为 `8196783dad86ce2b5ac9e4d892767e7d098758e3`。独立只读验收确认两份 DMG 及其中 App 的版本、架构、最低系统、原签名团队、公证票据、Gatekeeper、权限和路径隐私符合项目要求；四附件服务器摘要与认证下载 SHA-256 一致。仓库可见性保持私有。

| 安装包 | SHA-256 |
| --- | --- |
| `HostShelf-0.1.2-macos-arm64.dmg` | `b2bff07e68175929e6335c142ce05590febe89e1a8384c930f33568eb93dbec3` |
| `HostShelf-0.1.2-macos-x86_64.dmg` | `c8457c488dbd84ab05fb7826e97c0d9d61b4a37bf6eeda864dc5b127e7933830` |

这次没有启动最终安装包或修改本机安装版；Intel 原生运行、真实双击交接、右键完整 GUI、macOS 14 及干净 Mac／断网首次安装继续待验。证据保存在已忽略的 `.tmp/release-0.1.2/`。

## 0.1.1（2）历史验收记录

记录时间：2026-10-25 14:17（北京时间）。ARM／Intel 两份 DMG 为 0.1.1（2），App 与 DMG 均已完成 Apple 公证、票据装订、路径隐私检查和独立静态验收，并更新至私有仓库的 v0.1.1 预发布 Release。本机已更新为同一公证 ARM 版，配置和应用数据摘要一致，实际启动及主窗口响应通过；原 Developer ID 身份保持不变，旧提交访问复验已完成。

## 后续源码交互修复

2026-10-25 23:22（北京时间），本地后续源码的逻辑与构建回归通过。本节对应当前源码，后文公证、安装和 Release 记录对应既有安装包；本轮没有更新安装版、公证包或远端发布。

| 范围 | 实际结果与边界 |
| --- | --- |
| 终端执行 | 固定脚本及参数保持分离，脚本对象限定在专用串行后台队列；注入阻塞执行时主线程保持响应，跨实例串行、失败回传和无效输入检查通过。AppStore 忙碌状态立即生效，重复提交被忽略。没有执行真实 Apple Events 或 SSH |
| 提示 | 成功不再写入错误弹窗；窗口关闭后的成功交接不保留过期提示，真实失败在重新打开时仍可恢复。隔离状态回归通过，真实菜单栏点击路径待测 |
| 备注 | 连续文本变化先留在内存，停止输入后保存最新草稿；显式 flush 取消待处理计时器，保留期间修改的收藏。保存失败保留草稿及原损坏文件。窗口消失／退出前保存方法通过隔离回归；真实原生关闭和退出 hook 待测。失败退出提供返回应用或明确放弃草稿的选择 |
| 管理与展示 | 最近排序及日期相同的稳定次序、搜索筛选、空组删除及隐藏记录／草稿保护、Unicode 高亮、多地址摘要和指令列宽边界通过隔离检查 |
| 搜索组件 | 原生 NSTextField 的 Esc 清空并移出编辑焦点，其他编辑器及命令不被拦截。真实窗口内的完整快捷键流程待测 |
| 构建与保护 | 50 条 Core 测试、17 条隐私回归、手动刷新、终端及交互隔离检查、ARM／Intel Debug 和 Release 构建、Release 二进制路径隐私、Harness 检查通过；配置只读检查前后摘要一致 |
| 界面缺口 | 原生整窗自动化两次超时，最小窗口、整窗明暗模式、长名称／指令、设置大字与滚动、弹窗取消、关闭／重开和正常退出未完成本轮端到端复测。离屏缓存截图不完整，已弃用，未作为通过证据 |

回归入口为 `./script/test_app_interactions.sh`，使用隔离配置、元数据、终端执行器及原生搜索组件，不操作真实服务器或用户剪贴板。Intel 原生运行、macOS 14 及三终端实际授权缺口继续保留。本轮新增源码尚不具备正式交付的完整 GUI 验收证据。

## 不干扰桌面的后台补验

2026-10-26 00:08（北京时间），使用零窗口隔离进程补验当前源码。派生入口只移除原 App 文件的 `@main` 并追加检查代码，原生产函数保持不变；配置、元数据和偏好均为演示夹具。

- 直接调用实际 `applicationShouldTerminate` 的成功路径：待处理备注先落盘，再返回允许退出；重新创建数据实例后，备注及分组恢复正确。
- 再次调用干净状态下的退出处理函数，文件内容保持一致；损坏元数据时，保存方法保留草稿和原损坏文件。没有触发失败退出弹窗。
- 前后检查确认测试进程为 `prohibited`、未激活，窗口数量及激活通知均为零。编译使用低优先级单并发，没有发送全局输入、截图或执行真实终端／SSH。

这次仅新增退出处理函数及数据恢复的运行证据，未通过系统分发真正退出应用，也未创建窗口或触发真实关窗通知；整窗明暗、最小尺寸、大字滚动、真实快捷键、SwiftUI 关闭／重开和错误弹窗继续待验。没有修改产品源码、当前安装版或用户数据。

## 需求与实际证据

| 验收项 | 实际结果 | 证据与限制 |
| --- | --- | --- |
| AC1 配置索引 | 通过 | Core 共 47 条 XCTest 零失败，其中索引 22 条、来源片段 10 条；覆盖 Include、重复声明、条件候选、循环、词法、软链接、特殊文件、有界索引读取及来源行号；没有运行配置命令 |
| AC2 本地管理 | 通过已测范围 | 元数据 9 条单测；隔离 GUI 中收藏、修改备注、新建分组、分配分组和分组过滤成功，JSON 落盘；源配置不写回 |
| AC3 手动刷新 | 通过已测范围 | 最新要求为仅手动刷新；启动首次读取后，配置变化／应用激活不刷新，主动刷新可读取更新及 Include；扫描中重复请求不续扫。原文件监听已移除 |
| AC4 终端交接 | 部分验证 | 命令校验／安全引用 6 条单测及终端隔离驱动通过，支持 Terminal／iTerm2／Ghostty；参数与偏好、缺失应用提示已测。实际 Apple Events 允许／拒绝／恢复、新窗口及已有会话保护尚未运行验收；没有连接真实服务器 |
| AC5 原生界面 | 通过已测范围 | 当前 macOS 27.0.1、Apple Silicon 的 Debug 实际运行；新版详情明暗渲染、最小窗口、长名称、来源定位、备注成功／失败路径、`⌘F`／`⌘R` 焦点及空选择 `⌘Return` 已验证；此前窗口恢复通过。菜单栏完整操作、有选择时的连接交接及其他系统环境仍未完整验收 |
| AC6 分架构 | 通过静态验收 | ARM／Intel 的 Debug、Release 均构建成功；最终 DMG 内 App 和 Core 分别为纯 arm64／x86_64，Mach-O 最低系统均为 14.0，版本与应用 ID 一致 |
| AC7 签名及分发 | 部分验证 | 独立 release-verifier 只读挂载两份最终 DMG，确认 App／DMG 公证、装订、严格签名、原身份和权限通过；本机 Gatekeeper 执行／打开检查通过，认证下载哈希一致。干净 Mac／断网首次安装尚未验证 |

本机配置另做只读盘点，前后内容摘要一致，正常启动后的界面索引与盘点结果一致；不在项目文档保留真实别名、地址或具体数量。索引结果不代表目标当前可连接。

## 隐私清理与运行复验

- ARM／Intel 新 DMG 和安装版的整个 App 均通过原始字节扫描，个人主目录和临时编译目录命中为 0；所有真实 Mach-O 的 N_SO／N_OSO 为 0，无内嵌 DWARF 或 dSYM。
- 主程序 12 项、Core 332 项动态导出集合及全部动态依赖与清理前一致；版本、单架构、macOS 14 最低要求、Developer ID、Hardened Runtime、Apple Events 权限与严格签名通过。
- 隐私清理时，安装版文件及符号链接与当时 ARM DMG 一致，本机运行实例唯一、启动完成且窗口存在。公证后又将安装版更新为同一 ARM 包，App 新增公证票据，主程序与 Core 的字节哈希保持一致；配置、主机元数据和默认终端选择摘要一致，没有发起服务器连接。
- 47 条 Core 测试、17 条隐私回归、刷新／终端隔离回归、双架构 Debug／Release 构建及扩展后的 Harness push 门禁通过。新增检查覆盖实际 Mach-O 剥离前失败、剥离后通过、UTF-16、资源和符号链接失败路径。
- 本机旧个人署名提交对象不可读，reflog 与旧回滚 bundle 已清除；逐文件哈希确认后删除含隐私路径的生成编译文件，旧 DMG 已由清洁版本替代，临时文本证据已脱敏。
- GitHub 旧库已按用户明确确认删除并重建为同名私有仓库，新旧仓库 ID 不同，旧 ID 返回 404。当前提交、README 和图标正向读取通过；12 条旧个人署名提交及此前匿名基线，共 13 个已知旧 SHA，Git 对象接口均返回 404，提交接口均返回 422「No commit found」。独立验收确认其不能通过当前仓库读取，不据此宣称 GitHub 后台备份已物理擦除。
- 历史已从使用 GitHub 用户名和隐私邮箱的无父初始提交重新开始，后续文档提交沿用该身份；v0.1.1 标签指向已验收源码 `a70d9f6`。本次只更新状态文档及公证安装包，应用代码不变；包内容变化限于公证票据、DMG 根目录状态说明及容器签名。Developer ID 的合法签名身份信息保留。

证据位于 `.tmp/privacy-cleanup/`，独立产物报告为 `verification/artifacts-independent.json`，远端报告为 `verification/recreated-remote-independent.json`；流程与边界见 [隐私与发行检查](privacy.md)。下述功能段落为此前验收记录，历史临时文件可能已按隐私清理规则移除；当前安装与产物状态以本节及安装包表为准。

## 界面间距回归

本轮检查全部 6 个界面文件及应用场景，确认并修复两处问题：搜索框缺少内容内边距，放大镜贴近系统工具栏圆角边缘；来源片段固定行号栏宽度让六位行号折行，造成代码行距错位。其余备注输入、分组弹窗、诊断、原生表单和菜单未发现同类确定性问题。

在本机使用隔离的 3 个测试主机及含 100,000 行空白的配置样本进行真实 GUI 检查：1120 × 720 窗口下，明暗模式的搜索框留白正常；输入 `edge` 后列表从 3 项变为 1 项，清除后恢复 3 项；来源行号 `99999` 至 `100004` 均保持单行，代码列对齐。ARM／Intel Debug 构建和 Harness task 检查通过。没有连接服务器或修改个人配置。

间距回归的截图与构建日志位于 `.tmp/spacing-audit/`；README 的亮暗截图已更新为修复后的隔离界面。最小窗口与搜索焦点的补充验收见下节。

## 最小窗口与搜索焦点回归

实际复现了搜索命令被收到、请求观察器执行后，焦点仍留在备注编辑器的问题；下移 SwiftUI 焦点监听器未解决。因此仅将搜索输入改为局部 AppKit 文本控件桥接，保留间距、宽度、过滤与清除行为。只有实际 field editor 成为第一响应者后才消费请求；挂载和窗口激活时处理未完成请求，明确搜索命令全选已有文字，普通文字更新不改变光标。临时诊断代码已移除。

窗口恢复补测还发现搜索会新建窗口、留下原先最小化窗口的问题。主窗口识别改用场景挂载时注册的弱窗口集合，复用可见或最小化窗口，不再依赖会被 SwiftUI 生命周期重写的窗口 identifier；关闭后由 SwiftUI 管理场景生命周期。

| 验收场景 | 实际结果 |
| --- | --- |
| 最小尺寸 | 日志确认主内容区 `880 × 560` 点，含系统工具栏的整窗 `880 × 612` 点；三栏、搜索、连接与复制按钮完整可见 |
| 备注区、主机列表中按 `⌘F` | 直接输入进入 `hostSearch`，过滤得到对应主机；备注内容不变 |
| 重复按 `⌘F` | 已有查询被全选，新输入直接替换 |
| 清除搜索 | 3 个测试主机恢复显示，搜索输入保持焦点 |
| 主窗口最小化、关闭后按 `⌘F` | 主窗口恢复或重开，输入直接进入搜索框 |
| 恢复时窗口数量 | 清理此前验收遗留窗口后，基线为 1；最小化后搜索、关闭后搜索，原生 Window 菜单均仍只有 1 个主窗口 |
| 设置窗口中按 `⌘F` | 主窗口置前，搜索输入获得焦点 |
| 数据与构建 | 隔离元数据文件摘要与基线一致；最终 ARM／Intel Debug 构建及 Harness task 通过，未连接服务器 |

本次使用原生 Window 菜单的贴靠操作缩小窗口，随后重启恢复到确切最小尺寸；未修改系统外观或窗口管理设置。证据位于 `.tmp/window-focus/results.json`、`runtime.log`、`window-counts.json`、`window-routing-build.log`、`final-x86_64-build.log` 与同目录截图、AX 状态记录。Intel 原生运行和 macOS 14 运行仍未验证。

## 新版详情与焦点回归

采用已确认的 HTML 方案，实现原生声明概览、阅读态备注、分组声明及折叠来源片段。以 4 个假主机、6 份隔离配置验证，不连接服务器，不读取私钥。主内容区最小约束仍为 `880 × 560` 点；亮色截图为 `1760 × 1224` 像素（2 倍），深色贴靠截图包含额外 1 点系统边界，为 `1762 × 1224` 像素。

| 验收场景 | 实际结果 |
| --- | --- |
| 明暗模式与最小窗口 | 标题、连接／复制、声明概览和备注可见；长别名换行，地址不被挤成窄列；缺省端口显示“未声明／由 SSH 判断” |
| 多处声明 | 同一端口显示“2 处声明”，完整声明保留各自文件与行号，条件声明明确标记 |
| 来源定位 | 点击第 22 行、滚走后再次点击同一行、切换到另一文件第 2 行均可见高亮；片段保留不连续范围的省略标识 |
| 原生无障碍读取 | 来源跳转后可正常获取 AX 树与截图；移除静态代码文本的焦点接管及自定义 AX label，未再触发先前的递归崩溃 |
| 搜索焦点 | 从备注编辑器按 `⌘F` 后输入进入搜索；重复命令替换查询；`⌘R` 后搜索仍聚焦，备注不受搜索文字影响 |
| 备注保存与重启 | 原生编辑写入 JSON，重启后恢复；已通过原生编辑还原测试备注 |
| 保存失败 | 人为损坏隔离元数据后显示错误且保留损坏文件；切换主机后失败草稿恢复，搜索焦点未被抢走；草稿仅保留于当前运行期间 |
| 无选择连接快捷键 | 搜索无结果后按 `⌘Return`，保持空选择，无终端交接或错误提示 |
| 自动检查 | 47 条 Core XCTest 通过（含 10 条新增来源片段测试）；ARM／Intel Debug 编译和 Harness task 通过 |
| 只读边界 | 6 份隔离 SSH 配置 SHA-256 与基线完全一致；隔离元数据最终内容恢复为基线 |

外层 SwiftUI 滚动代理无法可靠定位横向代码滚动区内的行，因此使用透明 AppKit 行锚点，仅负责布局后的纵向定位，不接管选择或键盘焦点。来源片段读取保持在 Core，按所有声明位置合并上下文，白名单检查先于文件读取，并显式报告来源变化与读取失败。

证据：`.tmp/detail-redesign/core-tests.log`、`arm64-build.log`、`x86_64-build.log`、`harness-task.log`、`results.json` 及 `native-qa/`。README 明暗截图为本轮原生界面；Intel 与 macOS 14 运行、真实 Terminal 自动化交接和新版 DMG 未在本轮验证。

## 全部主机二级菜单

右侧状态栏入口和应用“主机”菜单共用 `AllHostsMenu`，从 `snapshot.hosts` 读取完整索引，按别名自然排序，显示总数。每项调用现有 `store.connect(host)`，继续校验别名并复用 Terminal 交接与最近记录；不新增连接实现。长标题保留头尾共 30 个字符，提供完整提示及无障碍标签。

- 原生应用“主机”菜单 AX 观察确认 81 个隔离假主机全部列出，排序为 `qa-node-1、qa-node-2…qa-node-9、qa-node-10…qa-node-80`。
- 源码复核确认菜单独立于主窗口的 `visibleHosts`，首次读取及空列表有提示；搜索／分组筛选独立性尚未完成 GUI 复测。
- 最终 ARM／Intel Debug 构建、47 条 Core XCTest 及 Harness task 通过；本轮未改变 Core 和连接服务。
- 最后一次 GUI 复测期间 CUA／AX 连接超时；进程仍在，只读 3 秒采样的 2540 次主线程样本均处于正常事件循环等待，CPU 为 0.0%，无新增崩溃报告。
- 未取得右侧状态栏展开、原生长菜单滚动、最终长标题视觉和菜单点击后实际 Terminal 交接证据；未发起真实服务器连接。

证据位于 `.tmp/all-hosts-menu/`：`arm64-build.log`、`x86_64-build.log`、`core-tests.log`、`harness-task.log`、`runtime-sample.txt`。原生菜单观察来自本轮会话 AX 工具输出，未取得截图；不将源码与编译结果当作完整 GUI 验收。

## 手动刷新与按钮稳定性

最新产品要求替代首版计划中的自动刷新：应用启动首次读取，之后只响应用户主动刷新，不再使用 FSEvents、定时扫描或应用激活通知。删除旧文件监听实现及测试入口，以 `./script/test_manual_refresh.sh` 作为隔离回归入口，并同步项目规范与 Harness 检查。

原抖动实现会在工具栏中交替创建刷新按钮和独立 `ProgressView`。现在使用同一个按钮、固定图标尺寸及原位进度覆盖；250 毫秒以内的扫描不显示转圈，读取中禁用重复点击，减少动态效果时使用静态图标及状态标签。

| 检查 | 实际结果 |
| --- | --- |
| 配置变化／应用激活 | 隔离 AppStore 驱动修改配置并发送激活通知后，快照与初次读取时间保持不变 |
| 手动刷新 | 主动调用后读取变更及新增 Include；扫描中追加 20 次请求，完成后不自动续扫 |
| 按钮尺寸 | 离屏生产组件在明暗、空闲、加载状态下，固有尺寸均为 `40 × 24` 点；不以此代替完整工具栏像素验收 |
| 实际 GUI | 初始 2 个测试主机；配置增加第 3 个后仍显示 2 个，点击刷新后更新为 3 个；原生按钮 ID 保持 `refreshConfiguration` |
| 构建与规范 | 47 条 Core XCTest、ARM／Intel Debug 编译、Harness task 与项目配置校验通过 |

证据位于 `.tmp/refresh-jitter/`：`manual-refresh-check.log`、`core-tests.log`、`arm64-build.log`、`x86_64-build.log`、`harness-task.log`、`harness-config-validation.log` 及 `gui/`。测试只修改应用自建夹具，没有修改个人 SSH 配置或连接服务器。旧安装包仍含旧刷新行为，未在本轮重打包；Intel／macOS 14 原生运行仍未验证。

## 默认终端选择

设置增加默认终端选择器，所有连接入口共用 `AppStore.preferredTerminal`，保存于本机 `UserDefaults`；初始为 Terminal。目标应用按 bundle ID 检测，不接受任意脚本或命令模板。每款应用使用固定 AppleScript handler，别名作为单个 AppleEvent 参数传入，固定命令继续使用 `/usr/bin/ssh --` 和 `quoted form`。所选应用缺失时明确报错，不静默改用其他终端。

| 检查 | 实际结果 |
| --- | --- |
| 默认／保存／恢复 | 独立偏好 suite 中缺省为 Terminal，选择 Ghostty 后新建 AppStore 能恢复；未知值按 Terminal 读取，原偏好值不被初始化覆盖；主机元数据不变 |
| 应用可用性 | 本机识别 Terminal 与 Ghostty 1.3.1；iTerm2 未安装。夹具覆盖缺应用、错误 bundle ID、未知／过低版本及 Ghostty 1.3.0 边界 |
| 安全参数 | 空值及控制字符在发送前拒绝；空格、引号、命令替换字符、中文及前导连字符均保持为单个 AppleEvent 字符串，不进入脚本源码 |
| 原生设置 | 默认 Terminal、未安装 iTerm2 灰显已通过 AX 观察；修复了普通 `.disabled` 未禁用 Picker 选项的问题，改用 macOS 14 起支持的 `selectionDisabled` |
| 非默认名称／错误路径 | 持久化的 iTerm2 偏好在重启后显示“在 iTerm2 中连接”；对缺失应用点击连接后明确报错，未启动其他终端、未修改最近记录 |
| GUI 限制 | 对禁用项的自动点击超时；之后选项仍灰显、值保持 Terminal。Ghostty 选项的实际点击复测被 CUA 窗口状态变化错误阻断，因此未取得其原生选择／重启的完整流程证据 |
| 回归与构建 | 47 条 Core XCTest、终端隔离驱动、手动刷新驱动、ARM／Intel Debug 构建、Harness task 和项目配置校验通过 |

Ghostty 的接口、1.3.0 起的支持范围与授权依据来自[官方 AppleScript 文档](https://ghostty.org/docs/features/applescript)、本机 1.3.1 的 `Ghostty.sdef` 和[命令解析说明](https://ghostty.org/docs/config/reference#command)；macOS 不使用仅适用于 GTK 的 `+new-window`。iTerm2 的新窗口调用依据其[官方脚本文档](https://iterm2.com/documentation-scripting.html)，该 API 已标为 deprecated，且本机未安装，未进行其运行验收。

证据位于 `.tmp/terminal-preferences/`：`terminal-launcher-check.log`、`core-tests.log`、`manual-refresh-check.log`、双架构构建日志、Harness 日志及 `gui/`。本轮未编译／执行终端 AppleScript、未触发实际自动化授权或连接服务器；未将源代码、参数验证或缺失应用错误路径当作成功交接证据。测试前的终端偏好已恢复。

## 本机安装与首次读取修复

首次安装验收时版本为 `0.1.0（1）`，路径为 `/Applications/HostShelf.app`，仅含 `arm64`，使用 Developer ID 签名及安全时间戳；主程序和 Core 均启用 Hardened Runtime，无调试／沙盒权限，应用仅声明 Apple Events 权限。以下为当时的修复与验收历史，当前安装版见下节。

首次安装验收发现主机列表停留在读取中。3 秒采样的全部 2639 个后台样本均在 `Scanner.watch → attributesOfItem → getxattr`，主线程正常等待事件。该监听目录计算已没有生产消费者；本轮移除其祖先遍历、`globBase` 与 `watchedDirectories` 字段，并将源文件必要的类型／大小判断改为基本 `lstat`。没有把等待归因为未经证实的权限拒绝或文件提供程序故障，没有修改个人配置。

| 检查 | 实际结果 |
| --- | --- |
| 索引与边界 | 47 条 Core XCTest 通过；仍覆盖软链接、Include、不可读、非普通文件、UTF-8 和超 8 MB 限制；原监听断言改为实际来源、声明与主机结果断言 |
| 服务回归 | 手动刷新和终端参数／偏好隔离驱动通过 |
| 构建 | 当前源码 ARM／Intel Release 均成功；只安装本机 ARM 版本，不代表 Intel 原生运行已验收 |
| 最终应用 | `/Applications` 下严格签名、版本、纯 ARM、最低系统和权限检查通过；独立核对 Mach-O UUID 与本轮 Release 匹配 |
| 实际首次读取 | 已从安装路径启动；原生 AX 读取确认配置读取完成且无元数据错误；不记录真实数量，未导出主机地址或发起连接 |

证据位于 `.tmp/local-install/`：修复前 `runtime-sample.txt`、`indexer-fix-tests.log`、两架构 Release 构建日志、服务回归日志、`installed-artifact.json`、`installed-binary.sha256`、`install-receipt.json` 和仅含计数的 `runtime-summary.json`。本轮替换的初次安装构建保留于工具缓存，位置记录在 `previous-app-path.txt`。公证、下载后 Gatekeeper、干净环境安装和真实终端交接仍未执行。

## 公证 ARM 版本机更新

2026-10-25 14:17，使用下表同一公证 ARM DMG 更新 `/Applications/HostShelf.app`，版本为 `0.1.1（2）`。安装前正常退出已有实例，复制并核对完整 App 文件与符号链接；安装后签名、公证票据、Gatekeeper、架构、权限和路径隐私检查通过，没有重新构建或重签 App。

独立原生验收确认安装路径实例唯一、启动完成、可见主窗口响应、首次索引读取完成且无元数据错误。退出前、退出后、替换后及重新打开后的 SSH 配置、应用数据目录和默认终端偏好摘要完全一致，备注、收藏和分组保留。验证只记录摘要与布尔结果，没有记录真实主机、地址、备注或数量，没有读取私钥或发起服务器连接。

证据位于 `.tmp/notarized-install/`：`install-receipt.json`、`source-app-manifest.json`、`installed-artifact.json`、`data-comparison.json` 和 `independent-runtime.json`。本机升级与启动不代替干净 Mac／断网首次安装、macOS 14 或 Intel 原生运行验收。

## 安装包

本地位置：`dist/release/`；下载入口：[私有 v0.1.1 Release](https://github.com/maydaychen/hostshelf/releases/tag/v0.1.1)。两种架构为同一应用的替代包，不是两个独立应用。

Release 标记为预发布，标签固定于构建源码 `a70d9f6`。两份公证附件已替换原同名附件；名称、大小、上传状态及 GitHub SHA-256 摘要通过核对，从认证下载接口取得的文件哈希与下表及本地原件完全一致。更新前后仓库均为私有；旧包使用者需重新下载。此次证据位于 `.tmp/notarize-0.1.1/`，初次上传记录保留于 `.tmp/github-release-0.1.1/`。

| 文件 | SHA-256 |
| --- | --- |
| HostShelf-0.1.1-macos-arm64.dmg | `95139718f05f175db2edb26bcb75c0165bb59f23c2befaa30ffa219e4b9b9cf8` |
| HostShelf-0.1.1-macos-x86_64.dmg | `ef991013187e98512ecfd869916bb310c16eedcf746ce9a4cbd5c2d2f07bde1b` |

两个 App 各含主程序和 HostShelfCore 两个实际 Mach-O；均启用 Hardened Runtime，无 `get-task-allow` 和 App Sandbox。主 App 仅声明 `com.apple.security.automation.apple-events`，有对应用途说明。DMG 内包含 Applications 链接及签名状态说明。两个挂载已卸载。

四项 Apple 提交均为 `Accepted`，独立验收在线复核结果一致：

| 架构 | App 公证 ID | DMG 公证 ID |
| --- | --- | --- |
| arm64 | `4b1238b1-7d77-4025-9b2f-f8e6ffc59260` | `d83b0a09-fa22-4ec4-9609-fe0fab64ce01` |
| x86_64 | `128cc3a5-9281-4361-923e-fd378510dcfc` | `48d18c3b-e1bb-4bc5-b708-2d239098cd7b` |

每个 App 和 DMG 的 `stapler validate` 通过；`spctl --assess --type execute` 检查 App，`spctl --assess --type open --context context:primary-signature` 检查 DMG，均返回 `Notarized Developer ID`。表中 SHA-256 在最终 DMG 装订后计算。当前机器的票据与 Gatekeeper 检查不代替干净 Mac／断网首次安装验收。

## 复验入口

从项目根运行：

```sh
./script/test.sh
./script/test_manual_refresh.sh
./script/test_terminal_launcher.sh
./script/check_readonly.sh
./script/build.sh arm64
./script/build.sh x86_64
./script/build_and_run.sh --verify
./script/verify_packages.sh --signed
python3 scripts/harness/verify.py --mode task
```

工具沙盒若阻止 SwiftPM／Xcode 的嵌套编译沙盒、原生组件测试、进程查询及磁盘映像挂载，需要在获授权的非沙盒工具环境执行，不关闭编译或签名安全检查。编译和磁盘映像暂存使用操作系统临时目录，避免 File Provider 异步重新添加 FinderInfo；日志仍在项目 `.tmp/`，安装包在 `dist/`。

当前会话原始证据：`.tmp/evidence/core-tests.log`、`watcher.log`、`readonly-index.json`、`normal-launch.json`、`package-developer-id.log`、`package-verification.log`，独立报告为 `.tmp/release-verifier/signed-preview-verification.json`。亮暗截图已保存到 `docs/images/`。

## 后续门槛

- 使用真实签名 Release 构建验证所选终端自动化首次允许、拒绝、恢复及新窗口行为；真实服务器连接须有明确目标和授权。
- 取得 macOS 14 Apple Silicon、macOS 14 Intel 测试环境；Intel 交叉编译不算 Intel 运行验收。
- 补充干净 Mac／断网首次安装验收；本机签名、票据和 Gatekeeper 检查已通过，不得以关闭 Gatekeeper 作为验收通过。
- 当前已完成清洁公开基线与标准 sRGB 截图重拍，待重建公开仓库并同步 `v0.1.3` 预发布后补充公开远端独立验收；提交身份继续使用 GitHub 隐私邮箱。公开发行仍需相应授权与实机验收。
