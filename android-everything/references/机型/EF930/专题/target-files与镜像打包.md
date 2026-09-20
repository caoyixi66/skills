# EF930 Target-files 与镜像打包

状态：部分确认  
适用源码工作区：`V:\new_ssd1\workspace\android\ef930_2`  
最后源码核对：2026-08-08  
适用范围：target-files、`system.img` 重建、A/B 增量 OTA 输入、线刷包边界与 Recovery VAB 验证边界。

## 资料边界

| 项目 | 内容 |
|---|---|
| 本专题回答的问题 | target-files 中有什么、为什么同时保存文件树和镜像、正常 `system.img` 构建与 target-files 重建有何区别、增量包的真正输入、线刷包和 OTA 的关系 |
| 不覆盖的范围 | 某个 modem、efuse 的具体分区名、签名链、slot 模型及其自定义升级代码；这些必须按目标分支和产物再次核对 |
| 证据来源 | 当前 EF930_2 的 `qssi14/build/make`、`target/system/update_engine`、已检查的 target-files/线刷产物及 Recovery 专题中的历史日志 |
| 验证边界 | 宿主机离线产包、ZIP metadata 检查和源码阅读不等于 Recovery sideload 成功；刷机、重启、sideload、清理 snapshot 状态必须另行获得明确授权 |

## 先区分四种交付物

| 名称 | 主要用途 | 是否足以作为 A/B 增量 OTA 的输入 |
|---|---|---|
| `target-files.zip` | 发布工程的可重打包输入；含文件树、镜像和构建 metadata | 是。旧 target-files 作 `--incremental_from`，新 target-files 作目标输入 |
| 全量 OTA ZIP | 交给 `update_engine`/Recovery 的最终安装包；含 `payload.bin`、`payload_properties.txt`、metadata 和 ZIP 签名 | 否。它是输出，不是下一次差分生成的完整输入 |
| 增量 OTA ZIP | 同上，但 payload 同时描述 source 和 target 分区信息 | 否。不能反向替代旧 target-files |
| line-flash ZIP / 线刷包 | fastboot、EDL 或厂商线刷工具的刷写物料；常含 `rawprogram*.xml`、`super*.img`、bootloader/RADIO 镜像 | 否。即使含有 `system.img` 或 `super.img`，也通常缺少 target-files 的完整 `META/`、分区文件树和重打包信息 |

结论：不要把“有两个线刷包”直接等同于“可制作 Android 标准增量 OTA”。增量 OTA 的正确比较对象是匹配的旧、新 target-files；线刷包只能用于核对镜像内容、分区布局和额外固件，不是 `ota_from_target_files --incremental_from` 的替代品。

## Target-files 的结构和职责

典型 target-files 包至少可按下面四类理解：

```text
SYSTEM/、VENDOR/、PRODUCT/、ODM/ ...
    逻辑分区的解包文件树：用于重建、重签和一致性检查

IMAGES/*.img
    已制作好的分区镜像，例如 system.img、vendor.img、vbmeta.img

META/*
    镜像属性、签名映射、文件属性、A/B 分区清单、动态分区信息等

RADIO/*
    打包进 target-files 的基带、bootloader 等非文件系统镜像
```

它是一个“发布输入包”，不是设备升级时原样写入的包。`ota_from_target_files` 读取它后，选择 A/B 分区集合、准备 old/new 镜像、调用 `delta_generator`，才得到最终 OTA ZIP。

EF930 为 QSSI/vendor 拆分构建：QSSI partial target-files 提供 framework 侧的 `SYSTEM/`、`PRODUCT/`、`SYSTEM_EXT/` 等，`target` partial target-files 提供 vendor/ODM/启动镜像侧内容，`merge_target_files` 合并后才形成最终 OTA 输入。具体合并边界见 `专题/VAB动态分区.md` 的“QSSI 与 target-files 合并边界”。

## 正常构建与 Target-files 重建 system.img

两条路径使用的是同一类文件和元数据规则，但输入位置不同：

```text
源码编译和安装
  -> TARGET_OUT/                         已安装的 system 文件树
  -> build_image(TARGET_OUT, props, ..., TARGET_OUT)
  -> PRODUCT_OUT/system.img              正常镜像构建

target-files 打包
  -> TARGET_OUT/ 复制为 target-files/SYSTEM/
  -> 导出 META/*
  -> add_img_to_target_files
  -> target-files/IMAGES/system.img      可重打包镜像
```

### 正常 system.img 构建

`qssi14/build/make/core/Makefile:3211-3228` 调用：

```text
build_image TARGET_OUT system_image_info.txt system.img TARGET_OUT
```

第一个 `TARGET_OUT` 是要放入 system 分区的文件树；最后一个 `TARGET_OUT` 让镜像工具能够读取当前构建输出中的设备专用文件属性配置。正常构建也会汇总各模块的 file-contexts，生成 `file_contexts.bin`，并把其路径写入 image properties。源码：`Makefile:1864-1878`。

因此，“正常整编不需要 `filesystem_config.txt`”不等于“正常整编不需要文件属性或 SELinux 规则”。它同样需要：

```text
fs_config 规则 -> uid/gid/mode/capability 等 inode 属性
file_contexts.bin -> pathname 到 SELinux context 的匹配，写入 inode 的 SELinux xattr
image properties -> 文件系统类型、大小、稀疏格式、AVB 等
```

### Target-files 为什么还会重新制作镜像

创建 target-files 时，构建系统先复制 `TARGET_OUT` 到 ZIP staging 的 `SYSTEM/`。源码：`Makefile:6008-6012`。随后导出 `META/file_contexts.bin`、`META/misc_info.txt`、`META/apkcerts.txt` 和 `META/apexkeys.txt`。源码：`Makefile:6082-6090`。

最后，`Makefile:6273-6278` 调用 `add_img_to_target_files -a`。`AddSystem()` 若已存在 `IMAGES/system.img` 则复用；不存在才从 `SYSTEM/` 创建，并同时生成 `IMAGES/system.map`。源码：`qssi14/build/make/tools/releasetools/add_img_to_target_files.py:268-302`。

这可能导致同一轮完整发布构建中“序列化文件系统镜像”不止一次，但不是把 APK、Java、C/C++ 再编译一次。只执行 `systemimage` 与只执行 `target-files-package` 的依赖路径也不完全相同，不能从命令名推断是否一定已有另一份 `system.img`。

不要只凭逻辑断言两份镜像哈希必然相同。文件内容和属性应对应同一构建，但镜像字节还会受 UUID、时间戳、AVB footer、稀疏格式和工具行为影响；target-files 重建路径会显式设置可重复的 timestamp、UUID 和 hash seed。源码：`add_img_to_target_files.py:575-607`。需要结论时，对具体产物做 SHA-256 和解稀疏/分区内容核对。

## fs_config、filesystem_config.txt 与 file_contexts.bin

这三个名字相近，但不是同一件事：

| 名称 | 本质 | 正常构建中的作用 | target-files 中的作用 |
|---|---|---|---|
| `fs_config` | 宿主机工具和文件属性计算机制 | 根据当前构建和设备规则计算每条路径的 uid/gid/mode/capability | 在打包时对 staging 文件树逐路径求值 |
| `META/filesystem_config.txt` | 上述计算的可携带结果清单 | 通常不是普通构建的必需前置文件 | 重建镜像时作为显式 `fs_config` 文件输入 |
| `META/file_contexts.bin` | 编译后的 SELinux 路径到 context 规则 | 交给镜像工具，给 inode 写 SELinux label | 解压重打包时替代原构建机上的路径 |

构建 Makefile 通过宿主机 `fs_config` 遍历 `SYSTEM/`，把输出写到 `META/filesystem_config.txt`：`Makefile:5649-5654`、`6219-6228`。这份文件是“已算出的每个路径属性表”，不是另一个名为 `fs_config` 的二进制。

重打包时，`CreateImage()` 查找 `META/filesystem_config.txt` 并设置 Python 属性 `image_props["fs_config"]`；随后 `build_image.py` 将其作为镜像工具的 `-C` 输入。源码：`add_img_to_target_files.py:575-607`、`build_image.py:255-325`。`LoadInfoDict(..., repacking=True)` 还会将 `misc_info.txt` 中原先指向构建机路径的 `*_selinux_fc` 改指向 `META/file_contexts.bin`。源码：`common.py:827-885`。

`SYSTEM/etc/selinux/plat_file_contexts`、`VENDOR/etc/selinux/vendor_file_contexts` 是设备分区内的运行时策略/规则文件；它们不等同于 target-files 的 `META/file_contexts.bin`。后者是宿主机重建镜像时的构建输入，设备升级时不会在 Recovery 中逐文件运行 `fs_config`。

## META 中其余常见文件

| 文件 | 宿主机用途 | 不应误解为 |
|---|---|---|
| `misc_info.txt` | 镜像文件系统、分区尺寸、AVB、动态分区、A/B 等全局属性；`LoadInfoDict()` 是 releasetools 的早期入口 | 设备端 payload 的“逐块偏移表” |
| `ab_partitions.txt` | A/B payload 候选更新分区名单；构建/校验会确认名单中的镜像是否可用 | ZIP 中凡是有镜像都自动更新 |
| `dynamic_partitions_info.txt` | super 内动态分区组、大小等构建信息 | `super.img` 的字节级差分指令 |
| `apkcerts.txt`、`apexkeys.txt` | 发布主机重签 target-files 的密钥映射输入；私钥本体不应在 ZIP 中 | Recovery 或 update_engine 在设备端执行的重签任务 |
| `IMAGES/*.map` | 文件路径到镜像 block range 的映射；构建时由 block-list 输出 | 设备端更新脚本或文件内容本身 |

`sign_target_files_apks` 是 AOSP releasetools 的宿主机工具。其目的不是“APK 一定没签过”，而是允许工程将构建期 test/dev key 的 target-files 转换为 release key 的 target-files；APK/APEX、相关镜像和 AVB metadata 可能因此需要重建。源码：`qssi14/build/make/tools/releasetools/Android.bp`、`sign_target_files_apks.py`。

`.map` 的一行可表达某个文件落在镜像的哪些 block。`delta_generator` 支持 `--old_mapfiles` 和 `--new_mapfiles`，但某次具体 OTA 是否传入、是否利用它，必须以该次 `ota_from_target_files` 的实际命令和生成日志为准。不能仅因为 target-files 中存在 `system.map` 就断言该差分一定使用了 map。源码：`target/system/update_engine/payload_generator/generate_delta_main.cc:325-333`。

## A/B payload 与 modem、efuse 等自定义固件

`META/ab_partitions.txt` 是“本次标准 A/B payload 选择哪些分区”的名单。`add_img_to_target_files` 会读取它，并检查名单中的镜像可从 `IMAGES/` 或 `RADIO/` 取得。源码：`add_img_to_target_files.py:1171-1180`。`ota_from_target_files` 再以这个集合组织 `delta_generator` 的 `--partition_names`、`--new_partitions`，而增量场景还会传 `--old_partitions`。

`delta_generator` 本身是 AOSP host 工具，支持多个分区的 old/new 镜像；旧镜像存在时设置 payload 为 delta。源码：`target/system/update_engine/payload_generator/generate_delta_main.cc:313-333`、`573-624`。因此 `boot`、`dtbo`、`abl`、`xbl` 等在名单中的分区并不天然只能全量或只能差分：是否生成 source-copy/bsdiff/replace 等操作取决于 old/new 内容、分区格式与生成器决策。

对 EF930 当前已检查的 target-files，`modem.img` 虽可位于 `RADIO/`，但没有因为“文件存在”就自动进入当前 A/B payload。若需要使 modem 或 efuse 按标准 payload 更新，不能只手改最终 ZIP 的名单；至少需要逐项确认并实现：

1. 该分区是否有 A/B slot 和可由 update_engine 解析、映射和写入的设备路径。
2. 构建配置是否将它加入 `AB_OTA_PARTITIONS`，并确保 old/new target-files 都提供同名、可读取的镜像。
3. 该固件自己的签名、反回滚、写入顺序、掉电恢复和依赖关系是否允许由 update_engine 更新。
4. 若是 vendor/Qualcomm 自定义处理路径，是否与 payload metadata、ZIP offset、签名和 Recovery sideload 路径一致；不能把传统 updater 的 `filesmap`/固件 patch 逻辑直接套到 A/B payload。
5. 先离线检查 payload manifest、分区名、old/new hash 和签名，再在专门设备上做明确授权的 sideload、重启、slot 和固件版本验证。

`old_partition_info` 是增量 payload 的标志之一。Recovery 若无法创建 VAB snapshot，全量 payload 可尝试 direct-write fallback；增量包因需要旧 source 块，在该 fallback 路径会被拒绝。这不是“Recovery 永远不能 sideload 差分包”，而是“snapshot 准备失败时，增量包不能安全回退”。源码：`target/system/update_engine/aosp/dynamic_partition_control_android.cc:1253-1283`。Recovery 的具体状态机、历史 stale `Initiated` 修复和日志边界见 `专题/Recovery与OTA.md`。

## 产包与测试的经验教训

1. 先区分真实产物：line-flash、target-files、全量 OTA、增量 OTA 的角色不同；回答“能否做差分”前先检查 ZIP 根目录和 `META/`。
2. 增量包必须锁定精确 source baseline。`source target-files` 不是“任意旧线刷包”，而是设备当前版本对应的旧发布输入；source hash mismatch 往往意味着基线或当前 slot 不对。
3. 离线生成成功只证明 host 侧输入和工具链可工作。它不证明设备当前版本匹配、Recovery `/data` 可创建 snapshot、签名被接受、payload 能写入或重启后能启动。
4. 判断 Recovery sideload 失败时，从 `/tmp/recovery.log`、`/cache/recovery/last_log`、`/cache/recovery/last_kmsg` 取首个决定性错误；同时保存 update_engine、snapshotctl、slot 与构建版本证据。
5. 不要手工删除 `/data/gsi/ota`、`/metadata/ota` 或 COW 文件来伪造干净环境。VAB 的 snapshot 状态、dm 映射和 backing image 之间有依赖，必须走分支匹配且已验证的清理逻辑。
6. 修改 modem/efuse、payload 分区列表、签名或 ZIP 封装前，先保留原 package 的 payload offset、manifest、签名和 SHA-256；任何“metadata 与 payload 偏移不一致”的历史问题都要在改包后重新检查。

## 当前验证结论与重新验证条件

| 结论 | 当前状态 | 重新验证条件 |
|---|---|---|
| target-files 是 EF930 A/B 增量 OTA 的正确 old/new 输入 | 已确认 | 更换 Android 分支、release tool 或 target-files 合并流程 |
| line-flash 不能直接替代 `--incremental_from` target-files | 已确认 | 厂商另行实现将线刷物料转换为完整 target-files 的流程 |
| 正常 image 构建也使用文件属性和 SELinux context 规则 | 已确认 | 更换 build/make、文件系统工具或产品镜像类型 |
| `filesystem_config.txt` 是 `fs_config` 计算结果的可携带清单 | 已确认 | 修改 target-files 重打包脚本或 fs_config 工具 |
| Recovery 在 snapshot 正常创建时可尝试 sideload 增量 payload | 源码确认，真机未在干净基线验证 | 使用精确 source baseline、干净 snapshot 状态和对应 Recovery 做受控测试 |
| modem/efuse 可进入 EF930 标准 A/B payload | 待按具体分区验证 | 确认 slot、device path、签名/反回滚、自定义 updater 代码和端到端设备测试 |
