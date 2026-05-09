# Auto.js 项目 CI 构建修复记录

## 项目背景

本项目是 Auto.js Android 自动化工具的源代码库，基于 GitHub: `ff0x5f/Auto` (dev 分支)。

主要技术栈：
- Kotlin 1.8.0-RC2 + Java 17
- Android Gradle Plugin
- Android SDK 33
- kapt (Kotlin 注解处理)
- Rhino JavaScript 引擎

## 修复历程

### 1. JAR 文件路径不匹配

**问题**：refactor 后 `build.gradle.kts` 中的 JAR 文件路径与实际文件名不一致。

**修复**：修正路径：
```kotlin
// 修改前 -> 修改后
com.android.dx-1.7.0.jar -> com-legacy-android-dx-1_7_0.jar
org.mozilla.rhino-1.7.15-snapshot.jar -> org-mozilla-rhino-2_0_0-SNAPSHOT.jar
android-plugin-client-sdk-for-locale-9.0.0.jar -> android-plugin-client-sdk-for-locale-9.0.0.aar
github-api-1.306.jar -> github-api-1_306.jar
```

**相关文件**：`app/build.gradle.kts`

---

### 2. Java 版本不兼容

**问题**：项目配置 `JAVA_VERSION=18`，但 CI 使用 JDK 17。

**修复**：`version.properties` 中 `JAVA_VERSION=18` → `JAVA_VERSION=17`

---

### 3. DisplayUtils 方法签名不匹配

**问题**：Java 代码调用 `DisplayUtils.pxToSp(context, px)` 和 `dpToPx(context, dp)` 时传递了 Context 参数，但 Kotlin 函数只接受 Float 参数。

**修复**：添加带 Context 参数的重载方法：
```kotlin
fun pxToSp(context: Context, px: Float): Float
fun dpToPx(context: Context, dp: Float): Float
```

**相关文件**：`app/src/main/java/org/autojs/autojs/util/DisplayUtils.kt`

---

### 4. Android dX 库缺失

**问题**：`AndroidClassLoader.java` 需要 `com.android.dx.command.dexer.Main`，但 libs 中只有 `com.legacy.android.dx`。

**修复**：
1. 添加 `com-android-dx-1_14.jar` 到依赖
2. 修改 `AndroidClassLoader.java` import 为 `com.legacy.android.dx.command.dexer.Main`

**相关文件**：
- `app/build.gradle.kts`
- `app/src/main/java/org/autojs/autojs/rhino/AndroidClassLoader.java`

---

### 5. Rhino 2.0.0 与源码冲突

**问题**：libs 中的 `org-mozilla-rhino-2_0_0-SNAPSHOT.jar` 包含的类与项目源码冲突：
- `TokenStream` 不是 public 的，无法从外部包访问
- `Dim.java` 使用 Rhino 1.7 API (`ObjArray`, `ObjToIntMap`)

**修复**：
1. 从 git 历史恢复 `TokenStream.java` 和 `Dim.java`（来自 commit 086229da）
2. 更新相关文件的 import 语句：
   - `Dim` → `org.autojs.autojs.rhino.debug.Dim`
   - `TokenStream` → `org.autojs.autojs.rhino.TokenStream`

**相关文件**：
- `app/src/main/java/org/autojs/autojs/rhino/TokenStream.java`
- `app/src/main/java/org/autojs/autojs/rhino/debug/Dim.java`
- `app/src/main/java/org/autojs/autojs/rhino/debug/Debugger.java`
- `app/src/main/java/org/autojs/autojs/rhino/debug/DebugCallback.java`
- `app/src/main/java/org/autojs/autojs/rhino/debug/DebugCallbackInternal.java`
- `app/src/main/java/org/autojs/autojs/ui/edit/toolbar/DebugToolbarFragment.java`
- `app/src/main/java/org/autojs/autojs/script/JavaScriptSource.java`
- `app/src/main/java/org/autojs/autojs/ui/edit/editor/JavaScriptHighlighter.java`

---

### 6. Dim.java API 兼容性问题

**问题**：Dim.java 中 `attachTo(ScriptEngineService, ContextFactory)` 方法与当前 `ScriptEngineService` API 不匹配，缺少参数化版本的 `attachTo(ContextFactory)`。

**修复**：添加桥接方法：
```java
public void attachTo(ContextFactory factory) {
    // No-op when there's no ScriptEngineService
}
```

**相关文件**：`app/src/main/java/org/autojs/autojs/rhino/debug/Dim.java`

---

### 7. 其他已移除的依赖

**移除的文件**：
- `TinySign.java` - 依赖不可用的 APK builder (`com.stardust.autojs.apkbuilder.util.StreamUtils`)
- `RootShell` 和 `APK Builder` 依赖 - 已从 build.gradle.kts 移除

---

## 关键教训

1. **JAR 版本匹配**：libs 目录的 JAR 文件必须与项目源码中使用的 API 版本完全匹配
2. **Git 历史恢复**：删除的文件可以从 git 历史中恢复（`git show <commit>:<path>`）
3. **Rhino 版本差异**：Rhino 1.7.x 和 2.0.x 的 API 有显著差异，不能混用
4. **Context 参数传递**：Kotlin/Java 互操作时注意方法签名的差异

## 待解决问题

1. **AccessibilityService 警告**：`ApplicationAccessibilityService` 在 AndroidManifest.xml 中声明但未在编译路径中找到（可能是预期行为，需确认）
2. **TinySign.java**：如果后续需要签名功能，需要找到替代方案或恢复 APK builder

## 相关 Commits

| Commit | 描述 |
|--------|------|
| c9d2509b | patch Dim.java for compatibility |
| 8b5448f9 | restore TokenStream.java and Dim.java |
| 0a7a42de | update imports for Rhino 2.0.0 |
| b398a5eb | address Rhino 2.0 compatibility issues |
| 3b626d84 | add com-android-dx-1_14.jar and fix Main import |
| 23a48302 | add Context parameter overloads for pxToSp and dpToPx |
| 66ab0a5e | change Java version from 18 to 17 |
