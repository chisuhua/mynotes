#!/bin/bash
# archive-designs.sh — 归档评审通过的设计文档
# 用法：./archive-designs.sh --design <文档名> --target <目标目录>

set -e

PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESIGNS_DIR="${PROJECT_PATH}/designs"
REVIEWS_DIR="${PROJECT_PATH}/reviews"
ARCHIVE_DIR="${PROJECT_PATH}/archive"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

DESIGN_NAME=""
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --design)
      DESIGN_NAME="$2"
      shift 2
      ;;
    --target)
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "用法：$0 --design <文档名> --target <目标目录>"
      echo ""
      echo "参数:"
      echo "  --design   设计文档名（不含日期前缀，如 'Schema 设计.md'）"
      echo "  --target   目标目录（相对路径，如 '../02-知识图谱构建/'）"
      exit 0
      ;;
    *)
      log_error "未知参数：$1"
      exit 1
      ;;
  esac
done

if [ -z "$DESIGN_NAME" ] || [ -z "$TARGET_DIR" ]; then
  log_error "必须指定 --design 和 --target 参数"
  exit 1
fi

# 查找最新的草稿文件
DRAFT_FILE=$(ls -t "${DESIGNS_DIR}"/????-??-??_"${DESIGN_NAME%.md}".draft.md 2>/dev/null | head -1)
if [ -z "$DRAFT_FILE" ]; then
  log_error "未找到设计草稿：${DESIGN_NAME}"
  exit 1
fi

# 查找对应的评审文件
REVIEW_FILE=$(ls -t "${REVIEWS_DIR}"/????-??-??_"${DESIGN_NAME%.md}".review.md 2>/dev/null | head -1)

log_info "设计文件：${DRAFT_FILE}"
if [ -n "$REVIEW_FILE" ]; then
  log_info "评审文件：${REVIEW_FILE}"
else
  log_warn "未找到评审文件"
fi

# 确认归档
echo ""
log_warn "⚠️  归档确认"
echo "  源文件：${DRAFT_FILE}"
echo "  目标：${TARGET_DIR}/${DESIGN_NAME}"
echo ""
read -p "确认归档？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info "归档已取消"
  exit 0
fi

# 执行归档
TARGET_PATH="${PROJECT_PATH}/${TARGET_DIR}/${DESIGN_NAME}"
mkdir -p "$(dirname "${TARGET_PATH}")"
mv "${DRAFT_FILE}" "${TARGET_PATH}"
log_success "设计文档已归档：${TARGET_PATH}"

# 归档评审文件（如果存在）
if [ -n "$REVIEW_FILE" ]; then
  REVIEW_NAME="${DESIGN_NAME%.md}_评审意见.md"
  REVIEW_TARGET="${ARCHIVE_DIR}/${REVIEW_NAME}"
  mv "${REVIEW_FILE}" "${REVIEW_TARGET}"
  log_success "评审意见已归档：${REVIEW_TARGET}"
fi

# 更新归档日志
ARCHIVE_LOG="${PROJECT_PATH}/archive/归档日志.md"
if [ ! -f "${ARCHIVE_LOG}" ]; then
  cat > "${ARCHIVE_LOG}" << EOF
# 归档日志

| 日期 | 文档 | 操作 | 评审意见 |
|---|---|---|---|
EOF
fi

echo "| $(date +%Y-%m-%d) | ${DESIGN_NAME} | 归档 | $([ -n "$REVIEW_FILE" ] && echo "有" || echo "无") |" >> "${ARCHIVE_LOG}"

log_success "归档完成"
