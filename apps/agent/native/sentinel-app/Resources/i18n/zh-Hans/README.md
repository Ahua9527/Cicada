# Sentry

<p align="center">
  <a href="../../../README.md">English</a> |
  <a href="README.md">简体中文</a>
</p>

一款强大的 macOS 安全监控应用程序，可检测未经授权的访问尝试并为您录制视频证据。

想象一下：你在咖啡店里愉快地编码时，突然内急。你必须离开但又不想把笔记本电脑拖到洗手间。只需激活哨兵模式，如果发生任何可疑情况，你可以快速处理完事情并冲回现场！

## 预览

![预览图片](../../../Resources/Preview.png)

## 功能特性

- 🔒 **全面监控**：跟踪屏幕状态、网络连接和电源连接
- 📹 **自动录制**：启用时录制视频片段
- 🚨 **多重警报系统**：声音警报和通过 Bark 推送通知
- 🎯 **实时检测**：即时监控设备状态变化

## 系统要求

- macOS 13.0+
- 摄像头访问权限用于视频录制

## 安装

1. 从 Mac App Store 下载 Sentry：

[![App Store 图标](../../../Resources/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg)](https://apps.apple.com/us/app/sentry-just-step-away/id6746349629)

2. 禁用自动睡眠模式 [见下文](#安装---禁用自动睡眠)
3. 需要时，从应用程序文件夹启动 Sentry。

如果你不想从 App Store 购买，也可以从源代码构建。在这种情况下 Sentry 是免费的。

## 安装 - 禁用自动睡眠

为确保 Sentry 有效工作，你需要防止 Mac 进入睡眠状态。如果没有此设置，当有人快速合上屏幕时，你的 Mac 可能会在 Sentry 触发声音警报或发送通知之前进入睡眠状态。使用以下方法之一来解决此问题：

### 选项 1：使用 SleepHoldService

Sentry 通过使用 [SleepHoldService](https://github.com/Lakr233/SleepHoldService) 自动防止你的 Mac 进入睡眠状态。通过运行以下终端命令安装此服务：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Lakr233/SleepHoldService/HEAD/net_install.sh)"
```

### 选项 2：使用 `pmset` 命令

你可能需要禁用睡眠模式以确保警报正常工作，使用以下命令行：

```bash
sudo pmset -a disablesleep 1
```

要重新启用睡眠模式，使用：

```bash
sudo pmset -a disablesleep 0
```

## 许可证

本项目采用 MIT 许可证。详情请参阅 LICENSE 文件。

## 免责声明

本软件旨在对您自己的设备进行合法的安全监控。用户有责任确保遵守有关录制和监控的当地法律法规。

---

版权所有 2025 © Lakr Aream。保留所有权利。
