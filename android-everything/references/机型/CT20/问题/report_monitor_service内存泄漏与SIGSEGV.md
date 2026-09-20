# CT20 report_monitor_service 失败路径内存泄漏与 SIGSEGV

状态：部分确认  
适用范围：CT20 2026-07-30 bugreport、debuglogger 与当前源码的 report 事件失败路径  
创建日期：2026-08-06

## 问题摘要

| 字段 | 内容 |
|---|---|
| 现象 | 2026-07-30 bugreport 的 `tombstone_00` 记录 PID 514 的 `/system/bin/report_monitor_service` 发生 SIGSEGV；同一包稍后捕获到 PID 2953 的该服务 RSS 为 433,260K，并记录 27 次 LMK kill |
| 首个决定性错误 | `signal 11 (SIGSEGV)`，`fault addr 0x4`；调用栈为 `netlink_send_nfc_report` -> `netlink_server_handler` -> `main` |
| 已确认原因 | `spi_ddi_get_report_event()` 失败分支调用 `netlink_send_nfc_report()`；该函数对 `malloc(NLMSG_SPACE(MAX_PAYLOAD))` 的结果直接 `memset()`，函数返回前没有 `free()` |
| 未确认部分 | SIGSEGV 是否由本次 `malloc()` 返回 NULL 直接造成、这条用户态泄漏在全系统内存压力中的占比、IRQ/DDI 失败根因、SPI/NFC 内核驱动是否另有泄漏 |
| 安全处置边界 | 当前页是证据和验证要求，不包含源码修改、构建、刷机、重启或设备操作；后续修复需以实际产物 BuildId 和同负载时间序列回归 |

## 证据链

| 顺序 | 事实或日志 | 结论边界 | 证据位置 |
|---|---|---|---|
| 1 | 原始目录存在主文本、`dumpstate_log.txt` 及 `FS/data/tombstones/tombstone_00` | 可确认这是系统级 bugreport 的离线证据，不是单一 app log | `D:\xgd\ct20\bugreport-full_aiv8175p2_bsp-RP1A.200720.011-2026-07-30-16-51-51` |
| 2 | tombstone：PID/TID 514，服务为 `/system/bin/report_monitor_service`，SIGSEGV/SEGV_MAPERR，fault addr `0x4` | 可确认 native 服务在该时刻崩溃 | `FS/data/tombstones/tombstone_00:6-8` |
| 3 | tombstone 栈：`netlink_send_nfc_report+56` -> `netlink_server_handler+130` -> `main+626` | 可将崩溃定位到 report 失败处理路径；不能从栈单独证明 malloc 返回值 | `tombstone_00:17-19`，主 bugreport 约第 10694-10696 行 |
| 4 | 源码：`malloc(NLMSG_SPACE(MAX_PAYLOAD))` 后立即 `memset(nlh_nfc_report, ...)`，发完 `sendmsg()` 直接返回 | 每次到达该函数都会遗漏该缓冲区；无 NULL 检查可使分配失败时转为崩溃风险 | `vendor/nexgo/system/ddiservice/report_monitor/report_monitor_service.c:235-265` |
| 5 | 源码：收到 `report` 后若 `spi_ddi_get_report_event()` 不为 `DDI_OK`，调用上述函数 | 已确认泄漏函数在 DDI 查询失败时可重复触发 | `report_monitor_service.c:566-590` |
| 6 | 后续快照：PID 2953 的 `report_monitor_service` 为 433,260K RSS；ActivityManager 记录 `Total number of kills: 27` | 可确认该事故包存在显著内存压力，且服务后来处于运行状态；不能仅凭此判定重启机制或全部泄漏来源 | 主 bugreport 约第 104294、119776 行 |
| 7 | 日志在 16:40:59 先出现 `DeadSystemException`，服务 PID 514 在 16:41:11 崩溃 | 只能确认两个事件的顺序；不能凭本包断言是 init 单独重启服务还是 runtime restart 后重新启动 | 主 bugreport 约第 10343、10586 行 |

## 验证与回归

| 验证项 | 结果 | 状态 | 重新验证条件 |
|---|---|---|---|
| 当前源码的失败路径内存所有权 | 分配点存在且同一函数无 `free()`；空指针检查缺失 | 已确认 | 代码路径、`MAX_PAYLOAD`、分配方式或所有权模型变更后重查 |
| tombstone 与源代码的对应 | 栈函数名对应失败路径；`fault addr 0x4` 与未检查 malloc 后的内存访问高度一致，但未记录 malloc 返回值 | 部分确认 | 用带符号的同 BuildId 二进制、分配失败日志或修复前后复现进一步确认 |
| 修复后的用户态内存趋势 | 本轮未执行修复或设备回归 | 待验证 | 固定 workload 下连续采集 PID、`smaps_rollup`、FD、DDI 失败次数和 report/IRQ 计数 |
| 内核泄漏排除 | 本轮未验证 | 待验证 | 查 `NETLINK_NFC=29`、`NETLINK_USER=31` 的内核接收路径，以及 slab/kmem 和驱动缓冲区时间序列 |
