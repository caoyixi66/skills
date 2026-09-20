# EF930 平台代号与BP签名配置

状态：已确认  
适用范围：EF930 的 bengal/khaje/divar 与 QCM2290 参考线的 scuba/agatti 代号、LA/BP 目录边界、secimage 签名配置、msm-id/board-id 与 ABL 签名链路  
创建日期：2026-08-20  
最后验证日期：2026-08-20  
适用源码工作区：`V:\new_ssd1\workspace\android\ef930_2` / `\\10.199.40.231\caoyixi\new_ssd1\workspace\android\ef930_2`  
重新验证条件：切换源码工作区、BP 包版本、sectools 配置、产品 lunch 或 ABL/XBL 构建脚本后，重新检查本页路径、行号和产物来源。

## 资料边界

| 项目 | 内容 |
|---|---|
| 本专题回答的问题 | Qualcomm 为什么对同一颗芯片在 LA/BP/kernel/签名中使用多个代号；divar/agatti 签名字段与算法；EF930 ABL 为什么使用 divar 签名；多芯片镜像如何按 msm-id/board-id 选择 DTBO。 |
| 不覆盖的范围 | XBL/ABL 内部 UEFI 模块细节见 `专题/ABL与EDK2构建模型.md`；生产密钥和 CASS 证书细节；设备实机启动验证。 |
| 证据来源 | `xgd_build.sh`、`build_qcm2290_sc200e_32go.sh`、`Divar_IOT.LA.2.0`/`QCM2290.LA.5.0` 的 contents.xml、两份 divar/agatti secimage XML、khaje/scuba DTS、DT Makefile、`bengal-kernel/.config`、ABL `LocateDeviceTree.c`。 |

## 已确认事实

| 方向 | 事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| 代号矩阵 | `bengal` 是 Android BSP 平台名；`khaje` 是 SM6225 在 kernel/DT/ABL 的 SoC 名；`scuba` 是 QCM2290 在 kernel/DT 的 SoC 名；`divar` 是 SM6225 在 BP/签名侧的代号；`agatti` 是 QCM2290 在 BP/签名侧的代号。 | 已确认 | `target/device/qcom/bengal_515/BoardConfig.mk:8-10`、`target/kernel_platform/qcom/proprietary/devicetree/qcom/khaje.dtsi:13-15`、`scuba.dtsi:13-16`、`Unpacking_Tool/build_sm6225_64bit.sh`、`Unpacking_Tool/Divar_IOT.LA.2.0/contents.xml:25-27`。BSP/BP 版本变化后重验。 |
| LA/BP 目录边界 | `qssi14/`、`target/` 是 LA（Android 系统侧）；`Unpacking_Tool/` 是 BP 打包与源码目录。`Divar_IOT.LA.2.0` 和 `QCM2290.LA.5.0` 主要是 contents.xml + common 的打包/签名壳，实际源码在 `BOOT.XF.4.1`、`MPSS.HA.1.1`、`TZ.XF.5.1.6`、`RPM.BF.1.10`、`ADSP.VT.5.4.3.c1` 等兄弟目录。 | 已确认 | `Unpacking_Tool` 顶层目录、`Unpacking_Tool/build_sm6225_64bit.sh:12-16,31-37`、`Unpacking_Tool/Divar_IOT.LA.2.0/contents.xml:40-43`。目录或 BP 包版本变化后重验。 |
| divar BP 配置 | EF930 BP 包 divar：`oem_certs`、RSA 4096 + PSS + SHA256、`msm_part=0x001B80E1`、`soc_vers=0x9007`、`oem_id=0x0159`。 | 已确认 | `Unpacking_Tool/Divar_IOT.LA.2.0/common/sectools/config/divar/divar_secimage.xml:26-65`。sectools 配置变化后重验。 |
| divar LA 配置 | 同芯片在 `target/vendor/qcom/proprietary/sectools/config/divar/divar_secimage.xml` 是 `qti_presigned_certs`、RSA 2048、`oem_id=0x0000`；`msm_part`/`soc_vers` 相同。 | 已确认 | `target/vendor/qcom/proprietary/sectools/config/divar/divar_secimage.xml:26-65`。 |
| agatti LA 配置 | QCM2290 LA 树 agatti：`qti_presigned_certs`、ECDSA secp384r1 + SHA384、`msm_part=0x001450E1`、`soc_vers=0x9003`、`oem_id=0x0000`。 | 已确认 | `target/vendor/qcom/proprietary/sectools/config/agatti/agatti_secimage.xml:27-81`。 |
| agatti BP 配置 | QCM2290 BP 包 agatti：`oem_certs`、RSA 2048 + PSS + SHA256、`oem_id=0x0159`；`msm_part`/`soc_vers` 与 LA 配置相同。 | 已确认 | `Unpacking_Tool/QCM2290.LA.5.0/common/sectools/config/agatti/agatti_secimage.xml:27-81`。 |
| 签名对比误区 | “divar RSA4096 vs agatti ECDSA”是混着比：divar 取 BP 包配置，agatti 取 LA 树配置。同侧对比时，BP 包侧 divar/agatti 都是 `oem_certs` + RSA PSS，仅 4096/2048 差异。 | 已确认 | 上述四份 XML 的差异。sectools 配置更新后重验。 |
| EF930 实际签名 | `xgd_build.sh` 的 `build_abl()` 和 `build_xbl_only()` 都用 `Unpacking_Tool/Divar_IOT.LA.2.0/common/sectools/config/divar/divar_secimage.xml`；ABL 签名输出拷为根目录 `abl.elf`。 | 已确认 | `xgd_build.sh:1400-1482,1653-1676`。构建脚本变化后重验。 |
| QCM2290 参考 ABL | `build_qcm2290_sc200e_32go.sh` 的 `build_abl()` 使用 LA 树 `target/vendor/qcom/proprietary/sectools/.../agatti_secimage.xml` 签名，说明“ABL 必须跟 BP 包走”不是 Qualcomm 统一规则，而是 EF930 项目的自定义选择。 | 已确认 | `build_qcm2290_sc200e_32go.sh:191-200`。 |
| unsigned 命名陷阱 | `target/kernel_platform/out/msm-kernel-bengal-gki/abl-userdebug/unsigned_abl.elf` 是 EDK2 未签名产物；`Unpacking_Tool/.../secimage_output/divar/abl/unsigned_abl.elf` 是签名后仍保留旧名的产物。 | 已确认 | `xgd_build.sh:1430-1443`；两个路径均存在。重新编译/签名后重验。 |
| msm-id | `khaje.dtsi` 基础 `msm-id=518/586`；`scuba.dtsi` 基础 `msm-id=441`；SC200E IOT 板 `scuba-iot-qrd-eldo-overlay.dts` 为 `473/474`。 | 已确认 | `khaje.dtsi:15`、`scuba.dtsi:16`、`scuba-iot-qrd-eldo-overlay.dts:10`。DT 改动后重验。 |
| EF930 板级 overlay | `khaje-ef930-dbg` 的 `msm-id=518/586`、`board-id=0x10022`；`khaje-ef930-fmu` 为 `0x10023`；WiFi-only 变体 `khaje-ef930-fmu-wf` 为 `0x10025`。 | 已确认 | `khaje-ef930-dbg-overlay.dts:10-11`、`khaje-ef930-fmu-overlay.dts:11-12`、`khaje-ef930-fmu-wf-overlay.dts:14-18`。 |
| 多芯片启动 | 内核侧同时使能 `CONFIG_ARCH_BENGAL/KHAJE/SCUBA`，Makefile 同时把 KHAJE 和 SCUBA 的 DTB/DTBO 编入；ABL 的 `LocateDeviceTree` 按 `qcom,msm-id`/`qcom,board-id` 选择 DTBO。 | 已确认 | `target/device/qcom/bengal-kernel/.config:345-347`、`devicetree/qcom/Makefile:117-127,217-220,279-295`、`LocateDeviceTree.c:191-228,665-675`。 |
| lunch 边界 | 当前仓库 `AndroidProducts.mk` 只有 `bengal_515`、`bengal_515-user` 及 wifionly 变体；`bengal_515_32go.mk` 不存在。QCM2290 参考脚本中的 `bengal_515_32go` 属于另一条参考线。 | 已确认 | `target/device/qcom/bengal_515/AndroidProducts.mk:1-8`；`Test-Path bengal_515_32go.mk=False`。lunch 变更后重验。 |
| kernel 输出 | `target/device/qcom/bengal-kernel/` 是 bengal 内核构建输出目录，含 `Image`、`vmlinux`、`.ko`、`dtbs`、`kernel-abl` 等，不是内核源码根目录。 | 已确认 | 2026-08-20 目录内容检查。清理 `out/` 后重验。 |
| QFIL 产物 | `Unpacking_Tool/qfil_download_emmc/` 含 `abl.elf`、`xbl.elf`、`dtbo.img`、`boot.img`、`vendor_boot.img`、`prog_emmc_ufs_firehose_qcm6225_ddr_quectel.elf` 等线刷成品。 | 已确认 | 2026-08-20 目录清单。重新打包后重验。 |

## 常见误区

- 不要把 `Divar_IOT.LA.2.0` 当成 xbl/tz/modem 源码根目录；它是 BP 打包/签名壳，源码在 `Unpacking_Tool` 的兄弟包。
- 不要用一份 divar 配置和另一份 agatti 配置直接比较算法；先确认是 LA 树配置还是 BP 包配置。
- `oem_id=0x0159` 不等于签名配置里写死 Nexgo；仓库产品层有 `vendor/nexgo`，但 XML 只写数值。
- `473` 只是 scuba IOT 板 overlay 的 msm-id 之一，不是 scuba 全系唯一 ID。
- `unsigned_abl.elf` 在 EDK2 out 和 sectools output 两个位置都存在，前者未签名、后者已签名，核对产物时不要只看文件名。

## 可复用检查顺序

1. 先确认要回答的是 LA 侧还是 BP 侧：`qssi14/target` 还是 `Unpacking_Tool/*.LA.*`。
2. 查 `contents.xml` 的 `product_name/chipid/build_id`，确定当前 BP 包版本和代号。
3. 查实际构建脚本使用的 sectools 路径和 `-c <secimage.xml>`，不要直接假设使用 `target/vendor/.../sectools`。
4. 核对 secimage XML 的 `selected_cert_config/msm_part/soc_vers/oem_id/dsa_type/rsa_padding/ecdsa_curve/hash_algorithm`。
5. 核对 msm-id/board-id 时区分基础 `*_base.dtsi` 与板级 overlay；基础文件可能不代表具体板子。
6. 对初学者解释时，先讲“平台名、SoC 名、BP/签名名”是不同领域的三个名字，再进入签名算法和构建链路。