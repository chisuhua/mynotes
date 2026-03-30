#!/bin/bash
# 电商商品数据分析流水线执行脚本
# 使用方法：bash run-pipeline.sh [--dry-run]

set -e

WORKSPACE=~/.openclaw/ecommerce
DATE=$(date +%Y%m%d)

echo "=========================================="
echo "电商商品数据分析流水线"
echo "日期：$(date)"
echo "=========================================="

# 检查配置文件是否存在
if [ ! -f "$WORKSPACE/config/product_urls.json" ]; then
    echo "❌ 错误：商品 URL 配置文件不存在"
    echo "请创建：$WORKSPACE/config/product_urls.json"
    exit 1
fi

# 阶段 1: 爬取数据
echo ""
echo "📥 阶段 1/4: 爬取淘宝/京东最新数据..."
if [ "$1" == "--dry-run" ]; then
    echo "[DRY-RUN] 将爬取以下 URL:"
    cat "$WORKSPACE/config/product_urls.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print('  Taobao:', len(d.get('taobao',[])), 'urls'); print('  JD:', len(d.get('jd',[])), 'urls')"
else
    python3 "$WORKSPACE/scripts/crawler.py" "$WORKSPACE/config/product_urls.json" "$WORKSPACE/raw_data/$DATE"
    echo "✅ 爬取完成，数据保存到：$WORKSPACE/raw_data/$DATE"
fi

# 阶段 2: 数据去重
echo ""
echo "🔄 阶段 2/4: 数据去重..."
if [ "$1" == "--dry-run" ]; then
    echo "[DRY-RUN] 将执行去重操作"
else
    python3 "$WORKSPACE/scripts/deduplicate.py" "$WORKSPACE/raw_data/$DATE" "$WORKSPACE/analysis_results/cleaned/$DATE"
    echo "✅ 去重完成， cleaned 数据保存到：$WORKSPACE/analysis_results/cleaned/$DATE"
fi

# 阶段 3: AI 分析
echo ""
echo "🤖 阶段 3/4: AI 分析（价格趋势、情感分析、分类标注、竞品对比、异常检测）..."
if [ "$1" == "--dry-run" ]; then
    echo "[DRY-RUN] 将调用以下 Agent:"
    echo "  - price-analyst: 价格趋势 + 异常检测"
    echo "  - sentiment-analyst: 评价情感分析"
    echo "  - classifier-agent: 商品分类标注"
    echo "  - competitor-analyst: 竞品对比"
    echo "  - anomaly-detector: 异常模式识别"
else
    # 调用各专业 Agent 进行分析
    openclaw chat --agent price-analyst "分析 $WORKSPACE/analysis_results/cleaned/$DATE 中的价格数据，输出到 $WORKSPACE/analysis_results/price/$DATE"
    openclaw chat --agent sentiment-analyst "分析 $WORKSPACE/analysis_results/cleaned/$DATE 中的评价数据，输出到 $WORKSPACE/analysis_results/sentiment/$DATE"
    openclaw chat --agent classifier-agent "分类 $WORKSPACE/analysis_results/cleaned/$DATE 中的商品，输出到 $WORKSPACE/analysis_results/classification/$DATE"
    openclaw chat --agent competitor-analyst "对比 $WORKSPACE/analysis_results/cleaned/$DATE 中的竞品数据，输出到 $WORKSPACE/analysis_results/competitor/$DATE"
    openclaw chat --agent anomaly-detector "检测 $WORKSPACE/analysis_results/cleaned/$DATE 中的异常模式，输出到 $WORKSPACE/analysis_results/anomaly/$DATE"
    echo "✅ 分析完成"
fi

# 阶段 4: 生成报告
echo ""
echo "📄 阶段 4/4: 生成每日分析报告..."
if [ "$1" == "--dry-run" ]; then
    echo "[DRY-RUN] 将生成报告：$WORKSPACE/reports/daily_$DATE.md"
else
    openclaw chat --agent report-generator "
      读取 $WORKSPACE/analysis_results/ 中的所有分析结果，
      生成每日分析报告，
      输出到 $WORKSPACE/reports/daily_$DATE.md
    "
    echo "✅ 报告生成完成：$WORKSPACE/reports/daily_$DATE.md"
fi

echo ""
echo "=========================================="
echo "✅ 流水线执行完成！"
echo "=========================================="
echo ""
echo "查看报告：cat $WORKSPACE/reports/daily_$DATE.md"
