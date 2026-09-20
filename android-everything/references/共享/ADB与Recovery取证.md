# ADB 与 Recovery 取证

## 连接原则

先执行只读检查，再判断是否存在受保护 ADB、正常 Android、Recovery 或 sideload 状态。

| 检查 | 目的 |
|---|---|
| `adb devices -l` | 识别设备数量、状态和产品信息 |
| `adb shell id` | 验证 shell 是否可用 |
| `adb root` 后 `adb wait-for-device` | 区分 adbd 重启与持续授权失败 |
| `getprop`、`ps`、`dmesg` | 确认当前模式和服务状态 |

若自定义授权链路导致 shell 关闭，只能使用经批准的本地工具；不得把认证命令、认证值、设备序列号或派生值写入 Skill。

## Recovery 证据优先级

| 文件 | 用途 |
|---|---|
| `/tmp/recovery.log` | 本次 Recovery 会话的直接日志 |
| `/cache/recovery/last_log` | 上一次保留的 Recovery 日志 |
| `/cache/recovery/last_kmsg` | Kernel/驱动层辅助证据 |

## sideload 判断

```text
Recovery 菜单
  -> minadbd 启动
  -> FunctionFS 就绪
  -> sys.usb.config=sideload
  -> USB gadget 绑定
  -> 主机显示 sideload 设备
  -> adb sideload <package>
```

`minadbd` 是 sideload 服务，不是可交互 shell。处于 sideload 状态时应使用主机侧 `adb sideload`，而不是继续尝试 `adb shell`。

## 风险边界

- 不为了查看历史日志而强制切换 `sys.usb.config=sideload`。
- 复现 sideload、重启、清数据、刷写前必须获得明确授权。
- `adb push` 成功不等于设备已真正加载新产物；后续仍要做版本、时间戳、日志或功能验证。
