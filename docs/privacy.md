# 隐私与发行产物检查

本项目提交使用 GitHub 用户名和隐私邮箱。SSH 配置、主机备注及终端偏好只保留在本机，不纳入源码或发行包。

## 发行构建

使用 `./script/build.sh <arm64|x86_64> Release`。脚本将实际源码及构建目录映射到中性的 `/HostShelf`、`/HostShelfBuild`，Release 剥离调试记录并保留动态导出。Debug 保留本机调试能力，不作为发行产物。

Release 构建、打包前和最终产物复验均调用 `script/check_binary_privacy.py`。检查直接读取文件字节及 Mach-O 结构，覆盖主程序、嵌入框架和 App 资源，拒绝个人主目录、系统临时编译路径、调试来源／对象映射、内嵌 DWARF 或 dSYM；系统运行依赖如 `/System`、`/usr`、`@rpath` 可以保留。日志只输出相对文件名、类别和计数。

```sh
python3 Tests/ServiceChecks/BinaryPrivacyCheck.py
./script/check_release_privacy.sh
python3 script/check_binary_privacy.py /Applications/HostShelf.app
./script/verify_packages.sh --anonymous
```

压缩的 DMG 应只读挂载后检查其中的 App；不能用压缩文件的字符串扫描代替内容验证。dSYM 只用于本机调试，不随包交付；删除不再使用的历史构建缓存时也应清理旧 dSYM。

公开 GitHub 发行产物统一使用 `./script/package.sh --anonymous` 与 `./script/verify_packages.sh --anonymous`，保证外层 DMG 不签名且内部 App 与 Framework 仅为本地 `ad-hoc` 签名（`Signature=adhoc`、`TeamIdentifier=not set`，不启用 Hardened Runtime，无 `Authority=` 证书身份或公证记录），不暴露签名证书姓名／Team ID、个人主目录或本机编译路径。仅在本机自用或明确授权的私有 Developer ID 构建（`--developer-id`／`--signed`）中才启用 Hardened Runtime 并出现对应证书的合法身份信息，不可将其当作匿名公开包分发。

## Git 历史与 GitHub 残留

重置分支只移除可达历史。本机清理还需核对工作区、stash、refs、reflog、对象库及回滚 bundle，避免备份继续保留原身份信息；不删除其他任务或项目的数据。

GitHub.com 没有供仓库所有者调用的旧提交对象垃圾回收接口。旧 SHA 是否仍可读必须单独验证；保持私有可以限制访问，但不能等同于永久删除。需要平台清理时，可按 [GitHub 官方说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository#fully-removing-the-data-from-github) 申请处理；是否受理由 GitHub 判断。删除、重建、公开仓库或发送支持请求均须获得对应明确授权。

当前仓库已清理两张含旧目录路径与显示器 ICC 元数据的截图，并以清洁源码的单个无父提交准备公开仓库基线；后续提交继续使用 GitHub 用户名及隐私邮箱。验证时先确认当前提交和文件可以正常读取，再检查旧仓库／旧 SHA 的 Git 对象接口返回 404、提交接口明确报告找不到该 SHA，避免将凭据失效误判为清理成功。该结果只证明旧对象不能通过当前公开仓库读取，不证明 GitHub 后台备份已经物理擦除。实际验收范围见 [验收记录](acceptance.md)。
