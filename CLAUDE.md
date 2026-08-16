# AutoJs6 项目说明

## 项目概述

AutoJs6 是一个 Android 自动化工具，支持 JavaScript 脚本编写和执行。

## 当前标识（com.simple.process 基线）

此仓库的 applicationId / namespace 已从上游 `org.autojs.autojs6` 改为 `com.simple.process`，源码包名仍保持 `org.autojs.autojs.*` 不变。可据此与原版 `org.autojs.autojs6` 同时安装。

| 配置项 | 值 | 说明 |
|--------|-----|------|
| namespace | `com.simple.process` | 生成 `R` / `BuildConfig` 的包名，源码里 `import com.simple.process.R` |
| globalApplicationId | `com.simple.process` | `app/src/main/java/org/autojs/autojs/App.kt` 等已 `import com.simple.process.R` |
| `app` flavor applicationId | `com.simple.process` | 完整版应用 |
| `inrt` flavor applicationId | `com.simple.process.inrt` | 打包脚本运行时（`applicationIdSuffix = ".inrt"`） |
| FileProvider authorities (`app`) | `com.simple.process.fileprovider` | `app/build.gradle.kts:505` |
| FileProvider authorities (`inrt`) | `com.simple.process.inrt.fileprovider` | `app/build.gradle.kts:529` |
| 显示名称 | `AutoJs6 Alt` | `app/src/main/res/values/strings.xml:16` 的 `app_name` |

### 改回原版标识如需

修改 `app/build.gradle.kts`：line 29 `globalApplicationId`、line 459 `namespace`、line 505 / 529 `authorities`，并全局把源码的 `import com.simple.process.R` 改回 `import org.autojs.autojs6.R`。

## 已知问题（启动闪退）

应用启动即闪退，根因尚未最终定位。
- 已排除：`AccessibilityTool` 在 `GlobalAppContext` 未就绪时的 NPE（远程 `50d059b` 已_lazy 化并 `runCatching` 包裹 `BaseActivity.onCreate`）、manifest 缺 `MainActivity` 声明（`b8cf0e8` 已补）。
- 候选崩点：`App.onCreate` 初始化链（`AutoJs.initInstance`、`TimedTaskScheduler.init`、`initDynamicBroadcastReceivers`、`MlKitContext.initializeIfNeeded`、`ThemeColorManager.init`）或 `ExplorerFragment`（首页首个 Fragment）。
- 远程 CI 的 `instrumented-test` 跑的是第三方库 example 测试，从不启动 app，无法捕获启动崩溃——CI 绿 ≠ 不闪退。

## 构建项目

### 环境要求
- JDK 21（CI 用 Temurin 21；项目同时设置 min 17）
- Android SDK（NDK 26.1.10909125 / 23.1.7779620）
- Gradle 9.4.0（gradle-wrapper 已固定）

### 常用构建命令

```bash
# Debug 完整版（单 arch，CI 常用）
./gradlew :app:assembleAppDebug -Pandroid.injected.abi.list=x86_64

# Release 版本
./gradlew assembleAppRelease

# inrt 版本（打包脚本运行时）
./gradlew assembleInrtRelease

# 单元测试
./gradlew :app:testAppDebugUnitTest

# 清理 / 同步 / 依赖树
./gradlew clean
./gradlew --refresh-dependencies
./gradlew app:dependencies
```

## 项目结构

```
├── app/                    # 主应用模块
├── build-logic/           # Gradle 构建逻辑
├── libs/                  # 第三方库
├── modules/               # 功能模块
├── plugin-api/            # 插件 API
└── scripts/watch-ci.sh     # 本地轮询 CI 并 dump 崩溃栈
```

## CI 与启动诊断

### 强制流程（每次 push 后必做）

> **规则：任何 `git push` 到 master 后，立即执行一次 `scripts/watch-ci.sh`，不得跳过、不得在脚本退出前中断、不得靠手动反复 `go on` 轮询。**

push 触发的 workflow 只跑 `startup-diagnosis` job（见下），需约 15 分钟。脚本会自己轮询到 run 真正结束并 dump 崩溃栈，期间无需人工干预。

```bash
git push origin master
HTTPS_PROXY=http://127.0.0.1:7897 ./scripts/watch-ci.sh          # 等当前 run 完成
# 或指定 run：
HTTPS_PROXY=http://127.0.0.1:7897 ./scripts/watch-ci.sh <run-id>
```

脚本保证：run 标记 completed **且**每个 job 都 terminal 之后才退出；中间网络抖动不会误判完成；超时 60 分钟（`WATCH_CI_MAX_MINS` 可调）。
退出码：0 完成（成功或闪退都需人看输出）/ 1 配置错 / 2 超时 / 3 没 startup-diagnosis job。

### 执行方式必须前台阻塞

**watch-ci.sh 必须前台运行并阻塞到它自行退出**，是指 Claude Code 在 push 后用 Bash 工具（前台，`run_in_background: false`）执行该脚本并等其返回，**不允许后台执行**（不 `run_in_background`、不 `&`）。

> 注意：Claude Code 的 Bash 工具单次调用默认 10 分钟超时。`startup-diagnosis` 单 job 约 15 分钟，前台调用必然超时被系统转后台——这是预期内的回退，不违反此规则（脚本本就会坚持到 run 真正结束）。可设较长 `timeout`（如 `3600000`ms=60min）尽量保持前台；即便被转后台，命令仍在运行、完成时通知，读其 output 文件即为同等的"脚本输出"。
>
> 重试规则：若前台调用被硬超时截断（未拿到脚本自身的结束输出），**立即再前台发起一次 `watch-ci.sh`**，最多连续 3 次。脚本幂等——同一 run 再跑只是重新轮询到 completed 后重新 dump 日志，不会重复触发 CI，所以重试安全。
>
> 关键语义：不主动发起新的后台 `watch-ci.sh`、不提前 `TaskStop` 它、更不用 `gh run view` 手动反复轮询来替代脚本。

### workflow 说明

`.github/workflows/android.yml`：调试期仅保留 `startup-diagnosis` job（`test` / `instrumented-test` / `build` 暂注释，定位完成后再恢复）。

`startup-diagnosis` job：构建 x86_64 debug APK → 复制到工作区 `built-apk/app-debug-x86_64.apk`（`$GITHUB_WORKSPACE` 路径，避开 emulator script 的 cwd/glob 与 `/tmp` 不共享问题）→ emulator 启动 `com.simple.process/org.autojs.autojs.ui.splash.SplashActivity` → 抓 `adb logcat` 的 `FATAL EXCEPTION` 堆栈 → `pidof` 判断进程存活 → 日志写入工作区并上传 artifact。`continue-on-error: true`，崩溃也让 run 绿，目的是拿堆栈而非卡 CI。emulator-runner 用 POSIX sh 执行 `script`，脚本内禁用嵌套 `$(ls ... || echo)` 等易破坏引号的结构。

### 输出判读

重点看 `watch-ci.sh` 打印的这些行：
- `Resolved APK =>` / `adb install rc=`（0 = 装机成功）
- `pidof com.simple.process => [...]`（有值 = ALIVE 不闪退，空 = GONE 闪退）
- `FATAL EXCEPTION` / `AndroidRuntime` / `Caused by` / `at org.autojs.*` = 崩溃堆栈定位根因

完整日志（含非 error 级）用 `gh run download <run-id> -n startup-diagnosis-logs`。

### 注意事项
- 代理：GitHub 需要 `http(s)_proxy=http://127.0.0.1:7897`；`gh auth status` 已登录账号 `ff0x5f`（scopes 含 `repo`/`workflow`）。
- emulator：GitHub ubuntu runner 不支持 arm64 镜像，必须 `arch: x86_64`；boot 约 7 分钟属正常。

## Product Flavors

| Flavor | ApplicationId | 用途 |
|--------|--------------|------|
| `app` | `com.simple.process` | 完整版应用 |
| `inrt` | `com.simple.process.inrt` | 打包脚本运行时 |

## 签名配置

签名密钥配置在 `app/signing.properties`（需自行创建）：

```properties
storeFile=path/to/keystore.jks
storePassword=xxx
keyAlias=xxx
keyPassword=xxx
```

### 源码包名与 namespace 的不对称（重要）
- 源码 Kotlin 包名仍是 `org.autojs.autojs.*`（未重构）。
- `namespace`（决定 `R`/`BuildConfig`）是 `com.simple.process`，故源码顶部 `import com.simple.process.R` 和 `import com.simple.process.databinding.*`。
- 改 namespace 必须同步改所有 `import *.R` 与 `import *.databinding.*`，否则编译失败。

### 未随改名处理的标识符
以下组件仍用上游旧标识符，按需修改：
- 自定义权限 `org.autojs.permission.PLUGIN`
- Broadcast action `org.autojs.autojs.action.task`
- 各 Activity 的 taskAffinity（如 `org.autojs.autojs.edit`）

## 相关链接

- 项目主页: http://project.autojs6.com
- VSCode 扩展: http://vscext-project.autojs6.com
