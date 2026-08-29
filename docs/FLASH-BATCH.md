# flash_batch — KMBox 固件批量烧录工具（Windows）

> 纯 Python 标准库实现（无第三方依赖），是 `tools/flash_kmbox_windows.ps1` 的替代方案，
> 额外支持**多设备批量烧录**。已验证环境：Windows 11 + Git Bash / cmd。

---

## 它做什么

1. 自动定位编译产物（`build-waveshare/PIOKMbox.uf2` → `build-metro/PIOKMbox.uf2`，与 ps1 脚本优先级一致）
2. 轮询检测处于 **BOOTSEL 模式** 的 RP2350 板子（挂载为 U 盘，卷标 `RPI-RP2` 或白标后的 `KMBOX-BRDG`）
3. 将 `.uf2` 复制到该盘 → 板子自动重启、盘符消失 → 烧录完成
4. 复制过程中设备断开（烧录完成瞬间的正常现象）会被捕获并按成功处理，与 ps1 行为一致

## 快速开始

```bash
# 方式一：直接运行脚本（需要 Python，uv 会自动处理环境）
cd D:/Project/aimbot/kmbox
uv run tools/flash_batch.py

# 方式二：双击运行已构建的 EXE（tools/dist/flash_batch.exe）
#         双击后会进入交互模式：等待设备 → 烧录 → 显示汇总 → 按回车退出
```

烧录时按住板上 **BOOTSEL** 再插 USB 线（或按住 BOOTSEL 按一下 RESET）即可。

## 全部参数

| 参数 | 默认 | 说明 |
|:-----|:-----|:-----|
| `--uf2 <路径>` | 自动查找 | 指定固件文件路径 |
| `--all` | 关 | 批量模式：依次烧录当前所有 BOOTSEL 设备，不弹选择菜单 |
| `--wait <秒>` | 60 | 等待 BOOTSEL 设备出现的超时 |
| `--verify <秒>` | 15 | 等待设备重启（盘符消失）的验证超时 |
| `--list` | — | 仅列出当前检测到的设备后退出（不等待） |
| `--version` | — | 显示版本 |

## 多设备行为

| 场景 | 行为 |
|:-----|:-----|
| 检测到 1 个设备 | 直接开始烧录（一键体验） |
| 检测到多个设备 | 列出菜单：输入序号烧录指定设备 / `a` 全部 / `q` 退出 |
| `--all` | 跳过菜单，依次烧录全部设备，最后输出汇总（成功/警告/失败计数） |

## 用 uv 构建 EXE

```bash
cd D:/Project/aimbot/kmbox/tools
uvx pyinstaller --onefile --console --clean --name flash_batch flash_batch.py
# 产物: tools/dist/flash_batch.exe （约 9 MB，单文件，双击即可运行）
```

- 构建依赖由 `uvx` 临时环境提供（PyInstaller），脚本本身零依赖
- 附带构建产生 `tools/build/`、`tools/flash_batch.spec`，建议在 `.gitignore` 加一行 `tools/dist/` 等目录避免误提交
- EXE 双击运行（无参数）时结束前会暂停等待回车，窗口不会一闪而过

## 退出码

| 码 | 含义 |
|:---|:-----|
| 0 | 成功（或 `--list` 正常返回 / 用户主动退出） |
| 1 | 至少一个设备烧录失败 |
| 2 | 未找到固件文件 |
| 3 | 等待设备超时 |
| 130 | 用户 Ctrl+C 中断 |

## 故障排查

<details>
<summary><b>中文输出乱码</b></summary>

cmd 窗口先执行 `chcp 65001` 切换 UTF-8；Git Bash / Windows Terminal 一般无此问题。

</details>

<details>
<summary><b>始终检测不到设备</b></summary>

1. 确认按住了 BOOTSEL 再插线，电脑上出现名为 `RPI-RP2` 的 U 盘
2. 换 USB 线（纯充电线不行）、换 USB 口（不要经 Hub）
3. 用 `--list` 快速验证；识别依据是卷标 `RPI-RP2` / `KMBOX-BRDG`，或可移动盘上存在 `INFO_UF2.TXT`

</details>

<details>
<summary><b>提示「盘符仍存在，烧录可能未完成」</b></summary>

复制命令已返回但设备未重启。重新上电（拔插 USB）让板子重启；若仍异常，重新进入 BOOTSEL 再烧一次。

</details>

<details>
<summary><b>路径包含中文或空格</b></summary>

脚本内部全部使用 `pathlib` 处理路径，`--uf2` 参数含中文/空格可直接使用（建议加引号）。

</details>
