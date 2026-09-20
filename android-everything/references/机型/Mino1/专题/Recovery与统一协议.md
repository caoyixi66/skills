# Mino1 Recovery 与统一协议

状态：部分确认  
适用范围：Recovery 菜单、xgdcmd、统一协议界面与 ADB 跳转  
创建日期：2026-08-04

## 资料边界

| 项目 | 内容 |
|---|---|
| 本专题回答的问题 | Recovery 的 `xgdcmd` socket 跳转、统一协议页面退出跳转、以及 ADB sideload 菜单链路 |
| 不覆盖的范围 | SP 固件内部协议语义、认证材料、实际 OTA 包兼容性、设备端运行结果 |
| 证据来源 | 2026-08-04 对 Mino1 A12 Recovery 的 Git 与源码只读检查 |

## 已确认事实

| 方向 | 事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| `c66b59b` 基线 | 当前 Recovery 分支 `cyx-mino1-auto-security-2` 的 HEAD 为 `c66b59b338ac5a5ac1f77fa7ec8c19a7684be0be`，提交修改 `recovery.cpp` 与 `xgdrecovery/xgd_recovery.cpp` | 已确认 | 2026-08-04 `git log -1`、`git show --stat --name-only`；换分支或 rebase 后重新检查 |
| socket 命令格式 | Recovery socket 处理单字符原生命令 `f`、`r`，以及前缀为 `xgdcmd:` 的扩展目标名 | 已确认 | `xgdrecovery/xgd_recovery.cpp` 的 `xgd_recovery_handle_socket_message()`；需与 adbd 侧实际发送格式共同验证 |
| 已映射的扩展目标 | 当前仅映射 `security-info`、`secure-unlock`、`download-secure-info`、`download-hwc`、`clear-data` | 已确认 | `xgd_recovery_jump_name_to_action()`；未知目标记录 warning 并不创建 pending action |
| 统一协议页内跳转 | `c66b59b` 增加 `g_xgd_in_unity_accord`；统一协议循环在发现 pending jump 时退出，再由主菜单循环消费该 action | 已确认 | `git show c66b59b` 与 `unity_accord_process()`、`xgd_prompt_and_wait()`；未覆盖设备并发时序 |
| `sideload` 的 c66 基线状态 | `xgdcmd:sideload` 在 `c66b59b` 映射表中不存在，因此会走 unknown-command 路径 | 已确认 | 2026-08-04 当前基线源码中目标名映射的完整列表；该事实适用于 c66 基线而非下述工作树 |
| ADB sideload 既有菜单链路 | `APPLY_ADB_SIDELOAD` 由 `apply_from_device()` 调用 `ApplyFromAdb(device, false, ...)` | 已确认 | `xgdrecovery/xgd_recovery.cpp`、`xgdrecovery/apply_install.cpp`；未代表 sideload 包安装必然成功 |

## Download SecurityInfo 故障边界

| 方向 | 已确认事实 | 证据与边界 |
|---|---|---|
| 传输与业务应分层判断 | 已观察到 CDC 打开、SP 交互返回 `ret=0` 后，后续仍会进入业务失败链，因此 CDC 枚举或一次 SP 成功响应不能证明“下载安全信息”成功 | 2026-07-10 Recovery 日志；详见 `问题/Recovery下载安全信息缺少3rdpk.md` |
| 决定性文件读取 | `unity_accord_dev_get_pk_api()` 调用 `spi_dev_get_pk_api()`；该 API 读取的目标名可落到 `/private/cert/3rd.pk` | `unityaccord_interface/unity_accord_function.cpp`、`spidev/spi_ddi.c`；私有 SP 通信实现不在本资料范围 |
| 证书落盘链路 | `unity_accord_write_3rd_cert()` 先写 `/private/3rd.pk`，再以 `/private/cert/libcert_bin` 处理，目标为 `/private/cert/3rd.pk` | Recovery 源码；不据此推断证书格式或加密语义 |
| 已观察失败链 | `/private/cert/3rd.pk` 的 `stat fail, ret:-1` 后出现第三方 hash 异常、FQJ 构造失败、`inner_active_deal_load_fqj ... ret=-1` 与 `Process Aborted` | 日志与源码时序共同支持“第三方 PK 缺失或未成功落盘”为首个业务失败点；不证明 host、SP 或私有认证链中具体哪一环首先遗漏 |

排查时先保存 `/tmp/recovery.log`、`/cache/recovery/last_log` 与 `/cache/recovery/last_kmsg`，按“CDC 已打开 -> SP 是否成功交互 -> `/private/cert/3rd.pk` 是否产生 -> 后续业务校验”的顺序定位。不得将认证材料、认证命令或设备身份数据写入资料。

## 调查与验证

1. 先确认当前源码工作区、产品配置、包或设备状态。
2. 从首个决定性错误或完整调用链开始，区分源码行为、日志事实和剩余假设。
3. 涉及刷机、重启、sideload、清数据或硬件操作时，明确标注需要用户确认的动作。

## 本次需求的最小源码方案

```text
adb shell xgdcmd sideload
  -> Recovery socket 收到 xgdcmd:sideload
  -> 新增一个 XGD_ADB_RECOVERY_SIDELOAD action
  -> 目标名映射返回该 action
  -> pending jump 退出统一协议循环
  -> xgd_run_adb_recovery_action()
  -> timeout_exit_stop()
  -> apply_from_device(device, APPLY_ADB_SIDELOAD)
  -> ApplyFromAdb() 进入既有 sideload 流程
  -> timeout_exit_start()
```

## 实施与构建验证

| 项目 | 结果 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| 最小源码改动 | 在 `XgdAdbRecoveryAction` 增加 `XGD_ADB_RECOVERY_SIDELOAD`；将 `"sideload"` 映射为该 action；在 action 分发中按菜单路径调用 `timeout_exit_stop()`、`apply_from_device(device, APPLY_ADB_SIDELOAD)`、`timeout_exit_start()` | 已确认 | 2026-08-04 工作树 diff；仅两文件、9 行新增 |
| 编译 | 在一次性 `ubuntu-18.04-cross-compiler:latest` 容器中执行 A12 `lunch vnd_AGN_H1504TQ_GO_XGD-userdebug && make recoveryimage -j16` 成功 | 已确认 | 日志结尾为 `[100% 698/698] ... recovery.img` 与 `build completed successfully (03:46)` |
| 产物 | `A12/out/target/product/AGN_H1504TQ_GO_XGD/recovery.img`，40 MiB，2026-08-04 20:43；SHA-256 为 `519f64066468d2548e4f067a575d4dd43b7109711a33e1680c0e57c2d8daa8fb` | 已确认 | `ls -l`、`file`、`sha256sum`；后续重编必须重新核验 |
| 设备验证 | 未刷写，未执行 `adb shell xgdcmd sideload`，未执行 `adb sideload` | 待验证 | 刷写/重启/传包均需要逐项确认；验证时同时观察统一协议页退出、sideload 枚举与返回主菜单 |

当前实现沿用已有 xgdcmd 的授权边界，没有额外接入菜单 `checkAction()`。这保持了与既有 xgdcmd action 一致的调用方式，但不等于该安全策略已经完成产品审批。
