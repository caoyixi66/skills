# EF930 VAB升级后救援模式

状态：部分确认  
适用范围：metadata加密data挂载失败、init救援触发、Recovery证据边界  
创建日期：2026-09-17

## 问题摘要

| 字段 | 内容 |
|---|---|
| 现象 | VAB全量 sideload 返回成功并切到 slot B；第一次 normal boot 后进入 XGD 救援页；确认 wipe 后同一 slot B 可进入 QSSI 14 系统。 |
| 首个决定性错误 | slot B 首次开机挂载失败，BCB 被写成 `/system/bin/recovery --prompt_and_wipe_data --reason=fs_mgr_mount_all`，Recovery 打印 `rescuePart mode!!!`。 |
| 已确认原因 | OTA 后新槽首次 normal boot 无法挂载 metadata 加密的 `/data`；init 将 `FS_MGR_MNTALL_DEV_NEEDS_RECOVERY_WIPE_PROMPT` 转成救援确认页。不是 OTA 安装失败，也不是 payload 漏刷 userdata 或刷写 metadata 分区镜像。 |
| 未确认部分 | slot B 首次 normal boot 中 vold 的具体失败行。可能是 `decryptWithKeystoreKey failed`、`KEY_REQUIRES_UPGRADE`、wrapped key export 失败或 metadata 钥匙目录异常；失败当次 logcat/串口/pstore 未保存，不能指定唯一根因。 |
| 安全处置边界 | 复现时必须先采集 slot B 首次 normal boot 的 vold/init 日志，再做 wipe。不要用 Recovery 的 `Invalid ext4 superblock` 判定 userdata 物理损坏：Recovery fstab 只写 `encryptable=footer`，它检查的是未解密 raw 盘。 |

## 证据链

| 顺序 | 事实或日志 | 结论边界 | 证据位置 |
|---|---|---|---|
| 1 | `powerwash_required: false`、`Detected a 'full' payload`、`Update successfully applied`、`Install from ADB completed with status 0` | OTA 安装成功且未安排 powerwash；不能推断“升级必须恢复出厂” | U盘日志 `F:\.sys_log\recovery\last_log.1`；本地副本 `D:\ai\codex\2026-09-17\ef930-ota-rescue\last_log.1.txt` |
| 2 | payload 逐分区 hash 只有 17 个 A/B 分区：abl、boot、dtbo、init_boot、odm、product、recovery、system、system_dlkm、system_ext、vbmeta、vbmeta_system、vendor、vendor_boot、vendor_dlkm、xbl、xbl_config；无 metadata/userdata | `payload.bin` 没有整盘刷 `/metadata` 或 `/userdata`；日志里的 payload metadata、ZIP metadata、super LP metadata 都不是 metadata 分区镜像 | 同上，`last_log.1` hash 段；参考包 `D:\devices\ef930\EF930_base_signed\payload.bin` 结构一致 |
| 3 | `reason is [fs_mgr_mount_all]`、`--prompt_and_wipe_data`、`ro.boot.slot_suffix=_b`、`rescuePart mode!!!` | 已确定救援页由 slot B normal boot 挂载失败触发，进入 XGD rescuePart UI | `F:\.sys_log\recovery\last_log` |
| 4 | `Formatting /data...`、`Formatting /metadata...`、`Data wipe complete.`；清数据后 `SYSTEM_BOOT` 显示 `EF930:14/UKQ1.250303.001/eng.xgd_sc.20260912.173435:user/release-keys` | wipe 同时清 data 与 metadata；清后证明 slot B 系统镜像可启动，不证明旧数据损坏 | `last_log` 与 `F:\.sys_log\dropbox\SYSTEM_BOOT@1789626613302.txt` |
| 5 | `Invalid ext4 superblock on userdata`、`can not mount data!!!` 只出现在救援 Recovery 内 | 只能证明 Recovery 不能直接挂未解密 raw `/data`，不能证明 `/data` 坏；不能作为 vold 失败原句 | `last_log` |
| 6 | 源码 `late-fs` 先 `exec_start wait_for_keymaster`，再 `mount_all --late`；EF930 fstab `/data` 带 metadata encryption、wrappedkey、`keydirectory=/metadata/vold/metadata_encryption` | 确认 `/data` 必须由当前 Keymaster/vold 解锁后才能挂载 | `/home/new_ssd1/caoyixi/workspace/android/ef930_2`：`target/device/qcom/bengal_515/init.target.rc:72-75`、`target/device/qcom/bengal_515/emmc/fstab_AB_dynamic_partition.qti:51-53` |
| 7 | `fs_mgr` 对 metadata 加密项调用 `vold cryptfs mountFstab`；失败返回 `FS_MGR_MNTALL_DEV_NEEDS_RECOVERY_WIPE_PROMPT`；init 生成 `--prompt_and_wipe_data --reason=fs_mgr_mount_all` | 可把失败点收窄到 normal boot 的 metadata 加密挂载路径 | `target/system/core/fs_mgr/fs_mgr.cpp:1555-1566`、`target/system/core/init/builtins.cpp:590-596` |
| 8 | vold `retrieveOrGenerateKey()` 区分旧钥匙 retrieve 与首次 generate；wrappedkey 路径调用 `exportWrappedStorageKey()`；`KEY_REQUIRES_UPGRADE` 当前直接 `return false` | 说明“旧密文钥匙 + 当前安全环境”是开机必经机制；但该具体失败未被本次日志捕获 | `qssi14/system/vold/KeyUtil.cpp:479-494`、`qssi14/system/vold/KeyStorage.cpp:157-176、623-645`、`qssi14/system/vold/MetadataCrypt.cpp:134-146、250-310` |
| 9 | XGD Recovery `prompt_and_wipe_data()` 设置 `rescuePart=1` 并打印 `rescuePart mode!!!` | 当前界面是 XGD 扩展救援页，不是 Java RescueParty | `target/bootable/recovery/recovery.cpp:211-217`、`target/bootable/recovery/xgdrecovery/xgd_recovery.cpp:736-744` |
| 10 | `.rescue_party_logs` 为空；拷贝源固定为 `/private/nxglogger/rescue_party.log*` | Java RescueParty 未运行；U盘该目录不能作为本故障证据 | `F:\.rescue_party_logs`；源码 `target/bootable/recovery/xgdrecovery/xgd_recovery.cpp:1142-1213` |

## 版本与升级定性

| 对象 | 已确认版本 | 证据 | 边界 |
|---|---|---|---|
| 升级前 slot A Recovery | Android 13、userdebug、incremental `149`、09-16 | `last_log.1` Recovery prop：`ro.build.fingerprint` | 这是 Recovery 进程 prop，不等价于升级前 normal system 指纹 |
| 升级前 slot A normal system | 能进系统，有 SystemServer/PMS/launcher；指纹未保存 | `F:\.sys_log\nxglogger\nxglog.log` | 不能写成 13→14 或 14→14 的明确版本升级 |
| OTA 包 vendor/Recovery 侧 | Android 13 | Rescue prop 与 EF930 QSSI+target merge 架构 | `xgd_build.sh` 分 QSSI14 与 target vendor 13，架构本身不是故障 |
| 清数据后 normal system | Android 14、user、`eng.xgd_sc.20260912.173435` | `SYSTEM_BOOT@1789626613302.txt` | 这是 wipe 后成功启动版本 |
| 包时间戳 | target build `20260912.173435`；slot A Recovery build 09-16 | `last_log.1` `target_build` 与 prop | 日志有 `Get factory_mode, don't check time`、`xgd allow downgrade`；不能将本次称为单纯“旧升新” |

## 已知机制与禁止结论

- AOSP A/B OTA 默认保留用户数据；`POWERWASH=1` 是显式开关，默认 false。本次 `powerwash_required: false`。禁止把“OTA 后必须恢复出厂”写成 Android 原生规则。
- “新系统用当前 Keymaster 解 `/metadata` 旧密文”是 metadata encryption + wrappedkey 的开机解锁机制，不是故意失败机制。设计目标是解锁成功。
- 本次已确认失败层为 normal boot 挂载 metadata 加密 `/data`；未确认 Keymaster/vold 具体错误码。禁止在无首次 normal boot 日志时写成唯一根因。
- `xgd_build.sh` 的 QSSI 14 + vendor 13 是合并架构；不要把正常架构版本混排列为故障原因。
- Upgrade 侧写过 `modem_b` 与 `secdata`，且 secdata 已有 ELF 头仍被写入 12764 字节；这属于候选影响安全环境的证据，不能单独证明导致 Keymaster 失败。
- Rescue Recovery 的 `Invalid ext4 superblock` 不得判定 userdata 物理损坏。

## 验证与回归

| 验证项 | 结果 | 状态 | 重新验证条件 |
|---|---|---|---|
| OTA 安装与成功返回 | `status 0`，slot 切到 B，`powerwash_required: false` | 已确认 | 更换包类型、签名、构建时间或更新流程 |
| 救援触发链 | `fs_mgr_mount_all` -> `--prompt_and_wipe_data` -> `rescuePart mode!!!` | 已确认 | Recovery、init、fs_mgr、fstab 或 rescuePart UI 修改 |
| payload 分区范围 | 17 个 A/B 分区；无 metadata/userdata | 已确认 | 更换 OTA 生成脚本或 AB_OTA_PARTITIONS |
| Keymaster/vold 精确错误 | 未取得失败当次日志 | 待验证 | 复现时保留 slot B 首次 normal boot 串口/logcat/pstore，抓 `decryptWithKeystoreKey failed`、`KEY_REQUIRES_UPGRADE`、`Failed to get ephemeral wrapped key`、`No key found` |
| 安全环境变化影响 | 写入 vendor/boot/abl/xbl/secdata；旧数据 wipe 后恢复 | 部分确认 | 用相同版本、非降级包对照；保留 `/metadata` 备份线索或设备串口，对比 Keymaster 输出 |
| QSSI 14 + vendor 13 合并架构 | `xgd_build.sh` 分段构建合并；wipe 后系统可启动 | 已确认 | merge 工具、lunch、QSSI/target 版本或包封装变化 |

## 建议复现取证顺序

1. 保留可复现旧包与旧 slot A 环境，记录升级前 normal system 的 `getprop ro.build.fingerprint`。
2. sideload 后立即用串口捕获 slot B 首次 normal boot，不要先 wipe。
3. 重点抓 vold/keystore/keymaster、`dm-default-key`、`cryptfs mountFstab` 与 init `queue_fs_event` 日志。
4. 如仍进救援，先从救援 Recovery 拷 `last_log`/`last_kmsg`/pstore，再决定 wipe。
5. 对照同版本、同 variant、非降级包；必要时按用户逐项授权测试 `POWERWASH=1` 与不写 `secdata` 的对照包。
