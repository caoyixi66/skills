# N6P Recovery 与 OTA

建档状态：部分确认  
适用工作区：`V:\new_ssd1\workspace\android\n6p`  
最后验证：2026-08-08

本专题只记录 Recovery 对升级包的执行边界。横跨 Android 服务、`ttyS1`、固件文件、升级 App 与 Recovery 的 M1 能力见 `功能模块/M1扫码与固件升级.md`。

## 已确认传统 ZIP 执行边界

| 项目 | 已确认事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| 传统 ZIP 执行路径 | `A12/bootable/recovery/install/install.cpp` 的 `SetUpNonAbUpdateCommands()` 从 ZIP 提取 `META-INF/com/google/android/update-binary` 并执行它。 | 已确认 | 当前 N6P Recovery 源码，2026-08-03。实际包类型变化时同时检查 ZIP metadata 与脚本。 |
| 私有 edify 注册 | `A12/bootable/recovery/xgdrecovery/install.cpp` 的 `xgd_RegisterFunction()` 注册既有 `McuUpgrade` 与新增 `M1Upgrade`。 | 已确认（源码） | 当前 N6P Recovery 源码工作区，2026-08-03；`M1Upgrade` 尚未编译或真机执行。 |
| M1 包集成边界 | 若 M1 包调用新增或扩展的私有 edify 行为，该行为必须编译进该包携带的 `update-binary`；仅修改父 Recovery 安装器不能改变旧包内二进制支持的函数集合。 | 已确认 | 由上述“提取后 exec 包内 binary”与函数注册源码共同确定，2026-08-03。 |

## M1 OTA 接入

当前工作区的 `M1Upgrade` 实现位于 `A12/bootable/recovery/xgdrecovery/install.cpp`，没有新增独立的 M1 C++ 文件。`A12/bootable/recovery/updater/Android.mk` 的 `updater` 静态可执行模块链接 `libxgdinstall`，而 `updater_main.cpp` 启动时调用 `xgd_RegisterFunction()`；因此新函数最终必须进入 OTA 携带的 `update-binary`。

M1 OTA 必须同时满足以下两项：

```edify
assert(package_extract_dir("m1", "/tmp/m1"));
assert(M1Upgrade("/tmp/m1/m1_upgrade.ini"));
```

1. 解出的 `m1/` 目录含 `m1_upgrade.ini` 和清单中引用的完整 Master、Slave、reset 文件。
2. 包内 `META-INF/com/google/android/update-binary` 来自包含此源码、重新编译的 `updater` 模块。

只在旧 OTA 的 `updater-script` 中加入 `M1Upgrade(...)` 会因旧 `update-binary` 未注册函数而失败；仅重新构建 Recovery 也不会使已签名的旧 OTA 自动获得该函数。

### 测试产物边界

对于当前这一次只修改 `xgdrecovery/install.cpp` 的接入，第一轮功能验证必须制作一个专用 M1 OTA：它至少携带新编译的 `update-binary`、最小 `updater-script`、`m1/m1_upgrade.ini` 和对应固件文件，并且必须通过设备上 Recovery 的包验证。

`recovery.img` 不是让 `M1Upgrade` 出现在 OTA 中的必要产物，因为传统 Recovery 会从 ZIP 提取并执行包内的 `update-binary`。只有真机证实当前 Recovery 缺少 `/dev/ttyS1`、DDI GPIO 支持或 `updater` 域的 SELinux 权限，才需要基于决定性日志修改并重新刷入 `recovery.img`。本轮尚未获得这类设备证据。

N6P 脚本 `A12/vendor/nexgo/build/xgd_tools/xgd_build.n6pro.64.sh` 已确认 vendor lunch 为 `vnd_n6pro_k62v1_64_bsp-userdebug`，其 Recovery 构建调用 `make recoveryimage -j24`；完整系统 OTA 构建由 A13 的 split-build 工具加 `--otapackage` 完成。

2026-08-03 已实际执行 `make updater -j24` 和 `make recoveryimage -j24` 并均成功。`updater` 输出为 `A12/out/target/product/n6pro_k62v1_64_bsp/system/bin/updater`，`recovery.img` 输出为 `A12/out/target/product/n6pro_k62v1_64_bsp/recovery.img`。

专用 M1 OTA 已按最小目录结构打为 `N6P_M1_V2.4.70.0.0_OTA_UNSIGNED.zip`，其中 `META-INF/com/google/android/update-binary` 是新编译的 `updater`，且 ZIP 内保持 Unix `0755`。当前 Recovery 的 `otacerts.zip` 信任 ECC 证书；现有工作区没有匹配私钥，因此包按公司流程保持未签名，必须在物理签名机完成签名后才可给设备安装。不得在签名后修改 ZIP 内容。

## `/private/config` 兼容保护

适用范围：N6P 当前非 A/B 传统 ZIP OTA，Recovery 源码位于 `A12/bootable/recovery`。2026-08-08 分支 `cyx-n6p-protect-config` 已确认的改动在 `install/install.cpp`、`install/include/install/install.h`、`recovery_main.cpp`；不修改历史 OTA 的 `update-binary` 或 `updater-script`。

### 生效规则和恢复策略

1. Recovery 读取 ZIP 内 `META-INF/com/google/android/updater-script`。只有脚本直接包含 `delete("/private/config")`、带尾部斜杠的等价形式，或对应的 `delete_recursive(...)` 时才启用保护。
2. 对启用保护的包，Recovery 扫描 `delete(...)` 中的字面量路径。`/private/config/<顶层名称>.cfg` 被显式删除时，该顶层 `.cfg` 不备份、不恢复；其他 `/private/config` 顶层文件、普通 `.cfg`、目录和目录内容均受保护。解析器支持一个 `delete(...)` 调用内的多个字面量参数，但不应把变量、拼接表达式或其他 edify 函数推断为删除规则。
3. 受保护总大小不超过 50 MiB 时，先 `rename()` 到 `/private/.ota_private_config_keep`；大于 50 MiB 时，先复制到 `/data/misc/recovery/.ota_private_config_keep`，以 `/private/.ota_private_config_keep_data` 作为 data 备份 marker，全部复制并 `syncfs()` 后才删除原条目。
4. 原 OTA 的 `update-binary` 退出后立即恢复；Recovery 启动时也会恢复遗留备份。目标路径已被 OTA 创建时，OTA 内容优先，旧备份条目被丢弃。恢复过至少一个条目后，通过 `sys.xgd.private_config_relabel=1` 请求 Recovery init 执行 `restorecon_recursive /private/config`，完成后 init 将属性置回 `0`。

`/data` 路径不是 fallback：当 `/data` 无法挂载、残留 data 备份或 marker、无法查询空间、空间小于“待保护大小 + 1 MiB”，或者 marker/复制/同步失败时，`PreparePrivateConfigProtection()` 返回失败。OTA 的 `update-binary` 不会启动，日志记录 `error: private_config_protect`，不会退回到 `/private` 内备份而冒分区空间风险。复制过程失败时，原条目尚未删除，Recovery 会尝试清理半成品和 marker；清理仍失败则保留遗留状态，等待下次 Recovery 启动继续处理。

`syncfs()` 只是在 marker 写入和 data 备份完成后的落盘请求，不等同于真实断电持久性证明；真实断电仍需在目标设备上单独验证。

### 已执行的验证

测试目录为 `D:\xgd\n6p\cyx-n6p-protect-config`。`prepare-private-config-protection-test.bat` 写入带时间戳的 `cyx_*` 测试条目和预期状态；`check-private-config-protection-test.bat` 读取最新状态文件，检查文件内容、显式删除例外、备份清理和 Recovery 日志。检查脚本不重新解析 sideload 的 ZIP，准备参数必须与实际包的脚本组合一致。

| 场景 | 准备参数与包脚本 | 已验证预期 |
|---|---|---|
| 两个显式删除 | 默认 `recursive-hidelist-settings`，递归删除 `/private/config` 后删除 `hidelist.cfg`、`settings_appshidelist.cfg` | 其他文件、普通 `.cfg`、目录保留；两个点名 `.cfg` 不存在。 |
| 无显式删除 | `recursive-only`，只有 `delete_recursive("/private/config")` | 所有测试条目，包括两个命名 `.cfg`，均保留；日志显示跳过 0 个显式删除 `.cfg`。 |
| 一个显式删除 | `recursive-hidelist`，递归删除加 `delete("/private/config/hidelist.cfg")` | `hidelist.cfg` 不存在，`settings_appshidelist.cfg` 和其他测试条目保留；日志显示跳过 1 个。 |
| 大于 50 MiB | 在上述递归删除场景加 `over-50m`，创建 51 MiB 测试文件 | 日志出现 `using /data`；文件恢复，`/private`、`/data/misc/recovery` 备份目录及 marker 均清理。 |

脚本 `verify-private-config-recovery-edge-cases.bat` 不 sideload OTA，而是在 Recovery 中构造遗留状态并重启：

- `data-marker`：原文件仍在 `/private/config`，`/data` 中只有内容不同的半成品副本和 marker，模拟 data 复制尚未完成即重启。启动恢复应保留原文件、丢弃 data 半成品并清理 marker。
- `directory-conflict`：`/private/config` 中存在视为 OTA 创建的目录，同时 `/private/.ota_private_config_keep` 有同名旧备份目录。启动恢复应保留 OTA 目录，递归删除整个旧备份目录，而不是只删除其内容后留下空目录。

2026-08-07 的设备输出已通过正常小数据、51 MiB `/data` 路径和上述两个边界脚本。每次 Recovery 源码、签名包或存储挂载策略变更后，需重新执行对应场景；未经重新刷入当前 `recovery.img` 的旧结果不能作为回归结论。

### 当前边界

- 仅覆盖当前传统 ZIP 的根目录 `delete`/`delete_recursive` 语义；`format`、原始分区写入、脚本调用外部程序、动态构造路径或其他私有 edify 行为需要针对实际 ZIP 重新评估。
- `/data` 是否可在目标 Recovery 下挂载、是否受 FBE 状态影响，必须由真机验证；当前代码检查挂载与空间，不以“可见 `/data`”替代真实恢复测试。
- 修改 ZIP 的 `updater-script` 后必须重新进行产品 ECC 签名；未经设备信任证书签名的变体包只能做离线结构检查，不能用于 sideload 验证。

## 最小取证与操作边界

Recovery 侧优先保留 `/tmp/recovery.log`、`/cache/recovery/last_log` 和 `/cache/recovery/last_kmsg`。

历史版本的 M1 函数曾额外输出 `M1UPG|phase=...` 日志，并每 128 条记录将阶段、记录号和错误写入 `/cache/recovery/m1_upgrade.state`；该描述仅适用于对应历史构建。2026-09-02 的目录驱动版本已移除 `peripheral_upgrade` 调试目录、`transaction_dir`、`m1_upgrade.state`、`m1_upgrade.trace` 以及 metrics/trace 调试逻辑，M1 固件校验、UART、BootLoader/命令模式、ACK、超时、Finish 和受控清理逻辑保留。后续若更换源码或 OTA，必须以当前包内 `update-binary` 和真机日志重新确认。

任何 sideload、重启、刷机、模块固件传输或断电测试都需要用户逐项确认。OTA 包类型、分区模式和实际 Recovery 执行结果仍需依据当前 ZIP、产品配置和真机日志重新验证。

### 2026-09-03 长时间 M1 OTA 挂测与 cache 清理回归

状态：已确认（特定 N6P Recovery/update-binary、V2.4.70 OTA、测试脚本和目标设备）。  
适用工作区：`V:\new_ssd1\workspace\android\n6p`；测试输出目录：`D:\xgd\n6p\cyx-n6p-support-upgrade-m1\self_test`。  
证据：最终汇总 `m1-sideload-total-result.md`，统计截止 2026-09-03 09:38:31；详细运行目录随后按用户要求清理。

统计规则是每个唯一 `attempt_dir` 计一次真实测试。旧版本脚本曾对同一目录追加重复的 `success`/`aborted` 行，不能按 CSV 原始行数直接计数。

| 项目 | 结果 |
|---|---:|
| 唯一测试记录 | 666 回 |
| 已完成 | 662 回 |
| 完成且成功 | 586 回 |
| 完成但失败 | 76 回 |
| 人工 Ctrl+C 中止 | 4 回 |
| `menu_sideload` | 341 回 |
| `reboot_sideload` | 325 回 |
| cache 清理 | 78 次，全部成功 |
| 保存的 `last_kmsg*` | 173 个，1,243,495,014 字节 |
| 清理后残留 `last_kmsg*` | 0 次 |
| 重启到系统再回 Recovery | 29 次，全部成功 |

最新连续运行中，199 回 OTA 全部成功，第 200 回在 `adb reboot sideload` 准备阶段被人工中止。历史 76 个完成失败记录中，65 个只由汇总字段确认 Recovery `install_status=1`，2 个为 `adb sideload` 非 0；其余发生在输入事件、Recovery 证据或等待阶段。没有汇总记录显示 `driver_success=0`。因此，删除详细日志后不能把全部 `install_status=1` 重新命名为 M1 协议失败；此前保留的部分失败日志曾明确显示 OTA 解压 `/cache/m1` 时 `No space left on device`，但该证据不能外推到所有失败记录。

本轮验证还确认：

1. 普通重启到 Android 不是通用 `/cache` 清理机制；可靠释放 `last_kmsg*` 依赖测试框架显式保存、删除和删除后复核。
2. `state.json` 可能落后于正在执行的回次；判断挂测是否结束必须同时检查挂测进程、`run.log` 尾部、`summary.csv` 和当前 attempt 是否存在 `result.json`。
3. 清理前必须先生成汇总报告；用户要求只保留报告时，不应在目标目录创建辅助清理脚本。

重新验证条件：Recovery、包内 `update-binary`、OTA、测试脚本、设备、日志阈值或清理策略任一变化后，必须重新执行挂测并保留至少一轮原始 `df`、`du`、Recovery 日志和清理结果；删除详细证据后只能引用预先生成的汇总报告。
