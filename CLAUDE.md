# AutoJs6 项目说明

## 项目概述

AutoJs6 是一个 Android 自动化工具，支持 JavaScript 脚本编写和执行。

## 当前配置（Alt 版本）

此版本经过修改，可与原版 `org.autojs.autojs6` 同时安装。

### 关键配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| namespace | `org.autojs.autojs6` | 保持不变，R/BuildConfig 路径不变 |
| applicationId | `org.autojs.autojs6.alt` | 安装时的唯一标识 |
| FileProvider authorities | `org.autojs.autojs6.alt.fileprovider` | 避免与原版冲突 |
| 显示名称 | `AutoJs6 Alt` | 桌面图标下方显示的名称 |

### 恢复为原版

如需恢复为原版配置，修改以下位置：

1. `app/build.gradle.kts:29`
   ```kotlin
   val globalApplicationId = "org.autojs.autojs6"
   ```

2. `app/build.gradle.kts:459`
   ```kotlin
   namespace = globalApplicationId
   ```

3. `app/build.gradle.kts:505`
   ```kotlin
   "authorities" to "org.autojs.autojs6.fileprovider",
   ```

4. `app/src/main/res/values/strings.xml:16`
   ```xml
   <string name="app_name" translatable="false">AutoJs6</string>
   ```

## 构建项目

### 环境要求
- JDK 17+
- Android SDK (compileSdk 34)
- Gradle 8.x

### 构建命令

```bash
# Debug 版本
./gradlew assembleAppDebug

# Release 版本
./gradlew assembleAppRelease

# 构建 inrt 版本（打包脚本运行时）
./gradlew assembleInrtRelease
```

## 项目结构

```
├── app/                    # 主应用模块
├── build-logic/           # Gradle 构建逻辑
├── libs/                  # 第三方库
├── modules/               # 功能模块
└── plugin-api/            # 插件 API
```

## Product Flavors

项目包含两个 flavor：

| Flavor | ApplicationId | 用途 |
|--------|--------------|------|
| `app` | org.autojs.autojs6.alt | 完整版应用 |
| `inrt` | org.autojs.autojs6.alt.inrt | 打包脚本运行时 |

## 签名配置

签名密钥配置在 `app/signing.properties`（需自行创建）：

```properties
storeFile=path/to/keystore.jks
storePassword=xxx
keyAlias=xxx
keyPassword=xxx
```

## 常见任务

### 清理构建
```bash
./gradlew clean
```

### 同步 Gradle
```bash
./gradlew --refresh-dependencies
```

### 查看依赖树
```bash
./gradlew app:dependencies
```

## 注意事项

### 已处理的副作用
- **namespace**: 保持为 `org.autojs.autojs6`，代码中的 `import org.autojs.autojs6.R` 和 `import org.autojs.autojs6.BuildConfig` 无需修改
- **FileProvider**: authorities 已改为 `org.autojs.autojs6.alt.fileprovider`

### 未处理的副作用
以下组件使用原有标识符，如有需要请自行修改：
- 自定义权限 `org.autojs.permission.PLUGIN`
- Broadcast action `org.autojs.autojs.action.task`
- 各 Activity 的 taskAffinity（如 `org.autojs.autojs.edit`）

## 相关链接

- 项目主页: http://project.autojs6.com
- VSCode 扩展: http://vscext-project.autojs6.com
