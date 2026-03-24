#!/bin/bash
# start-review-sessions.sh — 通用启动 Architect 和 Reviewer Session 的脚本
# 用法：./start-review-sessions.sh --project <项目名> [--parent <父目录>] [--base <基础目录>] [--mode architect|reviewer|both] [--no-tmux]

set -e

# 默认值
BASE_DIR="/workspace/mynotes"
PARENT_DIR=""
PROJECT_NAME=""
MODE="both"  # architect, reviewer, both
NO_TMUX=false

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

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
    --no-tmux)
      NO_TMUX=true
      shift
      ;;
    -h|--help)
      echo "用法：$0 --project <项目名> [--parent <父目录>] [--base <基础目录>] [--mode architect|reviewer|both] [--no-tmux]"
      echo ""
      echo "参数:"
      echo "  --project        项目名（必填，如 KnowledgeGraph）"
      echo "  --parent         父目录（可选，如 CortiX）"
      echo "  --base           基础目录（可选，默认 /workspace/mynotes）"
      echo "  --mode           启动模式（可选，默认 both）"
      echo "                   - architect: 只启动 Architect Session"
      echo "                   - reviewer:  只启动 Reviewer Session"
      echo "                   - both:      同时启动两个 Session"
      echo "  --no-tmux        不启动 tmux，只输出 openclaw 命令"
      echo ""
      echo "示例:"
      echo "  $0 --project KnowledgeGraph --parent CortiX --mode both"
      echo "  $0 --project PTX-EMU --mode architect --no-tmux"
      exit 0
      ;;
    *)
      log_error "未知参数：$1"
      exit 1
      ;;
  esac
done

# 验证必填参数
if [ -z "$PROJECT_NAME" ]; then
  log_error "必须指定 --project 参数"
  exit 1
fi

# 验证模式
case "$MODE" in
  architect|reviewer|both)
    ;;
  *)
    log_error "无效的模式：$MODE (必须是 architect, reviewer, 或 both)"
    exit 1
    ;;
esac

# 构建项目路径
if [ -n "$PARENT_DIR" ]; then
  PROJECT_PATH="${BASE_DIR}/${PARENT_DIR}/${PROJECT_NAME}"
else
  PROJECT_PATH="${BASE_DIR}/${PROJECT_NAME}"
fi

# 检查项目目录是否存在
if [ ! -d "$PROJECT_PATH" ]; then
  log_error "项目目录不存在：${PROJECT_PATH}"
  log_info "请先运行 init-project.sh 初始化项目工作台"
  exit 1
fi

# 读取 .review-workspace.json 配置（如果存在）
CONFIG_FILE="${PROJECT_PATH}/.review-workspace.json"
if [ -f "$CONFIG_FILE" ]; then
  log_info "读取配置：${CONFIG_FILE}"
  ARCHITECT_FILENAME=$(grep -o '"architect": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
  REVIEWER_FILENAME=$(grep -o '"reviewer": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
  SESSION_ARCH=$(grep -o '"architect": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
  SESSION_REV=$(grep -o '"reviewer": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
else
  # 回退：自动检测提示词文件
  log_warn "未找到 .review-workspace.json，自动检测提示词文件..."
  
  # 优先检测无前缀版本，回退到有前缀版本
  if [ -f "${PROJECT_PATH}/ARCHITECT.md" ]; then
    ARCHITECT_FILENAME="ARCHITECT.md"
  else
    ARCHITECT_FILENAME=$(ls "${PROJECT_PATH}"/ARCHITECT_*.md 2>/dev/null | head -1 | xargs basename)
  fi
  
  if [ -f "${PROJECT_PATH}/REVIEWER.md" ]; then
    REVIEWER_FILENAME="REVIEWER.md"
  else
    REVIEWER_FILENAME=$(ls "${PROJECT_PATH}"/REVIEWER_*.md 2>/dev/null | head -1 | xargs basename)
  fi
  
  # Session 名从文件名推断（去掉 ARCHITECT_/REVIEWER_ 前缀和 .md 后缀）
  SESSION_ARCH=$(echo "${PROJECT_NAME}-architect" | tr '[:upper:]' '[:lower:]')
  SESSION_REV=$(echo "${PROJECT_NAME}-reviewer" | tr '[:upper:]' '[:lower:]')
fi

# Session 名称（小写）
SESSION_ARCH=$(echo "${SESSION_ARCH}" | tr '[:upper:]' '[:lower:]')
SESSION_REV=$(echo "${SESSION_REV}" | tr '[:upper:]' '[:lower:]')

# 提示词文件
ARCHITECT_PROMPT="${PROJECT_PATH}/${ARCHITECT_FILENAME}"
REVIEWER_PROMPT="${PROJECT_PATH}/${REVIEWER_FILENAME}"

log_info "项目路径：${PROJECT_PATH}"
log_info "Architect 提示词：${ARCHITECT_FILENAME}"
log_info "Reviewer 提示词：${REVIEWER_FILENAME}"
log_info "启动模式：${MODE}"

# 启动 Architect Session
start_architect() {
  log_step "启动 Architect Session: ${SESSION_ARCH}"
  
  # 检查提示词文件
  if [ ! -f "$ARCHITECT_PROMPT" ]; then
    log_warn "Architect 提示词文件不存在：${ARCHITECT_PROMPT}"
    log_info "将使用默认提示词"
  fi
  
  if [ "$NO_TMUX" = true ]; then
    # --no-tmux 模式：只输出 openclaw 命令
    echo ""
    log_info "Architect Session 命令:"
    echo "  tmux new-window -n ${PROJECT_NAME}-Arch"
    echo "  openclaw tui --session ${SESSION_ARCH}"
    echo ""
    if [ -f "$ARCHITECT_PROMPT" ]; then
      echo "提示词文件已准备：${ARCHITECT_PROMPT}"
    fi
  else
    # tmux 模式
    if tmux has-session -t "${SESSION_ARCH}" 2>/dev/null; then
      log_info "Architect Session 已存在，连接到现有会话..."
      tmux attach-session -t "${SESSION_ARCH}"
    else
      log_info "创建新的 Architect Session..."
      tmux new-session -d -s "${SESSION_ARCH}" -c "${PROJECT_PATH}"
      
      tmux send-keys -t "${SESSION_ARCH}" "echo '🦊 DevMate | Architect Session 已启动'" Enter
      tmux send-keys -t "${SESSION_ARCH}" "echo '项目：${PROJECT_NAME}'" Enter
      tmux send-keys -t "${SESSION_ARCH}" "echo '工作区：${PROJECT_PATH}'" Enter
      tmux send-keys -t "${SESSION_ARCH}" "echo ''" Enter
      
      if [ -f "$ARCHITECT_PROMPT" ]; then
        tmux send-keys -t "${SESSION_ARCH}" "echo '提示词文件：${ARCHITECT_PROMPT}'" Enter
        tmux send-keys -t "${SESSION_ARCH}" "cat '${ARCHITECT_PROMPT}'" Enter
      else
        tmux send-keys -t "${SESSION_ARCH}" "echo '⚠️  提示词文件不存在，请先运行 init-project.sh'" Enter
      fi
      
      tmux send-keys -t "${SESSION_ARCH}" "echo ''" Enter
      tmux send-keys -t "${SESSION_ARCH}" "echo '输出目录：${PROJECT_PATH}/designs/'" Enter
      tmux send-keys -t "${SESSION_ARCH}" "ls -la designs/" Enter
      
      tmux attach-session -t "${SESSION_ARCH}"
    fi
  fi
  
  log_success "Architect Session 就绪"
}

# 启动 Reviewer Session
start_reviewer() {
  log_step "启动 Reviewer Session: ${SESSION_REV}"
  
  if [ ! -f "$REVIEWER_PROMPT" ]; then
    log_warn "Reviewer 提示词文件不存在：${REVIEWER_PROMPT}"
  fi
  
  if [ "$NO_TMUX" = true ]; then
    echo ""
    log_info "Reviewer Session 命令:"
    echo "  tmux new-window -n ${PROJECT_NAME}-Rev"
    echo "  openclaw tui --session ${SESSION_REV}"
    echo ""
    if [ -f "$REVIEWER_PROMPT" ]; then
      echo "提示词文件已准备：${REVIEWER_PROMPT}"
    fi
  else
    if tmux has-session -t "${SESSION_REV}" 2>/dev/null; then
      log_info "Reviewer Session 已存在，连接到现有会话..."
      tmux attach-session -t "${SESSION_REV}"
    else
      log_info "创建新的 Reviewer Session..."
      tmux new-session -d -s "${SESSION_REV}" -c "${PROJECT_PATH}"
      
      tmux send-keys -t "${SESSION_REV}" "echo '🦊 DevMate | Reviewer Session 已启动'" Enter
      tmux send-keys -t "${SESSION_REV}" "echo '项目：${PROJECT_NAME}'" Enter
      tmux send-keys -t "${SESSION_REV}" "echo '工作区：${PROJECT_PATH}'" Enter
      tmux send-keys -t "${SESSION_REV}" "echo ''" Enter
      
      if [ -f "$REVIEWER_PROMPT" ]; then
        tmux send-keys -t "${SESSION_REV}" "echo '提示词文件：${REVIEWER_PROMPT}'" Enter
        tmux send-keys -t "${SESSION_REV}" "cat '${REVIEWER_PROMPT}'" Enter
      else
        tmux send-keys -t "${SESSION_REV}" "echo '⚠️  提示词文件不存在，请先运行 init-project.sh'" Enter
      fi
      
      tmux send-keys -t "${SESSION_REV}" "echo ''" Enter
      tmux send-keys -t "${SESSION_REV}" "echo '评审目录：${PROJECT_PATH}/designs/'" Enter
      tmux send-keys -t "${SESSION_REV}" "echo '输出目录：${PROJECT_PATH}/reviews/'" Enter
      tmux send-keys -t "${SESSION_REV}" "ls -la designs/" Enter
      tmux send-keys -t "${SESSION_REV}" "ls -la reviews/" Enter
      
      tmux attach-session -t "${SESSION_REV}"
    fi
  fi
  
  log_success "Reviewer Session 就绪"
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
    if [ "$NO_TMUX" = true ]; then
      # --no-tmux 模式：输出两个命令
      start_architect
      start_reviewer
      echo ""
      log_info "💡 提示：你可以手动在 tmux 中执行上述命令"
    else
      # tmux 模式：Architect 后台，Reviewer 前台
      log_info "启动 Architect Session（后台）..."
      if ! tmux has-session -t "${SESSION_ARCH}" 2>/dev/null; then
        tmux new-session -d -s "${SESSION_ARCH}" -c "${PROJECT_PATH}"
        tmux send-keys -t "${SESSION_ARCH}" "echo '🦊 Architect Session 已启动'" Enter
        tmux send-keys -t "${SESSION_ARCH}" "echo '提示词：${ARCHITECT_PROMPT}'" Enter
        if [ -f "$ARCHITECT_PROMPT" ]; then
          tmux send-keys -t "${SESSION_ARCH}" "cat '${ARCHITECT_PROMPT}'" Enter
        fi
        log_success "Architect Session 已在后台启动"
      else
        log_info "Architect Session 已存在"
      fi
      
      start_reviewer
    fi
    ;;
esac

if [ "$NO_TMUX" = false ]; then
  echo ""
  log_success "=========================================="
  log_success "Session 启动完成！"
  log_success "=========================================="
  echo ""
  echo "快速命令:"
  echo "  连接 Architect:  tmux attach -t ${SESSION_ARCH}"
  echo "  连接 Reviewer:   tmux attach -t ${SESSION_REV}"
  echo "  查看会话列表：tmux list-sessions"
  echo "  关闭会话：tmux kill-session -t <会话名>"
  echo ""
fi

log_info "🦊 DevMate | 工作台就绪 --"
