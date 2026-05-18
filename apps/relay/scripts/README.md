# 调试脚本

CicadaRelay 调试和测试工具集。

## 可用脚本

- `debug-api.sh` - API 测试（health、send、ws等）
- `debug-diagnostic.sh` - 系统诊断
- `debug-integration.sh` - 集成测试
- `debug-logs.sh` - 日志监控和分析
- `debug-tools.sh` - 工具集（签名、性能测试等）

## 使用示例

```bash
# API 测试
./scripts/debug-api.sh health
./scripts/debug-api.sh send ping

# 系统诊断
./scripts/debug-diagnostic.sh all

# 日志监控
./scripts/debug-logs.sh monitor
```

## 环境变量

```bash
CICADA_RELAY_URL=https://cicada-relay.ahua.space \
API_KEY=your-api-key \
./scripts/debug-api.sh health
```

