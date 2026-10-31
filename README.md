# synology-rndis-autoup

Windows-assisted RNDIS driver installation and automatic interface activation for a narrowly validated Synology DSM configuration.

群晖 RNDIS 驱动安装与 USB 热插拔自动启用工具。通过 Windows 内置 SSH 连接 NAS，检查兼容性、校验下载、备份文件并配置自动启用。

## 支持范围

仅在以下条件**全部满足**时安装：

| 项目 | 要求 |
| --- | --- |
| CPU | AMD Ryzen Embedded V1500B |
| DSM 平台 | v1000，不是 v1000nk |
| 架构 | x86_64 |
| DSM | 7.4.x |
| 内核 | 4.4.302+ |

初始实机验证环境：系统报告型号 DS1821+，DSM 7.4.1-90080 Update 1。CPU 相同不代表其他平台或内核也兼容；未验证的配置会拒绝安装。

## Windows 使用

1. 使用 GitHub 的 **Code → Download ZIP** 下载并解压。
2. 确保三个脚本在同一文件夹，双击 **Run-RNDIS-Setup.cmd**。
3. 输入 NAS 的 SSH 地址、端口（默认 22）和管理员用户名。
4. 首次连接时核对服务器主机密钥指纹。
5. 按提示输入 SSH 密码，sudo 可能再次要求密码。输入时不显示字符，脚本不保存密码。

前提：Windows 已安装 OpenSSH 客户端；NAS 已启用 SSH，账户可以使用 sudo；NAS 能通过 HTTPS 访问 GitHub，并具有 curl、tar、sha256sum、base64、udevadm 和 ip。

也可在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Synology-RNDIS.ps1
```

启动器的 ExecutionPolicy Bypass 仅对该进程生效，不修改系统持久策略。组织策略仍可能阻止运行。

## 做了什么

- 核对 CPU、平台、DSM 与内核。
- 下载固定版本的 rndis_host、mii 和 cdc_ether，逐文件验证 SHA-256。
- 在 /usr/local/lib/rndis-backup 中保存修改前的文件。
- 保留系统 usbnet，安装所需模块，设置开机加载。
- 安装 udev 规则：网络设备新增且父驱动为 rndis_host 时，自动启用实际接口。
- 启用当前已绑定该驱动的接口。

热插拔规则不依赖 usb0 这个名称，因此 usb1 等接口也可适用：

```udev
ACTION=="add", SUBSYSTEM=="net", DRIVERS=="rndis_host", RUN+="/sbin/ip link set dev %k up"
```

**启用网卡不等于配置网络。** 本项目不配置 DHCP、静态 IP、DNS 或默认路由，也不自动重启 NAS。

## 文件与维护

| 文件 | 作用 |
| --- | --- |
| Run-RNDIS-Setup.cmd | Windows 双击入口 |
| Install-Synology-RNDIS.ps1 | 交互输入与 SSH 调用 |
| install-rndis-remote.sh | NAS 检查、备份、安装和热插拔配置 |
| [docs/maintenance.md](docs/maintenance.md) | 排障、校验、升级与回滚 |

现有自定义模块与目标版本不一致时会停止，不自动卸载在用驱动。加载失败会返回错误并保留备份，**不会自动回滚**。首次使用请查看完整输出。

## 验证状态

- 驱动加载、USB 绑定及 IPv6 对端通信已实机验证。
- 热插拔规则通过定向补发 net add 事件验证：接口从 DOWN 自动变为 UP。
- Windows PowerShell 与 NAS Shell 语法已检查。
- 尚未完成发布版安装器的完整端到端测试、真实重启测试，以及规则部署后的再次物理拔插测试。
- CI 仅检查语法；不证明内核模块兼容性。

## 上游与许可

本仓库只提供安装与维护脚本，**不分发驱动二进制，也不声称开发了这些驱动**。

- [robertklep/dsm7-usb-serial-drivers](https://github.com/robertklep/dsm7-usb-serial-drivers)：rndis_host.ko，固定提交 b2f5f9be176c97f27fd808aeb2cbbeff56ade1db。
- [AuxXxilium/arc-modules](https://github.com/AuxXxilium/arc-modules)：mii.ko、兼容的 cdc_ether.ko，版本 26.10.19，v1000-7.4-4.4.302.tgz。
- [udev 文档](https://www.freedesktop.org/software/systemd/man/latest/udev.html)：设备添加事件与规则语法。

原创脚本和文档使用 [MIT License](LICENSE)。第三方驱动与 Linux 内核代码遵循各自上游许可，MIT 许可不覆盖它们。此项目与 Synology 无官方关联。

