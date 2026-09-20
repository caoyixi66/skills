# Mino1 Recovery 下载安全信息缺少 3rd.pk

状态：已确认  
适用范围：Recovery CDC 传输成功后的第三方公钥落盘与业务校验失败  
创建日期：2026-08-05

## 问题摘要

| 字段 | 内容 |
|---|---|
| 现象 | Recovery 的 Download SecurityInfo 页面在 CDC 已打开、且已观察到 SP 交互 `ret=0` 后仍以 `Process Aborted` 结束。 |
| 首个决定性错误 | `spi_dev_get_pk_api ... /private/cert/3rd.pk` 后出现 `stat fail, ret:-1`。 |
| 已确认原因 | 该次失败中，第三方 PK 目标 `/private/cert/3rd.pk` 缺失或未成功完成落盘；后续第三方 hash/FQJ 业务校验因此失败。 |
| 未确认部分 | 日志与开源侧源码不能证明 host 下载包、私有认证链、`libcert_bin` 内部、SP 固件或 FQJ 私有格式中究竟哪一环首先导致未落盘。 |
| 安全处置边界 | 不通过临时伪造、替换或公开认证材料来绕过校验；优先检查已授权下载流程是否实际执行了第三方 PK 写入和处理。 |

## 证据链

| 顺序 | 事实或日志 | 结论边界 | 证据位置 |
|---|---|---|---|
| 1 | CDC 已打开，日志中的部分 SP 交互返回 `ret=0`。 | 传输层至少在该阶段可工作；不代表整项业务成功。 | 2026-07-10 `/tmp/recovery.log` / `last_log` 已保存片段。 |
| 2 | `spi_dev_get_pk_api` 访问 `/private/cert/3rd.pk` 时出现 `stat fail, ret:-1`。 | 这是日志中首个稳定、与后续业务失败直接相连的功能错误。 | Recovery 日志；`A12/bootable/recovery/xgdrecovery/spidev/spi_ddi.c` 的 `spi_dev_get_pk_api()`。 |
| 3 | 随后记录第三方 hash 异常、FQJ 构造失败、`inner_active_deal_load_fqj ... ret=-1` 和 `Process Aborted`。 | 该顺序支持文件缺失/未落盘导致后续业务失败；不把 FQJ 的私有语义解释为已知。 | 同一 Recovery 日志时序。 |
| 4 | `unity_accord_write_3rd_cert()` 先写 `/private/3rd.pk`，目标路径为 `/private/cert/3rd.pk`；处理程序路径为 `/private/cert/libcert_bin`。 | 源码证明预期的落盘链路；不证明该次运行曾成功执行该流程。 | `unityaccord_interface/unity_accord_function.cpp`、`install.cpp`。 |

## 验证与回归

| 验证项 | 结果 | 状态 | 重新验证条件 |
|---|---|---|---|
| 保存 Recovery 日志并定位首个错误 | 已确认本案例应优先检查 `/tmp/recovery.log`、`/cache/recovery/last_log`、`/cache/recovery/last_kmsg`，而非先归因于 CDC 枚举。 | 已确认 | Recovery 日志格式、路径或统一协议版本变化后重新确认。 |
| 检查第三方 PK 落盘链路 | 应在经授权的正常流程中确认 `/private/3rd.pk` 写入、`libcert_bin` 处理及 `/private/cert/3rd.pk` 结果；缺失任一阶段时继续向 host 包/下载流程或私有认证路径排查。 | 部分确认 | 需要同一版本的运行日志和经过批准的现场验证；不记录或传播认证材料。 |
| CDC/USB 修复是否足够 | 不足以单独证明业务修复。 | 已确认 | 每次更换 Recovery、统一协议库、SP 固件、下载包或证书流程后重新验证。 |
