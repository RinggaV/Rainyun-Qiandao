#!/bin/sh
# 雨云自动签到启动脚本
# 支持两种运行模式：单次运行（默认）和定时模式
set -e

# 默认 cron 表达式（每天 8:00）
DEFAULT_SCHEDULE="0 8 * * *"

# 合法的 @ 表达式白名单（supercronic 支持的）
VALID_AT_EXPRESSIONS="@yearly @annually @monthly @weekly @daily @hourly"

# -------------------------
# 工具函数：选择可用 python
# -------------------------
pick_python() {
  # 优先绝对路径，其次用 PATH 查找
  for c in /usr/local/bin/python /usr/local/bin/python3 /usr/local/bin/python3.11 python3 python; do
    if command -v "$c" >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}

# -------------------------
# 主逻辑
# -------------------------
if [ "$CRON_MODE" = "true" ]; then
  echo "=== 定时模式启用 ==="

  # 先去除可能的引号（兼容旧配置）
  CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | tr -d '"' | tr -d "'")

  # 去除首尾空格
  CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # 校验 CRON_SCHEDULE（去引号和空格后再判断）
  if [ -z "$CRON_SCHEDULE" ]; then
    echo "警告: CRON_SCHEDULE 未设置或为空，使用默认值: $DEFAULT_SCHEDULE"
    CRON_SCHEDULE="$DEFAULT_SCHEDULE"
  fi

  # 格式校验
  VALID=false

  # 检查是否为合法的 @ 表达式
  for expr in $VALID_AT_EXPRESSIONS; do
    if [ "$CRON_SCHEDULE" = "$expr" ]; then
      VALID=true
      break
    fi
  done

  # 如果不是 @ 表达式，检查是否为 5 段标准格式（至少 4 个空格）
  if [ "$VALID" = "false" ]; then
    SPACE_COUNT=$(echo "$CRON_SCHEDULE" | tr -cd ' ' | wc -c | tr -d ' ')
    if [ "$SPACE_COUNT" -ge 4 ]; then
      VALID=true
    fi
  fi

  # 校验失败，使用默认值
  if [ "$VALID" = "false" ]; then
    echo "错误: CRON_SCHEDULE 格式无效: $CRON_SCHEDULE"
    echo "期望格式: '分 时 日 月 周' 或 @daily/@hourly 等"
    echo "使用默认值: $DEFAULT_SCHEDULE"
    CRON_SCHEDULE="$DEFAULT_SCHEDULE"
  fi

  echo "执行计划: $CRON_SCHEDULE"
  echo "时区: ${TZ:-"(未设置)"}"

  # 选择 python 可执行文件（避免写死 /usr/local/bin/python 导致 ENOENT）
  PY_BIN="$(pick_python || true)"
  if [ -z "$PY_BIN" ]; then
    echo "致命错误: 未找到可用的 python 可执行文件（python/python3）"
    echo "调试信息："
    ls -l /usr/local/bin/python* 2>/dev/null || true
    which python 2>/dev/null || true
    which python3 2>/dev/null || true
    exit 1
  fi

  echo "使用 Python: $PY_BIN"
  # 输出一些调试信息，帮助确认是否为架构/链接问题
  ls -l /usr/local/bin/python* 2>/dev/null || true
  file "$PY_BIN" 2>/dev/null || true

  # 生成 crontab 文件（用 printf，避免 echo 在不同 shell 下转义/换行差异）
  CRON_FILE="/app/crontab"
  printf "%s %s -u /app/rainyun.py\n" "$CRON_SCHEDULE" "$PY_BIN" > "$CRON_FILE"

  # 关键：去掉可能的 Windows 回车（\r），否则会变成 python^M 导致 “no such file”
  sed -i 's/\r$//' "$CRON_FILE"

  echo "=== Crontab 内容 ==="
  cat "$CRON_FILE"
  echo "=== Crontab 可见字符(用于排查隐藏字符) ==="
  # cat -A 会把隐藏字符显示出来（比如 ^M）
  cat -A "$CRON_FILE" || true
  echo "===================="

  # 启动 supercronic
  # -passthrough-logs: 直接输出任务日志，不添加额外前缀
  exec supercronic -passthrough-logs "$CRON_FILE"

else
  # 单次运行模式（默认，兼容现有行为）
  exec python -u /app/rainyun.py
fi
