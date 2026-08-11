# Changelog

## Unreleased

- Add an optional setting to restore WeType after voice input that starts while Doubao is already active.
- Intercept and forward the captured voice shortcut after Doubao activates, avoiding cold-start event ordering races.
- Require and report both Input Monitoring and Accessibility permissions for reliable shortcut forwarding.

## 0.1.2

- 恢复右 Option 的异步提前切换，减少豆包长时间闲置后的首次唤醒等待。
- 重新加入输入监控授权状态与首次设置入口。

## 0.1.1

- 由豆包输入法完整处理右 Option 语音开关，避免输入源竞态。
- 移除输入监听权限与抢先切换逻辑。
- 补充两次 Option 完成录音与恢复的回归测试。

## 0.1.0

- 支持豆包全局语音结束后恢复微信输入法。
- 使用 CoreAudio 进程录音状态，避免长语音被固定超时截断。
- 支持右 Option 快速启动。
- 增加首次设置、开机启动、手动恢复和日志入口。
