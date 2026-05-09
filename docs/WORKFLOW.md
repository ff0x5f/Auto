# 工作流程

## 项目信息

- **仓库**: [ff0x5f/Auto](https://github.com/ff0x5f/Auto)
- **分支**: dev
- **App ID**: `org.autojs.auto6`
- **Workflow**: [Android CI (Fast Build)](https://github.com/ff0x5f/Auto/actions)

## 开发流程

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   本地 Coding   │ ──▶ │  git commit&push │ ──▶ │  GitHub Actions │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │   自动编译 ARM   │
                                              └─────────────────┘
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │  产出 APK 工件   │
                                              └─────────────────┘
```

## 操作命令

### 查看 Workflow 状态
```bash
gh run list --limit 3
```

### 查看详细日志
```bash
gh run view <run-id> --log
```

### 检查构建是否成功
```bash
# 查找关键信息
gh run view <run-id> --log | grep -E "(BUILD SUCCESS|error:|Artifact.*arm64)"

# 下载 APK
gh run view <run-id> --log | grep "Artifact download URL"
```

## 状态说明

| 状态 | 含义 |
|------|------|
| `in_progress` | 构建中 (~3分钟) |
| `completed success` | 成功，APK已上传 |
| `completed failure` | 失败，需查看日志修复 |

## 修复记录

详见 [CI_BUILD_FIXES.md](./CI_BUILD_FIXES.md)