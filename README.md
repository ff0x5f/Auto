`SuperMonster003/AutoJs6` 是基于原 **Auto.js** 项目（由 hyb1996 开发）的一个二次开发分支。它是一个在 **Android** 平台上利用 **无障碍服务** 实现 **JavaScript 自动化** 的工具。

以下是该项目 README 及相关文档的摘要总结：

---

### ## 核心简介
* **项目定位**：Android 平台上的 JavaScript 自动化工具，支持无障碍服务。
* **系统要求**：最低支持 **Android 7.0 (API 24)** 及以上版本。
* **开发语言**：脚本语言为 JavaScript，底层执行引擎基于 **Rhino**。
* **主要目标**：在原版 Auto.js 停止维护或转为闭源商业版后，提供一个持续更新、功能增强且对开发者友好的开源替代方案。

---

### ## 主要特性与增强
该版本相比原版 Auto.js 进行了大量的现代化改造和功能扩展：

* **现代 JS 语法支持**：
  * 通过升级 Rhino 引擎，支持了许多 ES6+ 的特性。
  * **BigInt** 支持：`typeof 567n === 'bigint'`。
  * **模板字符串**：可以使用 `` `Lucky number: ${num}` ``。
  * **新增方法**：支持 `Object.values()`、`Array.prototype.includes()` 以及 `Unicode` 辅助平面字符转义（如 `\u{1D160}`）。
* **网络与工具类增强**：
  * 新增异步网络请求方法，如 `http.getAsync`、`http.postAsync` 等。
  * 新增 `http.put`、`http.del`、`http.head` 等标准 HTTP 方法支持。
  * 提供像素单位转换工具：`util.dpToPx`、`util.pxToDp` 等。
* **UI 与系统交互**：
  * 支持获取状态栏和导航栏的可见高度。
  * 集成了 **Shizuku**、**WebSocket**、**OCR (PaddleOCR)**、**条码/二维码** 扫描等现代功能插件支持。
* **开发者工具**：
  * 拥有配套的 **VSCode Extension**，支持在个人电脑上进行远程开发和调试。

---

### ## 项目状态
* **许可证**：采用 **MPL-2.0** 开源协议。
* **更新频率**：该项目在 2024-2026 年间保持着活跃的更新频率（截至 2026 年 3 月仍有版本发布）。
* **文档支持**：拥有完善的在线文档站点（[docs.autojs6.com](https://docs.autojs6.com)），涵盖了从基础 API 到高级插件的详细说明。

---

### ## 常见用途
1. **自动化测试**：对移动端应用进行 UI 自动化测试。
2. **效率工具**：编写脚本自动完成重复性任务（如：自动签到、自动收集能量、抢券等）。
3. **辅助功能**：为残障人士开发特定的辅助操作脚本。

**注意**：使用此类工具时应遵守相关法律法规及目标平台的开发者服务条款。

---

## 功能点与代码位置索引

### 启动流程

用户打开 App → SplashActivity（1秒启动页） → 自动跳转 SnipeActivity（抢购页） → 用户点击"Go to Main" → MainActivity

| 阶段 | 代码文件 | 布局文件 |
|------|---------|---------|
| 启动页 | `app/src/main/java/org/autojs/autojs/ui/splash/SplashActivity.kt` | `app/src/main/res/layout/activity_splash.xml` |
| 抢购页 | `app/src/main/java/org/autojs/autojs/ui/snipe/SnipeActivity.kt` | `app/src/main/res/layout/activity_snipe.xml` |
| 主界面 | `app/src/main/java/org/autojs/autojs/ui/main/MainActivity.kt` | `app/src/main/res/layout/activity_main.xml` |

### 主界面布局

```
┌────────────────────────────────────┐
│ 状态栏                              │  ← 系统
├────────────────────────────────────┤
│ ☰  AutoJs6           🔍  📋       │  ← Toolbar
├────────────────────────────────────┤
│  文件  │  文档  │  插件  │  任务   │  ← TabLayout
├────────────────────────────────────┤
│                                    │
│        ViewPager 内容区             │  ← 默认显示"文件"Tab
│                                    │
│                              [+]   │  ← FAB 悬浮按钮
└────────────────────────────────────┘
```

### Toolbar（标题栏）

| 功能 | 代码位置 |
|------|---------|
| Toolbar 初始化与配色 | `app/src/main/java/org/autojs/autojs/ui/main/MainActivity.kt` → `setUpToolbar()` |
| 侧边抽屉开关（☰） | 同上，`ActionBarDrawerToggle` |
| 标题"AutoJs6"（长按进入设置） | 同上，`setOnTitleViewLongClickListener` |
| 搜索按钮 | 同上，`setUpSearchMenuItem()` |
| 日志按钮 | 同上，`onOptionsItemSelected()` → `LogActivity` |
| 菜单定义 | `app/src/main/res/menu/menu_main.xml` |

### Tab 栏与 ViewPager

| Tab | Fragment | 代码文件 |
|-----|----------|---------|
| 文件 | ExplorerFragment | `app/src/main/java/org/autojs/autojs/ui/main/scripts/ExplorerFragment.kt` |
| 文档 | DocumentationFragment | `app/src/main/java/org/autojs/autojs/ui/doc/DocumentationFragment.kt` |
| 插件 | PluginFragment | `app/src/main/java/org/autojs/autojs/ui/main/plugin/PluginFragment.kt` |
| 任务 | TaskManagerFragment | `app/src/main/java/org/autojs/autojs/ui/main/task/TaskManagerFragment.kt` |

Tab 配置代码：`MainActivity.kt` → `setUpTabViewPager()`

### 文件 Tab（默认页）

| 功能 | 代码文件 |
|------|---------|
| 文件浏览器视图 | `app/src/main/java/org/autojs/autojs/ui/explorer/ExplorerView.kt` |
| 文件浏览器辅助类 | `app/src/main/java/org/autojs/autojs/ui/explorer/ExplorerViewHelper.kt` |
| Fragment 布局 | `app/src/main/res/layout/fragment_explorer.xml` |

### FAB 悬浮按钮（右下角 "+"）

| 功能 | 代码文件 |
|------|---------|
| FAB 基础行为（滚动隐藏/显示） | `app/src/main/java/org/autojs/autojs/ui/main/MainActivity.kt` |
| 文件 Tab 展开菜单（新建文件夹/文件/导入/项目） | `app/src/main/java/org/autojs/autojs/ui/main/FloatingActionMenu.java` |
| 插件 Tab 展开菜单（本地安装/URL安装） | `app/src/main/java/org/autojs/autojs/ui/main/plugin/PluginFloatingActionMenu.java` |
| FAB 抽象基类 | `app/src/main/java/org/autojs/autojs/ui/main/ViewPagerFragment.kt` |

### 侧边抽屉（左滑打开）

| 功能 | 代码文件 |
|------|---------|
| 抽屉 Fragment | `app/src/main/java/org/autojs/autojs/ui/main/drawer/DrawerFragment.kt` |
| 抽屉布局 | `app/src/main/res/layout/fragment_drawer.xml` |
| 抽屉菜单适配器 | `app/src/main/java/org/autojs/autojs/ui/main/drawer/DrawerMenuAdapter.java` |
| 菜单分组布局 | `app/src/main/res/layout/drawer_menu_group.xml` |
| 菜单条目布局 | `app/src/main/res/layout/drawer_menu_item.xml` |

#### 抽屉菜单结构

```
┌──────────────────────┐
│  服务                │ ← 分组头
│    无障碍服务    [○]  │ ← 开关项
│    前台服务      [○]  │
│  工具                │
│    悬浮窗        [○]  │
│    指针位置      [○]  │
│  连接电脑            │
│    客户端模式    [○]  │
│    服务端模式    [○]  │
│  权限                │
│    通知权限      [○]  │
│    通知监听      [○]  │
│    所有文件访问  [○]  │
│    使用情况统计  [○]  │
│    忽略电池优化  [○]  │
│    悬浮窗权限    [○]  │
│    小米/OPPO等   [○]  │ ← 品牌相关，动态显示
│    写入系统设置  [○]  │
│    写入安全设置  [○]  │
│    媒体投影      [○]  │
│    Shizuku       [○]  │
│  外观                │
│    自动夜间模式  [○]  │
│    夜间模式      [○]  │
│    屏幕常亮      [○]  │
│    主题色        →   │ ← 点击进入颜色选择
│  文件                │
│    回收站        →   │ ← 显示数量/大小
│    版本历史      →   │ ← 显示数量/大小
│  关于                │
│    关于应用      →   │ ← 显示版本号
├──────────────────────┤
│ ⚙设置  🧩插件  🔄重启  ⏻退出 │ ← 底部固定按钮
└──────────────────────┘
```

### 其他关键页面

| 页面 | 代码文件 |
|------|---------|
| 日志页面 | `app/src/main/java/org/autojs/autojs/ui/log/LogActivity.kt` |
| 设置页面 | `app/src/main/java/org/autojs/autojs/ui/settings/PreferencesActivity.kt` |
| 关于页面 | `app/src/main/java/org/autojs/autojs/ui/settings/AboutActivity.kt` |
| 开发者选项 | `app/src/main/java/org/autojs/autojs/ui/settings/DeveloperOptionsActivity.kt` |
| 脚本编辑器 | `app/src/main/java/org/autojs/autojs/ui/edit/EditActivity.kt` |
| APK 打包 | `app/src/main/java/org/autojs/autojs/ui/project/BuildActivity.kt` |
| 回收站 | `app/src/main/java/org/autojs/autojs/ui/storage/TrashActivity.kt` |
| 版本历史 | `app/src/main/java/org/autojs/autojs/ui/storage/VersionHistoryActivity.kt` |
| 颜色选择 | `app/src/main/java/org/autojs/autojs/theme/app/ColorSelectActivity.kt` |
| 定时任务 | `app/src/main/java/org/autojs/autojs/ui/timing/TimedTaskSettingActivity.kt` |
| 崩溃报告 | `app/src/main/java/org/autojs/autojs/ui/error/CrashReportActivity.kt` |

### 核心服务与工具

| 功能 | 代码文件 |
|------|---------|
| 无障碍服务 | `app/src/main/java/org/autojs/autojs/core/accessibility/AccessibilityServiceUsher.kt` |
| 屏幕截图 | `app/src/main/java/org/autojs/autojs/core/image/capture/ScreenCapturerForegroundService.kt` |
| 前台服务 | `app/src/main/java/org/autojs/autojs/external/foreground/AppForegroundService.kt` |
| 悬浮窗管理 | `app/src/main/java/org/autojs/autojs/ui/floating/FloatyWindowManger.kt` |
| 脚本执行 | `app/src/main/java/org/autojs/autojs/execution/ScriptExecuteActivity.kt` |
| 定时任务接收器 | `app/src/main/java/org/autojs/autojs/timing/TaskReceiver.kt` |
| 开机启动接收器 | `app/src/main/java/org/autojs/autojs/timing/BootCompletedReceiver.kt` |
| 通知监听服务 | `app/src/main/java/org/autojs/autojs/core/notification/NotificationListenerService.kt` |
| 桌面小部件 | `app/src/main/java/org/autojs/autojs/external/widget/ScriptWidget.kt` |
| 更新检查 | `app/src/main/java/org/autojs/autojs/util/UpdateUtils.kt` |

### 构建与签名

| 功能 | 代码文件 |
|------|---------|
| 应用构建配置 | `app/build.gradle.kts` |
| 签名插件 | `build-logic/convention/src/main/kotlin/org/autojs/build/SignsPlugin.kt` |
| 签名工具类 | `build-logic/convention/src/main/kotlin/org/autojs/build/Signs.kt` |
| 版本管理 | `build-logic/convention/src/main/kotlin/org/autojs/build/Versions.kt` |
| 构建工具 | `build-logic/convention/src/main/kotlin/org/autojs/build/Utils.kt` |
| CI 工作流 | `.github/workflows/android.yml` |

### 项目目录结构

```
app/src/main/java/org/autojs/autojs/
├── App.kt                          # Application 入口
├── core/                           # 核心功能
│   ├── accessibility/              # 无障碍服务
│   ├── image/                      # 图像与截图
│   ├── notification/               # 通知监听
│   ├── permission/                 # 权限请求
│   ├── plugin/                     # 插件中心
│   └── activity/                   # 通用 Activity
├── execution/                      # 脚本执行
├── external/                       # 外部接口
│   ├── foreground/                 # 前台服务
│   ├── open/                       # 外部打开脚本
│   ├── shortcut/                   # 快捷方式
│   ├── tasker/                     # Tasker 集成
│   ├── tile/                       # 快速设置磁贴
│   └── widget/                     # 桌面小部件
├── inrt/                           # 打包运行时 (inrt flavor)
├── timing/                         # 定时任务
├── theme/                          # 主题与颜色
├── ui/                             # 界面
│   ├── splash/                     # 启动页
│   ├── main/                       # 主界面
│   │   ├── drawer/                 # 侧边抽屉
│   │   ├── scripts/                # 文件 Tab
│   │   ├── plugin/                 # 插件 Tab
│   │   └── task/                   # 任务 Tab
│   ├── edit/                       # 脚本编辑器
│   ├── doc/                        # 文档页面
│   ├── explorer/                   # 文件浏览器
│   ├── floating/                   # 悬浮窗
│   ├── log/                        # 日志页面
│   ├── settings/                   # 设置页面
│   ├── project/                    # 项目/APK 打包
│   ├── storage/                    # 回收站/版本历史
│   ├── error/                      # 崩溃报告
│   └── widget/                     # 自定义控件
├── model/                          # 数据模型
└── util/                           # 工具类
```