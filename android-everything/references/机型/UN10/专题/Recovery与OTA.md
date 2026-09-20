# UN10 Recovery 与 OTA

建档状态：部分确认  
适用工作区输入：`V:\new_ssd1\workspace\android\un10`

## 升级类型

| 项目 | 当前记录 | 状态 | 如何验证 |
|---|---|---|---|
| 分区模式 | 当前 `bengal_515` 源码默认 `ENABLE_AB=false`、`ENABLE_VIRTUAL_AB=false`；定义动态分区组与 non-A/B Recovery fstab 分支 | 部分确认 | 2026-08-03：`target/device/qcom/bengal_515/BoardConfig.mk`、`bengal_515.mk`。这是源码默认值；须以实际构建变量、设备分区表和启动属性确认产品实际模式。 |
| Recovery 启动 AVB 路径 | 2026-08-05 设备 ABL `logfs` 证明当前 Recovery 为“无 kernel、经 boot 启动”的路径；AVB2 常规路径读取顶层 `vbmeta`，再校验其中的 `recovery` hash descriptor。 | 已确认 | 适用于本次提取日志的设备与当前 ABL 行为；详见 `问题/UN10-02-Recovery启动AVB校验.md`。修改 ABL、Recovery header、A/B 配置或 AVB 规则后重验。 |
| Recovery 内嵌 VBMeta/footer 分支 | 仅在非 A/B、进入 Recovery、非 recovery-as-boot、且 Recovery 自带 kernel 时，ABL 才置 `AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION`，从 Recovery 的 `AVBf` footer 取内嵌 VBMeta。 | 已确认 | `VerifiedBoot.c:1502-1515`、`avb_slot_verify.c:1543-1589`。该条件不适用于本次 UN10 无 kernel Recovery。 |
| OTA 包类型 | 待验证 | 待验证 | 本轮未读取 OTA ZIP，不能据源码 wrapper 的 ZIP 文件名推断是 payload OTA、传统 Recovery OTA 或厂商私有流程。 |
| 升级主链路 | 待验证 | 待验证 | 2026-08-03：源码存在 `qssi14/system/update_engine` 子项目和 Recovery 源码项目，但未分析实际编译开关、安装入口或日志。 |
| 最小日志集合 | `/tmp/recovery.log`、`last_log`、`last_kmsg`、update_engine 日志 | 待验证 | 实际故障时保留同一时间窗口的日志与 OTA 包。 |

## 调查顺序

1. 先从实际 OTA 包识别 payload OTA、传统 Recovery OTA 或其他厂商流程。
2. 从升级日志中定位首个决定性失败，不把相邻 warning 当作根因。
3. 涉及分区、snapshot、COW 或 data 状态时，先确认当前交易状态和映射关系。
4. sideload、重启、清数据、刷机和 Recovery 复现都必须取得用户明确确认。
5. Recovery 启动失败先区分“Recovery 自带 kernel”与“Recovery 无 kernel、由 boot 提供 kernel”；随后确认 `NO_VBMETA_PARTITION` 是否实际置位，不得仅根据镜像尾部有 `AVBf` footer 推断校验来源。

## 重新验证条件

产品分区配置、OTA 生成流程、Recovery 或 update_engine 编译开关变化后，以当前 ZIP、源码和设备日志重新确认。
