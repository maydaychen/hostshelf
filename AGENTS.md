# HostShelf

## 项目定位与边界

HostShelf 是 macOS 14+ 的 SSH 主机目录与终端启动器。SSH 配置仅作为只读输入；只在用户主动连接时向所选终端交接别名。不得在索引阶段运行 SSH、`ssh -G`、`Match exec`，不得读取 IdentityFile、修改 SSH 配置或触发真实服务器连接。

## 目录与事实源

- `Sources/HostShelfCore/`：可独立测试的配置索引、模型、本地元数据和命令构造。
- `Sources/HostShelf/`：SwiftUI 界面、共享应用状态与外部终端桥接。
- `Tests/HostShelfCoreTests/`：隔离配置与持久化回归测试，不使用个人真实配置。
- `Tests/ServiceChecks/`：终端参数、偏好保存、手动刷新及原生组件的隔离回归，不执行真实连接。
- `script/`：构建、测试、运行及分架构打包入口。
- `project.yml`：XcodeGen 工程、版本、最低系统与构建设置的事实源；生成工程一并提交。
- `DESIGN.md`：界面设计事实源；`README.md`：实际用法；`ROADMAP.md`：当前进度和验证证据。
- `goals/`：实施清单与验收交接；不代表已创建 Goal。
- `.tmp/`：本次任务缓存、构建和测试证据；`dist/`：发布与试用交付目录，禁止把带本地说明的 `--preview` 试用包标成公开正式发行。

## 工程纪律

使用系统框架，不添加运行时第三方依赖。Core 与 GUI 分离；按职责分文件，500 行警告、1000 行硬上限。索引结果是配置声明，不是最终 SSH 生效配置；连接交接成功不等于登录成功。读配置失败必须显式诊断。

启动时仅首次读取配置，之后只响应用户主动刷新。不得使用文件监听、定时扫描或应用激活触发刷新。

ARM 和 Intel 分别构建、验证、打包，保持相同版本及应用身份；不交付 Universal 包代替两个安装包。不得把 Intel 交叉编译结果说成 Intel 运行验收。

Release 构建须映射源码及编译目录，剥离调试路径记录；最终签名前检查整个 App 不含个人主目录、系统临时构建路径、随包 dSYM 或调试映射。Core 的动态导出必须保留。公开开源分发统一采用 `./script/package.sh --anonymous` 生成分架构（`arm64`、`x86_64`）匿名构建：外层 DMG 不签名，内部 App 与 Framework 仅做本地 `ad-hoc` 签名（`Signature=adhoc`、`TeamIdentifier=not set`，不含 Developer ID 证书或 Apple 公证），并由 `./script/verify_packages.sh --anonymous` 与 `script/check_binary_privacy.py` 复验。仅在明确需要本机／私有签名分发时才显式使用 `--developer-id` 或 `--signed`，Developer ID 证书的合法身份信息仅属于对应显式签名模式。

## 工作流与验证

本机共享规范位置按忽略的 `AGENTS.local.md` 读取，不在仓库记录个人 Wiki 路径。本项目是 macOS 桌面应用，不套用 iOS Simulator 或 App Store 提审流程。

当前 Harness 检测未提供匹配的 macOS Profile，保留空 Profiles；实际门禁由本项目的 Core 测试、macOS 构建和手动刷新检查定义。

依次使用 `./script/test.sh`、`./script/test_manual_refresh.sh`、`./script/test_terminal_launcher.sh`、`./script/test_app_interactions.sh`、`./script/build.sh arm64`、`./script/build.sh x86_64`；运行使用 `./script/build_and_run.sh --verify`。交互回归使用注入终端和隔离元数据，不发送真实连接。公开打包默认使用 `./script/package.sh --anonymous` 与 `./script/verify_packages.sh --anonymous`；只有明确执行 `--developer-id`／`--signed` 模式时才从 Keychain／环境读取对应签名与公证凭据。

完成检查点后更新 ROADMAP，记录北京时间和实际证据。提交使用中文 Conventional Commits，只提交本项目改动；无授权不推送或公开发布。无法获取签名、Intel／最低系统运行环境或自动化权限时，保留缺口并继续完成可验证部分。

<!-- HARNESS_VERIFICATION_START -->

## Harness 验证

- 验证事实源：`.harness/verification.json`。
- 固定入口：`scripts/verify-before-push.sh`。
- Profiles：待确认。
- Adapters：无。
- 文件规模门禁：超过 500 行警告，超过 1000 行失败。
- `.` 检查：source-file-lines, project-configuration, shell-syntax, core-unit-tests, macos-arm64-build, macos-intel-build, manual-refresh, terminal-launcher, app-interactions, binary-privacy-tests, release-binary-privacy。

<!-- HARNESS_VERIFICATION_END -->
