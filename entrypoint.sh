#!/bin/sh
# 雨云自动签到启动脚本
# 支持两种运行模式：单次运行（默认）和定时模式
set -e

DEFAULT_SCHEDULE="0 8 * * *"
VALID_AT_EXPRESSIONS="@yearly @annually @monthly @weekly @daily @hourly"

pick_python() {
  for c in /usr/local/bin/python /usr/local/bin/python3 /usr/local/bin/python3.11 python3 python; do
    if command -v "$c" >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}

if [ "$CRON_MODE" = "true" ]; then
  echo "=== 定时模式启用 ==="

  CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | tr -d '"' | tr -d "'")
  CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -z "$CRON_SCHEDULE" ]; then
    echo "警告: CRON_SCHEDULE 未设置或为空，使用默认值: $DEFAULT_SCHEDULE"
    CRON_SCHEDULE="$DEFAULT_SCHEDULE"
  fi

  VALID=false
  for expr in $VALID_AT_EXPRESSIONS; do
    if [ "$CRON_SCHEDULE" = "$expr" ]; then
      VALID=true
      break
    fi
  done

  if [ "$VALID" = "false" ]; then
    SPACE_COUNT=$(echo "$CRON_SCHEDULE" | tr -cd ' ' | wc -c | tr -d ' ')
    if [ "$SPACE_COUNT" -ge 4 ]; then
      VALID=true
    fi
  fi

  if [ "$VALID" = "false" ]; then
    echo "错误: CRON_SCHEDULE 格式无效: $CRON_SCHEDULE"
    echo "期望格式: '分 时 日 月 周' 或 @daily/@hourly 等"
    echo "使用默认值: $DEFAULT_SCHEDULE"
    CRON_SCHEDULE="$DEFAULT_SCHEDULE"
  fi

  echo "执行计划: $CRON_SCHEDULE"
  echo "时区: ${TZ:-"(未设置)"}"

  PY_BIN="$(pick_python || true)"
  if [ -z "$PY_BIN" ]; then
    echo "致命错误: 未找到可用的 python 可执行文件（python/python3）"
    ls -l /usr/local/bin/python* 2>/dev/null || true
    exit 1
  fi

  echo "使用 Python: $PY_BIN"
  ls -l /usr/local/bin/python* 2>/dev/null || true
  ls -l /bin/sh 2>/dev/null || true

  # ----------------------------
  # 关键修复：用 wrapper 脚本承载参数
  # ----------------------------
  RUNNER="/app/run_rainyun.sh"
  cat > "$RUNNER" <<EOF
#!/bin/sh
exec "$PY_BIN" -u /app/rainyun.py
EOF
  # 去掉潜在 CRLF + 赋可执行权限
  sed -i 's/\r$//' "$RUNNER"
  chmod +x "$RUNNER"

  # 生成 crontab：命令部分不带空格参数（只执行脚本）
  CRON_FILE="/app/crontab"
  printf "%s %s\n" "$CRON_SCHEDULE" "$RUNNER" > "$CRON_FILE"
  sed -i 's/\r$//' "$CRON_FILE"

  echo "=== Crontab 内容 ==="
  cat "$CRON_FILE"
  echo "=== Crontab 可见字符(用于排查隐藏字符) ==="
  cat -A "$CRON_FILE" || true
  echo "===================="

  exec supercronic -passthrough-logs "$CRON_FILE"

else
  exec python -u /app/rainyun.py
fi
