# PDF 解析流程

**来源**: 从 `../文献预处理.md` 提炼  
**最后更新**: 2026-03-23  
**状态**: 架构评审中

---

## 🎯 解析目标

从 PDF 文献中提取：
1. **文本** — 正文、摘要、参考文献（支持双栏论文）
2. **表格** — 跨页表格、复杂格式表格
3. **图表** — Figure 图片 + 多模态描述
4. **公式** — LaTeX 格式输出
5. **元数据** — 标题、作者、DOI、年份、机构

---

## 🏗️ 解析架构

```
PDF → 文本提取 → 表格提取 → 图表提取 → 公式识别 → 结构化输出
       ↓            ↓            ↓            ↓
    PyMuPDF     Camelot      Qwen-VL     Pix2Tex/Nougat
    Grobid      LLM 视觉      LLM 描述
```

---

## 🔧 工具选型

### 文本提取

| 工具 | 优势 | 劣势 | 适用场景 |
|---|---|---|---|
| **PyMuPDF** | 快速、准确、支持双栏 | 公式识别弱 | 通用 PDF |
| **Grobid** | 学术 PDF 专用、结构识别强 | 需独立部署 | 学术论文 |
| **pdfplumber** | 表格友好、布局保留 | 速度较慢 | 含复杂表格的 PDF |

**推荐**: PyMuPDF（轻量）或 Grobid（高精度）

### 表格提取

| 工具 | 优势 | 劣势 | 适用场景 |
|---|---|---|---|
| **Camelot** | 准确、支持 LaTeX/CSV 输出 | 对扫描版 PDF 无效 | 原生 PDF 表格 |
| **Tabula** | 简单易用 | 跨页表格支持弱 | 简单表格 |
| **LLM 视觉提取** | 支持扫描版、复杂格式 | 成本高、速度慢 | 复杂/跨页表格 |

**推荐**: Camelot（原生 PDF）+ LLM 视觉（复杂表格兜底）

### 图表提取

| 工具 | 优势 | 劣势 | 适用场景 |
|---|---|---|---|
| **Qwen-VL** | 多模态理解、生成描述 | 需 API 调用 | 图表理解 |
| **规则检测** | 快速、无需外部 API | 准确率有限 | 简单图表 |
| **LLaVA** | 开源、可本地部署 | 效果略逊于 Qwen-VL | 本地部署场景 |

**推荐**: Qwen-VL（图表描述生成）

### 公式识别

| 工具 | 优势 | 劣势 | 适用场景 |
|---|---|---|---|
| **Pix2Tex** | 开源、可本地部署 | 复杂公式识别率一般 | 通用公式 |
| **Nougat** | 准确率高、支持复杂公式 | 模型较大、速度慢 | 高精度需求 |
| **Mathpix API** | 准确率最高 | 付费、有调用限制 | 关键公式 |

**推荐**: Pix2Tex（通用）或 Nougat（高精度）

---

## 📋 解析流程详解

### 阶段 1: 文本提取

```typescript
// tools/pdf-extract.ts
async function pdfExtract(pdfPath: string): Promise<ExtractResult> {
  // 1. 使用 PyMuPDF 提取文本
  const text = await pymupdf.extract(pdfPath, {
    layout: 'double_column',  // 支持双栏
    preserve_formatting: true
  });
  
  // 2. 提取元数据
  const metadata = await extractMetadata(pdfPath);
  
  // 3. 分割段落
  const paragraphs = splitParagraphs(text);
  
  return { text, metadata, paragraphs };
}
```

### 阶段 2: 表格提取

```typescript
// tools/table-extract.ts
async function tableExtract(pdfPath: string, pageNumbers: number[]): Promise<TableResult[]> {
  const tables = [];
  
  for (const pageNum of pageNumbers) {
    // 1. 尝试 Camelot 提取
    const camelotTables = await camelot.extract(pdfPath, pageNum);
    
    if (camelotTables.length > 0) {
      tables.push(...camelotTables);
    } else {
      // 2. Camelot 失败，使用 LLM 视觉提取兜底
      const llmTables = await llmVisionExtract(pdfPath, pageNum);
      tables.push(...llmTables);
    }
  }
  
  return tables;
}
```

### 阶段 3: 图表提取

```typescript
// tools/figure-extract.ts
async function figureExtract(pdfPath: string, pageNumbers: number[]): Promise<FigureResult[]> {
  const figures = [];
  
  for (const pageNum of pageNumbers) {
    // 1. 提取图片
    const images = await extractImages(pdfPath, pageNum);
    
    // 2. 使用 Qwen-VL 生成描述
    for (const img of images) {
      const description = await qwenVL.describe(img);
      figures.push({ image: img, description, page: pageNum });
    }
  }
  
  return figures;
}
```

### 阶段 4: 公式识别

```typescript
// tools/formula-extract.ts
async function formulaExtract(pdfPath: string): Promise<FormulaResult[]> {
  // 1. 定位公式区域（基于布局分析）
  const formulaRegions = await locateFormulas(pdfPath);
  
  // 2. 使用 Pix2Tex 识别为 LaTeX
  const formulas = [];
  for (const region of formulaRegions) {
    const latex = await pix2tex.recognize(region.image);
    formulas.push({ latex, page: region.page, bbox: region.bbox });
  }
  
  return formulas;
}
```

---

## 📤 输出格式

### 结构化输出 (JSON)

```json
{
  "metadata": {
    "title": "Paper Title",
    "authors": ["Author1", "Author2"],
    "year": 2024,
    "doi": "10.1000/paper1",
    "venue": "Conference Name"
  },
  "text": {
    "abstract": "...",
    "sections": [
      {
        "title": "Introduction",
        "content": "..."
      }
    ],
    "references": [...]
  },
  "tables": [
    {
      "table_id": "Table 1",
      "caption": "SOTA Comparison",
      "page": 3,
      "data_json": [["Method", "Accuracy"], ["Ours", "89.5"], ["Baseline", "87.2"]]
    }
  ],
  "figures": [
    {
      "figure_id": "Figure 1",
      "caption": "Model Architecture",
      "page": 2,
      "image_url": "/images/paper1_fig1.png",
      "description": "The model consists of..."
    }
  ],
  "formulas": [
    {
      "formula_id": "Eq 1",
      "page": 4,
      "latex": "\\mathcal{L} = -\\sum y \\log(\\hat{y})"
    }
  ]
}
```

### Markdown 输出

```markdown
---
title: Paper Title
authors: [Author1, Author2]
year: 2024
doi: 10.1000/paper1
venue: Conference Name
---

## Abstract

...

## Introduction

...

## Tables

### Table 1: SOTA Comparison

| Method | Accuracy |
|--------|----------|
| Ours   | 89.5     |
| Baseline | 87.2   |

## Figures

### Figure 1: Model Architecture

![Model Architecture](/images/paper1_fig1.png)

The model consists of...

## Formulas

$$ \mathcal{L} = -\sum y \log(\hat{y}) $$
```

---

## ⚠️ 常见问题与处理

| 问题 | 原因 | 缓解措施 |
|---|---|---|
| 双栏文本错乱 | 布局分析失败 | 使用 Grobid 或增加布局检测逻辑 |
| 表格跨页断裂 | 未检测跨页关系 | 增加跨页表格合并逻辑 |
| 公式识别错误 | 复杂公式结构 | 使用 Nougat 或人工校正 |
| 图表描述不准确 | 多模态理解偏差 | Few-Shot 示例增强，Prompt 迭代 |

---

## 📊 解析质量评估

| 指标 | 目标值 | 评估方法 |
|---|---|---|
| 文本提取准确率 | > 95% | 人工抽检 |
| 表格提取完整率 | > 90% | 对比原 PDF |
| 图表描述准确率 | > 80% | 人工抽检 |
| 公式识别准确率 | > 85% | 对比原 PDF |

---

## 📝 文档变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-03-23 | 从原文档提炼 | 精简核心 PDF 解析流程 |

`// -- 🦊 DevMate | PDF 解析流程提炼完成 --`
