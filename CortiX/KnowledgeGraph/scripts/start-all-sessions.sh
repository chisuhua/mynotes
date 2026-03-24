#!/bin/bash
# start-all-sessions.sh — 一键启动所有 Session（tmux + openclaw tui + 提示词注入）
# 用法：./start-all-sessions.sh [--project <项目名>] [--parent <父目录>] [--base <基础目录>] [--mode architect|reviewer|both]

set -e

# 默认值
BASE_DIR="/workspace/mynotes"
PARENT_DIR=""
PROJECT_NAME=""
MODE="both"  # architect, reviewer, both

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_session() { echo -e "${MAGENTA}[SESSION]${NC} $1"; }

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --parent)
      PARENT_DIR="$2"
      shift 2
      ;;
    --base)
      BASE_DIR="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    -h|--help)
      echo "用法：$0 [--project <项目名>] [--parent <父目录>] [--base <基础目录>] [--mode architect|reviewer|both]"
      echo ""
      echo "参数:"
      echo "  --project        项目名（可选，如果当前目录是项目目录则自动检测）"
      echo "  --parent         父目录（可选）"
      echo "  --base           基础目录（可选，默认 /workspace/mynotes）"
      echo "  --mode           启动模式（可选，默认 both）"
      echo "                   - architect: 只启动 Architect Session"
      echo "                   - reviewer:  只启动 Reviewer Session"
      echo "                   - both:      同时启动两个 Session"
      echo ""
      echo "示例:"
      echo "  # 指定项目名"
      echo "  $0 --project KnowledgeGraph --parent CortiX --mode both"
      echo ""
      echo "  # 在项目目录中直接运行（自动检测）"
      echo "  cd /workspace/mynotes/CortiX/KnowledgeGraph"
      echo "  ./scripts/start-all-sessions.sh"
      exit 0
      ;;
    *)
      log_error "未知参数：$1"
      exit 1
      ;;
  esac
done

# 自动检测项目目录（如果未指定项目名）
if [ -z "$PROJECT_NAME" ]; then
  # 检查当前目录是否有 .review-workspace.json
  if [ -f "./.review-workspace.json" ]; then
    log_info "自动检测项目配置..."
    PROJECT_NAME=$(grep -o '"project": *"[^"]*"' .review-workspace.json | cut -d'"' -f4)
    PARENT_DIR=$(grep -o '"parent": *"[^"]*"' .review-workspace.json | cut -d'"' -f4)
    BASE_DIR=$(grep -o '"base": *"[^"]*"' .review-workspace.json | cut -d'"' -f4)
    PROJECT_PATH="$(pwd)"
    log_info "检测到项目：${PROJECT_NAME}"
  else
    log_error "未指定 --project 参数，且当前目录不是项目目录（缺少 .review-workspace.json）"
    exit 1
  fi
else
  # 构建项目路径
  if [ -n "$PARENT_DIR" ]; then
    PROJECT_PATH="${BASE_DIR}/${PARENT_DIR}/${PROJECT_NAME}"
  else
    PROJECT_PATH="${BASE_DIR}/${PROJECT_NAME}"
  fi
fi

# 检查项目目录是否存在
if [ ! -d "$PROJECT_PATH" ]; then
  log_error "项目目录不存在：${PROJECT_PATH}"
  exit 1
fi

# 读取 .review-workspace.json 配置
CONFIG_FILE="${PROJECT_PATH}/.review-workspace.json"
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "配置文件不存在：${CONFIG_FILE}"
  log_info "请先运行 init-project.sh 初始化项目工作台"
  exit 1
fi

log_info "读取配置：${CONFIG_FILE}"

# 解析配置
SESSION_ARCH=$(grep -o '"architect": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
SESSION_REV=$(grep -o '"reviewer": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
ARCHITECT_FILENAME=$(grep -o '"architect": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
REVIEWER_FILENAME=$(grep -o '"reviewer": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)

# 如果配置中文件名是 session 名，则重新获取文件名
if [ ! -f "${PROJECT_PATH}/${ARCHITECT_FILENAME}" ]; then
  # 尝试检测提示词文件
  if [ -f "${PROJECT_PATH}/ARCHITECT.md" ]; then
    ARCHITECT_FILENAME="ARCHITECT.md"
  else
    ARCHITECT_FILENAME=$(ls "${PROJECT_PATH}"/ARCHITECT_*.md 2>/dev/null | head -1 | xargs basename)
  fi
fi

if [ ! -f "${PROJECT_PATH}/${REVIEWER_FILENAME}" ]; then
  if [ -f "${PROJECT_PATH}/REVIEWER.md" ]; then
    REVIEWER_FILENAME="REVIEWER.md"
  else
    REVIEWER_FILENAME=$(ls "${PROJECT_PATH}"/REVIEWER_*.md 2>/dev/null | head -1 | xargs basename)
  fi
fi

# Session 名（小写）
SESSION_ARCH=$(echo "${SESSION_ARCH}" | tr '[:upper:]' '[:lower:]')
SESSION_REV=$(echo "${SESSION_REV}" | tr '[:upper:]' '[:lower:]')

ARCHITECT_PROMPT="${PROJECT_PATH}/${ARCHITECT_FILENAME}"
REVIEWER_PROMPT="${PROJECT_PATH}/${REVIEWER_FILENAME}"

log_info "项目路径：${PROJECT_PATH}"
log_info "Architect Session: ${SESSION_ARCH}"
log_info "Reviewer Session: ${SESSION_REV}"
log_info "Architect 提示词：${ARCHITECT_FILENAME}"
log_info "Reviewer 提示词：${REVIEWER_FILENAME}"

# 启动 Architect Session
start_architect() {
  log_step "启动 Architect Session: ${SESSION_ARCH}"
  
  # 检查提示词文件
  if [ ! -f "$ARCHITECT_PROMPT" ]; then
    log_error "Architect 提示词文件不存在：${ARCHITECT_PROMPT}"
    return 1
  fi
  
  # 创建 tmux 窗口（如果不存在）
  WINDOW_NAME="${PROJECT_NAME}-Arch"
  if ! tmux list-windows -F "#W" 2>/dev/null | grep -q "^${WINDOW_NAME}$"; then
    log_info "创建 tmux 窗口：${WINDOW_NAME}"
    tmux new-window -n "${WINDOW_NAME}" -c "${PROJECT_PATH}"
  else
    log_info "tmux 窗口已存在：${WINDOW_NAME}"
  fi
  
  # 在 tmux 窗口中启动 openclaw tui
  log_session "启动 openclaw tui --session ${SESSION_ARCH}"
  tmux send-keys -t "${WINDOW_NAME}" "openclaw tui --session ${SESSION_ARCH}" Enter
  
  # 等待 openclaw 启动（约 2 秒）
  sleep 2
  
  # 注入提示词到上下文（通过 tmux send-keys 发送用户消息）
  log_session "注入提示词到 Architect Session 上下文..."
  tmux send-keys -t "${WINDOW_NAME}" "# 🦊 Architect Session 已启动" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "**项目**: ${PROJECT_NAME}" Enter
  tmux send-keys -t "${WINDOW_NAME}" "**提示词文件**: ${ARCHITECT_FILENAME}" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "以下是我的角色提示词，请仔细阅读并遵循：" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "---" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  
  # 逐行发送提示词内容（避免过长命令）
  while IFS= read -r line || [ -n "$line" ]; do
    tmux send-keys -t "${WINDOW_NAME}" "$line" Enter
  done < "$ARCHITECT_PROMPT"
  
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "---" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "请确认你已理解提示词内容，并准备好开始工作。" Enter
  
  log_success "Architect Session 已启动并注入提示词"
}

# 启动 Reviewer Session
start_reviewer() {
  log_step "启动 Reviewer Session: ${SESSION_REV}"
  
  # 检查提示词文件
  if [ ! -f "$REVIEWER_PROMPT" ]; then
    log_error "Reviewer 提示词文件不存在：${REVIEWER_PROMPT}"
    return 1
  fi
  
  # 创建 tmux 窗口（如果不存在）
  WINDOW_NAME="${PROJECT_NAME}-Rev"
  if ! tmux list-windows -F "#W" 2>/dev/null | grep -q "^${WINDOW_NAME}$"; then
    log_info "创建 tmux 窗口：${WINDOW_NAME}"
    tmux new-window -n "${WINDOW_NAME}" -c "${PROJECT_PATH}"
  else
    log_info "tmux 窗口已存在：${WINDOW_NAME}"
  fi
  
  # 在 tmux 窗口中启动 openclaw tui
  log_session "启动 openclaw tui --session ${SESSION_REV}"
  tmux send-keys -t "${WINDOW_NAME}" "openclaw tui --session ${SESSION_REV}" Enter
  
  # 等待 openclaw 启动
  sleep 2
  
  # 注入提示词到上下文
  log_session "注入提示词到 Reviewer Session 上下文..."
  tmux send-keys -t "${WINDOW_NAME}" "# 🦊 Reviewer Session 已启动" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "**项目**: ${PROJECT_NAME}" Enter
  tmux send-keys -t "${WINDOW_NAME}" "**提示词文件**: ${REVIEWER_FILENAME}" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "以下是我的角色提示词，请仔细阅读并遵循：" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "---" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  
  # 逐行发送提示词内容
  while IFS= read -r line || [ -n "$line" ]; do
    tmux send-keys -t "${WINDOW_NAME}" "$line" Enter
  done < "$REVIEWER_PROMPT"
  
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "---" Enter
  tmux send-keys -t "${WINDOW_NAME}" "" Enter
  tmux send-keys -t "${WINDOW_NAME}" "请确认你已理解提示词内容，并准备好开始工作。" Enter
  
  log_success "Reviewer Session 已启动并注入提示词"
}

# 主逻辑
echo ""
echo "============================================"
echo "  🦊 DevMate | Project Review Workspace"
echo "============================================"
echo ""

case "$MODE" in
  architect)
    start_architect
    ;;
  reviewer)
    start_reviewer
    ;;
  both)
    start_architect
    echo ""
    start_reviewer
    ;;
esac

echo ""
log_success "=========================================="
log_success "所有 Session 启动完成！"
log_success "=========================================="
echo ""
echo "快速命令:"
echo "  连接 Architect:  tmux select-window -t ${WINDOW_NAME}"
echo "  连接 Reviewer:   tmux select-window -t ${PROJECT_NAME}-Rev"
echo "  查看窗口列表：tmux list-windows"
echo ""
log_info "💡 提示：提示词已通过 tmux 注入到 Session 上下文中"
log_info "🦊 DevMate | 工作台就绪 --"
