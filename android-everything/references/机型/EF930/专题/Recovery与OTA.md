# EF930 Recovery 与 OTA

## 资料边界

本专题记录传统 Recovery OTA 的包执行边界、历史包兼容性，以及在 Recovery 场景中处理 VAB 遗留事务的受限规则。VAB 动态分区原理和目标槽映射分别见 `VAB动态分区.md`、`VAB目标槽映射.md`。

## 传统 Recovery 包检查

| 检查项 | 说明 |
|---|---|
| `META-INF/com/google/android/update-binary` | 确认是否使用传统 updater |
| `updater-script` | 查看 delete、format、`run_program` 和厂商扩展 |
| 签名与证书 | 修改历史包通常需要重新签名 |
| 分区操作 | 不能只看 `delete_recursive`，还要检查 format、raw 写入和覆盖 |

## 历史包兼容性

- 修改 Recovery 内的 updater 逻辑，只会影响包含新 updater 的未来包；不能自动改变已发布历史包的行为。
- 替换历史包、临时改 ZIP 或替换 `update-binary` 会影响签名验证和兼容性，必须逐包验证。
- “移动保护文件 -> 运行原始 updater -> 恢复”是兼容旧包的一种设计方向，但不能保证抵抗 format、原始块写入或整个分区替换。
- 每个历史包分别记录包类型、签名状态、脚本操作、真实测试结果、断连/中断覆盖范围和未验证场景。

## VAB payload sideload 的 stale `Initiated` 清理

状态：历史修复和 Recovery 日志已确认；最后核对日期：2026-08-03。该五文件补丁现已恢复到 `/home/new_ssd1/caoyixi/workspace/android/ef930_2` 的 `cyx-ef930-fix-update-error` 工作树，但仍未编译、暂存、提交或用该工作树重新刷机验证。历史设备 sideload 结果不能替代这次恢复后的构建和设备验证。

`D:\xgd\ef930\last_log` 的决定性链路为：

```text
Previous update has not been completed / Initiated
-> Verified correct signature / full payload 检查通过
-> Preparing partitions for new update，Completed 0/? operations
-> Cannot remove images backed by /data in recovery
-> Cannot begin new update
-> Unable to initialize partition metadata for slot B
-> kInstallDeviceOpenError (7)
```

这证明失败发生在 meaningful payload 写入前：旧 VAB 事务残留导致分区准备失败，不是该日志中的签名、payload offset、时间戳或增量基线根因。

| 受限清理条件 | 已确认行为 |
|---|---|
| 前置失败关闭 | `snapshot-boot` 存在时失败关闭 |
| 目标槽约束 | 所有 snapshot 名和 COW backing image 名必须属于目标槽 |
| 解除依赖 | `RemoveAllUpdateState()` 先按既有顺序解除 dm/COW 设备 |
| 临时授权 | 仅在上述检查通过期间短暂开启 `SetAllowDeleteInRecovery(true)`，删除 backing image 和 snapshot 状态 |
| 取消路径 | `CancelUpdate()` 不走深度清理，以保留当前 sideload re-flash fallback 所需 metadata |

当前 `snapshot_test.cpp` 改动覆盖 file-backed COW、目标槽清理成功和当前槽 COW image 使清理失败关闭的条件。历史设备 sideload 日志记录过受限清理后 `2074/2074`、`Update successfully applied`、`Install from ADB completed with status 0`，但这仍需在本次恢复后的构建上重新验证。

当前未提交补丁文件为：

- `target/system/core/fs_mgr/libfiemap/image_manager.cpp`
- `target/system/core/fs_mgr/libfiemap/include/libfiemap/image_manager.h`
- `target/system/core/fs_mgr/libsnapshot/include/libsnapshot/snapshot.h`
- `target/system/core/fs_mgr/libsnapshot/snapshot.cpp`
- `target/system/core/fs_mgr/libsnapshot/snapshot_test.cpp`

最终版本将 `TryCancelUpdate()` 区分为 `BeginUpdate()` 的旧事务清理授权和 `CancelUpdate()` 的本次 sideload fallback 路径；后者保持原生 Recovery 行为，不深度删除 re-flash 所需 snapshot 状态。恢复或重新实现时必须使用这一最终语义，而不是第一版“所有 Recovery `Initiated` 都深度清理”的实现。

边界：旧事务为何停在 `Initiated` 未获证明；不能断言是 remount、断电、强制重启或某个 APK 操作必然造成。不得在 Recovery 中手工删除 `/data/gsi/ota` 替代状态校验与设备解除映射。

## 为什么一次 sideload 会出现两次 `TryCancelUpdate()`

状态：已确认，适用本专题所列 EF930_2 源码和最终五文件补丁；最后源码核对日期：2026-08-03。

这两次调用可能在日志中都显示 `Update has been initiated, now canceling`，但它们不是同一笔事务，也不能使用同一种删除策略：

```text
旧 Android 内 OTA 遗留事务 A，状态为 Initiated
  -> Recovery 开始新的 sideload
  -> PrepareSnapshotPartitionsForUpdate()
  -> BeginUpdate()
  -> TryCancelUpdate(needs_merge, true)
  -> 受限地删除事务 A 的目标槽 COW、SnapshotStatus 和 state

本次 Recovery sideload 的 snapshot 尝试 B 失败
  -> Recovery full OTA 尝试 direct-write fallback
  -> CancelUpdate()
  -> TryCancelUpdate(needs_merge, false)
  -> 保持 Recovery 原有的“不物理删除 snapshot/COW 状态”语义
  -> 重建 direct-write 目标 LP metadata 并继续写入
```

- `BeginUpdate()` 使用 `TryCancelUpdate(&needs_merge, true)`；只有该入口在 Recovery 的旧 `Initiated` 事务上进入 `RemoveInitiatedUpdateInRecovery()`。该函数先拒绝存在 `snapshot-boot` 的状态，再验证全部 snapshot 名和 `/data` backing image 名均为 other/target slot，最后短暂允许删除。源码：`target/system/core/fs_mgr/libsnapshot/snapshot.cpp:171-245`、`321-383`。
- `CancelUpdate()` 使用 `TryCancelUpdate(&needs_merge, false)`。它服务于当前 sideload 的失败回退，不能借用上面的旧事务深度清理授权。Recovery 的原有 `DeleteSnapshot()` 只解除 dm/COW 映射，随后跳过状态文件和 backing image 的物理删除。源码：`snapshot.cpp:203-245`、`765-795`。
- 第一版修复把两条路径都做成深度删除，曾导致 direct-write fallback 后续映射 `odm_b`、`system_b` 时找不到 `/metadata/ota/snapshots/<name>`，在真正判断 re-flash 前就失败。最终补丁只允许 `BeginUpdate()` 清理经过校验的旧事务。

## Recovery 的 full direct-write fallback

`PrepareDynamicPartitionsForUpdate()` 在 VAB Recovery 中先尝试 `PrepareSnapshotPartitionsForUpdate()`。如果该尝试失败，Recovery 会记录“Attempt to overwrite existing partitions if possible”，调用当前事务的 `CancelUpdate()`，然后以 `delete_source = true` 重建并直接写入目标逻辑分区。Android 运行态不允许这样回退，源码明确要求 VAB Android OTA 使用 snapshot。源码：`target/system/update_engine/aosp/dynamic_partition_control_android.cc:498-552`、`943-978`。

这不是“保留旧 COW 后继续走 merge”：

- 当前 fallback 的目标 LP metadata 分区以 `LP_PARTITION_ATTR_READONLY` 创建，没有 `LP_PARTITION_ATTR_UPDATED`。因此映射时会被识别为 re-flash，直接返回普通目标逻辑分区，而不把旧 snapshot/COW 叠加到它上面。源码：`dynamic_partition_control_android.cc:1040-1054`、`snapshot.cpp:2376-2433`。
- 但 `MapUpdateSnapshot()` 先读取对应的 `SnapshotStatus`，再进入上述 re-flash 判断。因此当前 fallback 的状态文件不能被第一版补丁提前删除。源码：`snapshot.cpp:3601-3631`。
- 只有全量包可走这条路。增量 payload 的 `old_partition_info` 表示操作需要旧版本块作为输入；删除 source groups 后这些块不存在，源码直接拒绝并输出 `Cannot sideload incremental OTA because snapshots cannot be created.`。源码：`dynamic_partition_control_android.cc:1254-1283`。

## 重新验证条件

更换 Recovery、fs_mgr/update_engine 分支、OTA 包类型、动态分区布局或 `/data` 可见性后，按当前源码和实际日志重新确认。
