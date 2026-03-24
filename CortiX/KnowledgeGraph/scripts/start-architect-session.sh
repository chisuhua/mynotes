#!/bin/bash
# 启动 KnowledgeGraph Architect Session（简化版）
# 推荐使用 start-all-sessions.sh --mode architect

SESSION_NAME="knowledgegraph-architect"
WORKSPACE="/workspace/mynotes/CortiX/KnowledgeGraph"

echo "启动 KnowledgeGraph Architect Session..."
echo "Session 名：${SESSION_NAME}"

# 创建 tmux 窗口并启动 openclaw
if ! tmux list-windows -F "#W" 2>/dev/null | grep -q "^KnowledgeGraph-Arch$"; then
  tmux new-window -n "KnowledgeGraph-Arch" -c "${WORKSPACE}"
  tmux send-keys -t "KnowledgeGraph-Arch" "openclaw tui --session ${SESSION_NAME}" Enter
  echo "✅ Architect Session 已启动在 tmux 窗口：KnowledgeGraph-Arch"
else
  echo "ℹ️  窗口已存在，连接到现有窗口..."
  tmux select-window -t "KnowledgeGraph-Arch"
fi
