# EF930 ABL 与 EDK2 构建模型

状态：已确认  
适用范围：EF930 ABL 的 DEC、INF、DSC、FDF、LibraryClass、调试产物与镜像打包链路；当前工作区 `\\10.199.40.231\caoyixi\new_ssd1\workspace\android\ef930_1`（Linux 原生路径 `/home/new_ssd1/caoyixi/workspace/android/ef930_1`）  
最后验证日期：2026-08-17  
重新验证条件：EDK2 BaseTools、`QcomModulePkg.dsc`、`QcomModulePkg.fdf`、ABL 包装脚本或目标产品构建配置变更后，重新检查本页的构建链和工具语义。

## 资料边界

| 项目 | 内容 |
|---|---|
| 本专题回答的问题 | EF930 ABL 中 DEC、INF、DSC、FDF、LibraryClass 的职责和连接关系；`LinuxLoader` 的模块类型；调试产物与最终 ABL 镜像的区别。 |
| 不覆盖的范围 | XBL 如何调度 ABL、硬件显示驱动内部、签名密钥、刷机和设备运行时结果。本文是当前源码和已存在构建日志的结论，不替代本轮编译或设备验证。 |
| 证据来源 | `QcomModulePkg` 元数据、EDK2 `makefile`、`build/build_abl.sh`、`build_modulepkg.log`、`BaseTools` Python 源码。 |

## 已确认事实

| 方向 | 事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| EDK2 元数据层级 | DEC 是 Package 公共声明；INF 是单个模块的构建说明；DSC 是本次平台构建的组件和库实现选择；FDF 是固件镜像中 Firmware Volume 的布局。DSC/FDF 虽位于 `QcomModulePkg` 目录，但语义是平台/镜像级，不等同于 DEC 的 Package 级。 | 已确认 | `QcomModulePkg.dec`、`QcomModulePkg.dsc:74-83`、`QcomModulePkg.fdf:125-168`。平台、FDF 或 BaseTools 更换后重验。 |
| LinuxLoader | `Application/LinuxLoader/LinuxLoader.inf` 定义 `MODULE_TYPE = UEFI_APPLICATION`、入口为 `LinuxLoaderEntry`。它是 ABL 内的主 UEFI Application，不等同于整个 `abl.elf`。 | 已确认 | `LinuxLoader.inf:15-26`；FDF 将其放入 `FVMAIN`。模块类型或 FDF 改动后重验。 |
| 库模块 | `XgdBootLib.inf` 是 `MODULE_TYPE = BASE`、`LIBRARY_CLASS = XgdBootLib` 的库模块；`BootLib`、`XgdBootLib` 的目标代码会链接进使用它们的 LinuxLoader，而不是作为独立可启动应用写入 FDF。 | 已确认 | `XgdBootLib.inf:15-25`、`LinuxLoader.inf:44-68`、`QcomModulePkg.dsc:311-335`。库结构改动后重验。 |
| 实际库绑定 | `LinuxLoader.inf` 仅声明需要 `BootLib` 和 `XgdBootLib`；`QcomModulePkg.dsc` 为 LinuxLoader 绑定 `Library/BootLib/BootLib.inf` 与 `Library/XgdBootLib/XgdBootLib.inf`。DSC 按 LibraryClass 绑定库实例，不是按单个 C 函数绑定。 | 已确认 | `LinuxLoader.inf:61-68`、`QcomModulePkg.dsc:328-335`。DSC 覆盖规则或组件配置改动后重验。 |
| 旋转修复的链接路径 | `LinuxLoader.c` 调用 `SetDrawUiRotation(GetBootDisplayRotation())`；前者由 `BootLib/DrawUI.c` 提供，后者由 `XgdBootLib.c` 提供。两者都属于既有库模块，因此该修复未新增 INF/DSC/FDF 条目。 | 已确认 | `Application/LinuxLoader/LinuxLoader.c:595`、`Library/BootLib/DrawUI.c:199-221`、`Library/XgdBootLib/XgdBootLib.c:212-246`。调用或库归属变化后重验。 |
| 调试与镜像产物 | `LinuxLoader.debug` 是链接出的 LinuxLoader 调试副产物，用于符号和源码行定位；`LinuxLoader.efi` 是 UEFI Application 格式；`unsigned_abl.elf` 是由 `FVMAIN_COMPACT.Fv` 经 `image_header.py` 包装的未签名 ABL 镜像，后续才可签名为 `abl.elf`。 | 已确认 | `build_modulepkg.log` 中 `LinuxLoader.dll -> LinuxLoader.debug -> GenFw -> LinuxLoader.efi`；`makefile:462,471-472`。构建脚本/签名流程改动后重验。 |

## EF930 构建链

```text
xgd_build.sh -abl
  -> target/kernel_platform/build/build_abl.sh
  -> edk2/makefile
  -> build -p QcomModulePkg/QcomModulePkg.dsc
  -> 编译 LinuxLoader 和已绑定库
  -> LinuxLoader.efi
  -> LinuxLoader.ffs
  -> FVMAIN.Fv
  -> FVMAIN_COMPACT.Fv
  -> abl.fv
  -> unsigned_abl.elf
  -> 签名流程产出 abl.elf
```

`QcomModulePkg.fdf` 的 `FVMAIN` 写入 `LinuxLoader.inf`；`FVMAIN_COMPACT` 将 `FVMAIN` 作为 GUIDED section 的 `FV_IMAGE` 再封装。不要把库 INF 直接加入 FDF：库应先链接进消费者模块，FDF 只放需要作为独立固件文件存在的模块。

## LibraryClass 的四层关系

```text
DEC [Includes]
  仅提供头文件搜索目录，解决编译器如何找到 .h。

DEC [LibraryClasses]
  登记公共 LibraryClass 与其规范头文件的关系，属于 Package API 元数据。

INF [LibraryClasses]
  消费者模块声明自己需要哪个 LibraryClass。

DSC [LibraryClasses]
  平台为该 LibraryClass 选择具体库实例 INF；实例 INF 再列出其 .c 源码。
```

以 `MemoryAllocationLib` 为例：

```text
MdePkg.dec
  MemoryAllocationLib|Include/Library/MemoryAllocationLib.h
    -> 公共 API 声明 AllocatePool/AllocateZeroPool/FreePool

BootLib.inf
  [LibraryClasses] MemoryAllocationLib
    -> BootLib 需要该库能力

QcomModulePkg.dsc
  MemoryAllocationLib|MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
    -> 本 ABL 选择 UEFI 实现

UefiMemoryAllocationLib.inf
  LIBRARY_CLASS = MemoryAllocationLib|... UEFI_APPLICATION ...
  [Sources] MemoryAllocationLib.c
    -> 实际调用 gBS->AllocatePool()/gBS->FreePool()
```

同一个 LibraryClass 可以有多个实现，但同一个最终消费者模块只链接 DSC 选中的一个实现。现有树中 `UefiMemoryAllocationLib` 和 `PeiMemoryAllocationLib` 都实现 `MemoryAllocationLib`，但后者面向 PEI 阶段并使用 `PeiServicesAllocatePool()`；不能把两份同名实现同时链接进同一个模块。

## DEC [LibraryClasses] 的关键边界与纠正

此前曾把 DEC 的 `[LibraryClasses]` 解释成“当前普通 build 的链接必需链路”，这是不准确的。当前 EF930 的 BaseTools 在 `Workspace/DecBuildData.py:322` 明确注释：

```text
Retrieve library class declarations (not used in build at present)
```

因此必须区分：

| 问题 | 当前 EF930 普通构建的实际依据 |
|---|---|
| 编译器如何找到头文件 | INF `[Packages]` 引入 DEC，DEC `[Includes]` 提供 include 根目录。 |
| 模块需要哪个库 | 消费者 INF 的 `[LibraryClasses]`。 |
| 最终选择并链接哪个实现 | DSC 的 LibraryClass 到 Library Instance INF 映射，以及提供者 INF 的 `LIBRARY_CLASS` 和 `[Sources]`。 |
| DEC `[LibraryClasses]` 的作用 | 公共 API/接口归属登记；可被 ECC 等元数据检查用来验证 INF 声明的 LibraryClass 是否在关联 Package 中定义；当前普通 build 不以它选择链接实现。 |

`QcomModulePkg.dec` 当前仅通过 `[Includes.common]` 暴露 `Library/XgdBootLib/` 等目录，而没有为 `XgdBootLib` 增加 DEC `[LibraryClasses]` 条目；现有 `LinuxLoader.inf -> QcomModulePkg.dsc -> XgdBootLib.inf` 链路仍可完成当前构建。不要为了形式完整而在未确认工具链和现有规范前补写元数据。

## 可复用检查顺序

1. 从实际构建入口开始，确认 `build -p <platform>.dsc` 指向哪个 DSC。
2. 从 DSC 的 `[Components]` 定位消费者 INF，再读取其 `[Sources]`、`[Packages]`、`[LibraryClasses]`。
3. 从 DSC 的 LibraryClass 映射定位具体实现 INF，并确认实现 INF 的 `LIBRARY_CLASS`、支持模块类型和 `[Sources]`。
4. 从 DSC 的 `FLASH_DEFINITION` 进入 FDF，确认模块是否作为独立 FFS/FV 内容打包；库不应被误当作独立 FDF 模块。
5. 查阅当前 BaseTools 的实际代码、构建日志和生成命令，区分“元数据登记/检查”与“编译/链接/镜像包装的实际输入”。
6. 对初学者解释时，先分别说明“声明、依赖、实现、打包”四件事，避免把 DEC `[Includes]`、DEC `[LibraryClasses]`、INF `[LibraryClasses]`、DSC 映射混成一条规则。
