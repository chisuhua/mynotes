#!/bin/bash
# 启动 KnowledgeGraph Reviewer Session（简化版）
# 推荐使用 start-all-sessions.sh --mode reviewer

SESSION_NAME="knowledgegraph-reviewer"
WORKSPACE="/workspace/mynotes/CortiX/KnowledgeGraph"

echo "启动 KnowledgeGraph Reviewer Session..."
echo "Session 名：${SESSION_NAME}"

# 创建 tmux 窗口并启动 openclaw
if ! tmux list-windows -F "#W" 2>/dev/null | grep -q "^KnowledgeGraph-Rev$"; then
  tmux new-window -n "KnowledgeGraph-Rev" -c "${WORKSPACE}"
  tmux send-keys -t "KnowledgeGraph-Rev" "openclaw tui --session ${SESSION_NAME}" Enter
  echo "✅ Reviewer Session 已启动在 tmux 窗口：KnowledgeGraph-Rev"
else
  echo "ℹ️  窗口已存在，连接到现有窗口..."
  tmux select-window -t "KnowledgeGraph-Rev"
fi
