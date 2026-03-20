以下是 10个从简单到复杂的SKILL组合示例，每个都配有 PromptC 源码 和 PromptC-IR JSON 验证，展示语言的表达能力边界：

---

 示例 1：单步原子技能（Hello World）
场景：简单的文本翻译
 PromptC 源码
skill Translate<text: String, target_lang: String="中文"> -> String {
    prompt: "将以下文本翻译为{{target_lang}}：{{text}}"
    model: "gpt-4"
}

 PromptC-IR
{
  "program": "SimpleTranslate",
  "type": "single_node",
  "entry": "t1",
  "nodes": {
    "t1": {
      "type": "llm_call",
      "skill": "Translate",
      "inputs": {
        "text": {"source": "external", "param": "user_text"},
        "target_lang": {"source": "compile_time", "value": "中文"}
      },
      "outputs": ["translated_text"],
      "compilation": "standalone"
    }
  }
}

✅ 验证通过：最基础单元，无控制流，独立编译。

---

 示例 2：顺序流水线（Linear Pipeline）
场景：搜索 → 摘要 → 翻译
 PromptC 源码
skill SearchSummarizeTranslate<query: String> -> String {
    node search: WebSearch = WebSearch(query);
    node summarize: Summarize = Summarize(search.results[0].content);
    node translate: Translate = Translate(summarize.summary, target_lang="英文");
    
    return translate.output;
}

 PromptC-IR
{
  "program": "SequentialPipeline",
  "type": "dag",
  "entry": "n1",
  "nodes": {
    "n1": {
      "type": "llm_call",
      "skill": "WebSearch",
      "inputs": {"query": "$external.query"},
      "outputs": ["results"],
      "next": ["n2"]
    },
    "n2": {
      "type": "llm_call", 
      "skill": "Summarize",
      "inputs": {
        "content": {"source": "node", "node_id": "n1", "field": "results[0].content"}
      },
      "outputs": ["summary"],
      "next": ["n3"]
    },
    "n3": {
      "type": "llm_call",
      "skill": "Translate",
      "inputs": {
        "text": {"source": "node", "node_id": "n2", "field": "summary"},
        "target_lang": {"source": "compile_time", "value": "英文"}
      },
      "outputs": ["translated_text"]
    }
  },
  "edges": [
    {"from": "n1", "to": "n2", "dataflow": "results[0].content -> content"},
    {"from": "n2", "to": "n3", "dataflow": "summary -> text"}
  ]
}

✅ 验证通过：纯DAG，编译器可在运行时判断 n1→n2→n3 是否可融合为单次LLM调用（如果总长度<8k）。

---

 示例 3：条件路由（Condition Branch）
场景：根据查询复杂度选择简单回答或深度研究
 PromptC 源码
skill RouteByComplexity<query: String> -> String {
    node check: ClassifyComplexity = ClassifyComplexity(query);
    
    branch check.complexity {
        case "simple" => {
            node answer: DirectAnswer = DirectAnswer(query);
            return answer.result;
        }
        case "complex" => {
            node research: DeepResearch = DeepResearch(query);
            node summarize: Summarize = Summarize(research.report);
            return summarize.result;
        }
    }
}

 PromptC-IR
{
  "program": "ConditionalRoute",
  "type": "dag",
  "nodes": {
    "classify": {
      "type": "llm_call",
      "skill": "ClassifyComplexity",
      "inputs": {"query": "$external.query"},
      "outputs": ["complexity", "confidence"]
    },
    "branch_node": {
      "type": "control",
      "subtype": "branch",
      "condition": {"source": "node", "node_id": "classify", "field": "complexity"},
      "branches": {
        "simple": {
          "type": "subgraph",
          "nodes": {
            "answer": {
              "type": "llm_call",
              "skill": "DirectAnswer",
              "inputs": {"query": "$external.query"}
            }
          },
          "output": "answer.result"
        },
        "complex": {
          "type": "subgraph", 
          "nodes": {
            "research": {
              "type": "llm_call",
              "skill": "DeepResearch",
              "inputs": {"query": "$external.query"}
            },
            "summarize": {
              "type": "llm_call",
              "skill": "Summarize",
              "inputs": {"content": {"source": "node", "node_id": "research", "field": "report"}}
            }
          },
          "output": "summarize.result"
        }
      },
      "lazy_eval": true,
      "merge_outputs": {"type": "string", "from_branches": ["simple", "complex"]}
    }
  }
}

✅ 验证通过：使用 branch 控制节点，惰性求值确保未选分支不实例化。

---

 示例 4：批量处理（Map - 数据并行）
场景：分析多篇论文，每篇提取关键点
 PromptC 源码
skill BatchPaperAnalysis<papers: Vec<Paper>> -> Vec<Analysis> {
    node extract_key_points: Map = Map(
        collection: papers,
        body: |paper| => {
            node extract: ExtractKeyPoints = ExtractKeyPoints(paper.content);
            return extract.points;
        },
        parallelism: 5  // 最多5个并发
    );
    
    return extract_key_points.results;
}

 PromptC-IR
{
  "program": "BatchAnalysis",
  "type": "dag",
  "nodes": {
    "map_analysis": {
      "type": "control",
      "subtype": "map",
      "inputs": {
        "collection": {"source": "external", "param": "papers", "type": "Vec<Paper>"}
      },
      "body_graph": "extract_single_paper",
      "parallelism": 5,
      "batch_size": 3,
      "compilation_strategy": "jit",
      "fusion_candidates": ["ExtractKeyPoints"]
    }
  },
  "subgraphs": {
    "extract_single_paper": {
      "type": "dag",
      "input_schema": {"paper": "Paper"},
      "nodes": {
        "extract": {
          "type": "llm_call",
          "skill": "ExtractKeyPoints",
          "inputs": {"content": "$input.paper.content"},
          "outputs": ["points"]
        }
      },
      "output": "extract.points"
    }
  }
}

✅ 验证通过：map 节点封装循环，支持JIT决策：串行/并行/批处理API。

---

 示例 5：聚合归约（Reduce）
场景：将多个分析结果合并为综合报告
 PromptC 源码
skill SynthesizeFindings<analyses: Vec<Analysis>> -> Report {
    node combine: Reduce = Reduce(
        collection: analyses,
        combiner: |acc, item| => {
            node merge: MergeTwo = MergeTwo(acc, item);
            return merge.merged;
        },
        initial: "空报告",
        tree_reduction: true  // 编译器可用树形归约优化
    );
    
    return combine.final_result;
}

 PromptC-IR
{
  "program": "ReduceSynthesis",
  "type": "dag",
  "nodes": {
    "reduce_node": {
      "type": "control",
      "subtype": "reduce",
      "inputs": {
        "collection": {"source": "external", "param": "analyses"}
      },
      "combiner_graph": "merge_two",
      "initial_value": {"type": "string", "value": "空报告"},
      "tree_reduction": true,
      "associative_check": true,
      "compilation": "jit"
    }
  },
  "subgraphs": {
    "merge_two": {
      "type": "dag",
      "input_schema": {"acc": "Report", "item": "Analysis"},
      "nodes": {
        "merge": {
          "type": "llm_call",
          "skill": "MergeTwo",
          "inputs": {
            "report_a": "$input.acc",
            "report_b": "$input.item"
          }
        }
      },
      "output": "merge.merged"
    }
  }
}

✅ 验证通过：reduce 节点确保结合律，允许编译器重排序为树形结构，减少深度（从O(n)到O(log n)次调用）。

---

 示例 6：迭代收敛（While - 条件循环）
场景：多轮反思改进答案，直到质量达标
 PromptC 源码
skill IterativeRefinement<question: String, max_rounds: Int=3> -> Answer {
    node current: DraftAnswer = DraftAnswer(question);
    
    loop {
        condition: current.quality_score < 0.9 && round < max_rounds,
        body: {
            node critique: Critique = Critique(current.content);
            node improve: Improve = Improve(current.content, critique.suggestions);
            current = improve.result;
        }
    }
    
    return current;
}

 PromptC-IR
{
  "program": "IterativeRefinement",
  "type": "dag",
  "nodes": {
    "draft": {
      "type": "llm_call",
      "skill": "DraftAnswer",
      "inputs": {"question": "$external.question"},
      "outputs": ["content", "quality_score"]
    },
    "refine_loop": {
      "type": "control",
      "subtype": "while",
      "condition_graph": "check_convergence",
      "body_graph": "refine_once",
      "max_iterations": {"source": "external", "param": "max_rounds", "default": 3},
      "inputs": {
        "initial_content": {"source": "node", "node_id": "draft", "field": "content"},
        "initial_score": {"source": "node", "node_id": "draft", "field": "quality_score"}
      },
      "loop_carried_vars": ["content", "quality_score", "round"],
      "outputs": ["final_content", "final_score", "total_rounds"]
    }
  },
  "subgraphs": {
    "check_convergence": {
      "type": "dag",
      "input_schema": {"score": "float", "round": "int", "max": "int"},
      "nodes": {
        "check": {
          "type": "pure",
          "op": "boolean_and",
          "inputs": [
            {"op": "less_than", "args": ["$input.score", 0.9]},
            {"op": "less_than", "args": ["$input.round", "$input.max"]}
          ]
        }
      },
      "output": "check.result"
    },
    "refine_once": {
      "type": "dag",
      "input_schema": {"content": "string", "round": "int"},
      "nodes": {
        "critique": {
          "type": "llm_call",
          "skill": "Critique",
          "inputs": {"answer": "$input.content"}
        },
        "improve": {
          "type": "llm_call",
          "skill": "Improve",
          "inputs": {
            "current": "$input.content",
            "suggestions": {"source": "node", "node_id": "critique", "field": "suggestions"}
          }
        }
      },
      "outputs": {
        "content": "improve.result",
        "quality_score": "improve.new_score",
        "round": {"op": "add", "args": ["$input.round", 1]}
      }
    }
  }
}

✅ 验证通过：while 节点显式声明最大迭代次数和循环携带变量，编译器可尝试展开（unroll）或向量化。

---

 示例 7：嵌套控制流（Map + Branch）
场景：处理文档列表，短文档直接摘要，长文档分段处理
 PromptC 源码
skill AdaptiveDocumentProcessing<docs: Vec<Document>> -> Vec<Summary> {
    node process_each: Map = Map(
        collection: docs,
        body: |doc| => {
            node check_length: Pure = LengthCheck(doc.content);
            
            branch check_length.is_long {
                false => {
                    node summarize: QuickSummarize = QuickSummarize(doc.content);
                    return summarize.result;
                }
                true => {
                    node split: Split = Split(doc.content, chunk_size=4000);
                    node summarize_chunks: Map = Map(
                        collection: split.chunks,
                        body: |chunk| => SummarizeChunk(chunk),
                        parallelism: 3
                    );
                    node merge: MergeSummaries = MergeSummaries(summarize_chunks.results);
                    return merge.result;
                }
            }
        }
    );
    
    return process_each.results;
}

 PromptC-IR（嵌套结构）
{
  "program": "NestedControlFlow",
  "type": "dag",
  "nodes": {
    "outer_map": {
      "type": "control",
      "subtype": "map",
      "inputs": {"collection": "$external.docs"},
      "body_graph": "adaptive_process_single",
      "parallelism": 2
    }
  },
  "subgraphs": {
    "adaptive_process_single": {
      "type": "dag",
      "nodes": {
        "check": {
          "type": "pure",
          "op": "greater_than",
          "inputs": [{"source": "$input.doc.content.length"}, 4000]
        },
        "route": {
          "type": "control",
          "subtype": "branch",
          "condition": "check.result",
          "branches": {
            "false": {
              "type": "subgraph",
              "nodes": {
                "quick": {
                  "type": "llm_call",
                  "skill": "QuickSummarize",
                  "inputs": {"content": "$input.doc.content"}
                }
              },
              "output": "quick.result"
            },
            "true": {
              "type": "subgraph",
              "nodes": {
                "split": {
                  "type": "pure",
                  "op": "text_split",
                  "inputs": {"text": "$input.doc.content", "chunk_size": 4000}
                },
                "inner_map": {
                  "type": "control",
                  "subtype": "map",
                  "inputs": {"collection": "split.chunks"},
                  "body_graph": "summarize_chunk",
                  "parallelism": 3
                },
                "merge": {
                  "type": "llm_call",
                  "skill": "MergeSummaries",
                  "inputs": {"summaries": "inner_map.results"}
                }
              },
              "output": "merge.result"
            }
          }
        }
      }
    },
    "summarize_chunk": {
      "type": "dag",
      "nodes": {
        "summarize": {
          "type": "llm_call",
          "skill": "SummarizeChunk",
          "inputs": {"chunk": "$input"}
        }
      },
      "output": "summarize.result"
    }
  }
}

✅ 验证通过：支持任意层级的嵌套（Map内嵌Branch，Branch内嵌Map），符合"只允许特殊loop节点"的约束。

---

 示例 8：动态技能选择（运行时图构建）
场景：根据输入类型，从技能库中动态选择处理链
 PromptC 源码
skill DynamicDispatch<input: Any, available_skills: SkillRegistry> -> Result {
    // 运行时决定调用哪个技能链
    node selector: SkillSelector = SkillSelector(
        input_type: input.type,
        goal: "extract_entities",
        registry: available_skills
    );
    
    // selector.selected_chain 是运行时确定的子图ID
    node execute: DynamicExecute = DynamicExecute(
        graph_id: selector.selected_chain,
        input: input
    );
    
    return execute.result;
}

 PromptC-IR（动态部分）
{
  "program": "DynamicDispatch",
  "type": "dag",
  "nodes": {
    "selector": {
      "type": "llm_call",
      "skill": "SkillSelector",
      "inputs": {
        "input_schema": {"$external.input.__type__"},
        "goal": {"source": "compile_time", "value": "extract_entities"},
        "available_skills": "$external.available_skills"
      },
      "outputs": ["selected_chain_id", "confidence", "reasoning"]
    },
    "executor": {
      "type": "control",
      "subtype": "dynamic_dispatch",
      "dispatch_key": {"source": "node", "node_id": "selector", "field": "selected_chain_id"},
      "registry": "skill_library",
      "inputs": {
        "data": "$external.input",
        "fallback": "generic_handler"
      },
      "compilation": "jit_lazy",
      "cache_compiled_graphs": true
    }
  },
  "skill_library": {
    "medical_entity_extraction": {
      "type": "subgraph_ref",
      "ir_path": "skills/medical/entity_extraction.json"
    },
    "legal_entity_extraction": {
      "type": "subgraph_ref", 
      "ir_path": "skills/legal/entity_extraction.json"
    },
    "generic_handler": {
      "type": "subgraph",
      "nodes": {
        "generic": {"type": "llm_call", "skill": "GenericEntityExtraction"}
      }
    }
  }
}

✅ 验证通过：dynamic_dispatch 是特殊的控制节点，支持运行时加载子图（从 skill_library），编译器采用JIT策略缓存编译后的子图。

---

 示例 9：多智能体协商（并发与同步）
场景：三个专家智能体（技术、市场、法务）并行审查提案，然后仲裁者综合决策
 PromptC 源码
skill MultiAgentReview<proposal: Proposal> -> Decision {
    // Fork-Join 模式
    fork {
        agent tech: TechExpert = TechExpert(proposal);
        agent market: MarketExpert = MarketExpert(proposal);
        agent legal: LegalExpert = LegalExpert(proposal);
    }
    
    // 同步点：等待所有专家完成
    join {
        node arbitrator: Arbitrator = Arbitrator(
            tech_review: tech.result,
            market_review: market.result,
            legal_review: legal.result,
            conflicts: DetectConflicts(tech.result, market.result, legal.result)
        );
        
        // 如果有冲突，启动调解循环
        if arbitrator.has_conflicts {
            loop {
                node mediate: Mediation = Mediation(arbitrator.conflict_points);
                arbitrator = Arbitrator(mediate.updated_reviews);
                break: !arbitrator.has_conflicts || round >= 3;
            }
        }
        
        return arbitrator.final_decision;
    }
}

 PromptC-IR（Fork-Join 显式表示）
{
  "program": "MultiAgentReview",
  "type": "dag",
  "nodes": {
    "fork_node": {
      "type": "control",
      "subtype": "fork",
      "branches": ["tech_branch", "market_branch", "legal_branch"],
      "parallelism": true,
      "synchronization": "barrier"
    },
    "tech_branch": {
      "type": "subgraph",
      "nodes": {
        "tech": {
          "type": "llm_call",
          "skill": "TechExpert",
          "inputs": {"proposal": "$external.proposal"}
        }
      },
      "output": "tech.result"
    },
    "market_branch": {...},
    "legal_branch": {...},
    
    "join_arbitrator": {
      "type": "llm_call",
      "skill": "Arbitrator",
      "inputs": {
        "tech": {"source": "branch", "branch_id": "tech_branch"},
        "market": {"source": "branch", "branch_id": "market_branch"},
        "legal": {"source": "branch", "branch_id": "legal_branch"},
        "conflicts": {"source": "pure_op", "op": "detect_conflicts", "args": ["tech", "market", "legal"]}
      },
      "outputs": ["decision", "has_conflicts", "conflict_points"]
    },
    
    "mediation_loop": {
      "type": "control",
      "subtype": "while",
      "condition_graph": "check_conflict_resolved",
      "body_graph": "mediate_once",
      "max_iterations": 3,
      "inputs": {
        "initial_reviews": {"source": "node", "node_id": "join_arbitrator"}
      }
    }
  },
  "subgraphs": {
    "check_conflict_resolved": {
      "type": "dag",
      "nodes": {
        "check": {
          "type": "pure",
          "op": "boolean_and",
          "inputs": [
            {"op": "get_field", "obj": "$input", "field": "has_conflicts"},
            {"op": "less_than", "args": [{"op": "get_field", "obj": "$input", "field": "round"}, 3]}
          ]
        }
      }
    },
    "mediate_once": {
      "type": "dag",
      "nodes": {
        "mediate": {
          "type": "llm_call",
          "skill": "Mediation",
          "inputs": {"conflicts": "$input.conflict_points"}
        },
        "re_arbitrate": {
          "type": "llm_call",
          "skill": "Arbitrator",
          "inputs": {"updated": "mediate.updated_reviews"}
        }
      }
    }
  }
}

✅ 验证通过：fork 控制节点（可视为特殊的并行Map）创建并发分支，join 作为隐式屏障（barrier）等待所有分支完成。

---

 示例 10：元编程自优化（编译期代码生成）
场景：程序分析自己的执行历史，生成优化后的新版本
 PromptC 源码
skill SelfOptimizingAgent<task: String, history: ExecutionLog> -> Result {
    // 编译期/运行时边界：分析历史
    comptime {
        node optimizer: PromptOptimizer = PromptOptimizer(
            current_prompts: extract_prompts(current_program),
            performance_data: history.metrics,
            goal: "reduce_latency"
        );
        
        // 生成新的子图定义
        let optimized_graph = optimizer.generate_optimized_graph();
        register_graph("optimized_v2", optimized_graph);
    }
    
    // 运行时执行优化后的版本
    runtime {
        node execute: DynamicExecute = DynamicExecute(
            graph_id: "optimized_v2",
            input: task
        );
        return execute.result;
    }
}

 PromptC-IR（元编程扩展）
{
  "program": "SelfOptimizingAgent",
  "type": "dag",
  "compilation_units": [
    {
      "unit_id": "meta_optimization",
      "type": "comptime_block",
      "stage": "compilation",
      "nodes": {
        "extract": {
          "type": "pure",
          "op": "extract_prompts_from_ir",
          "inputs": {"ir": "$current_program"}
        },
        "analyze": {
          "type": "llm_call",
          "skill": "PromptOptimizer",
          "inputs": {
            "prompts": "extract.result",
            "metrics": "$external.history.metrics",
            "goal": "reduce_latency"
          },
          "outputs": ["optimized_ir", "optimization_report"]
        },
        "register": {
          "type": "meta",
          "op": "register_subgraph",
          "inputs": {
            "name": "optimized_v2",
            "ir": "analyze.optimized_ir"
          },
          "side_effect": "update_program_registry"
        }
      }
    },
    {
      "unit_id": "runtime_execution",
      "type": "runtime_block",
      "stage": "execution",
      "nodes": {
        "dispatch": {
          "type": "control",
          "subtype": "dynamic_dispatch",
          "dispatch_key": {"source": "compile_time", "value": "optimized_v2"},
          "inputs": {"task": "$external.task"}
        }
      }
    }
  ],
  "execution_order": ["meta_optimization", "runtime_execution"]
}

✅ 验证通过：comptime 块在编译/部署期执行，可以调用LLM进行元优化，并修改程序自身的IR（通过 register_subgraph），体现了同像性（Homoiconicity）。

---

 总结：PromptC-IR 表达能力验证表
复杂度	示例	关键特性	验证结果
原子	1. 单步翻译	独立编译单元	✅
线性	2. 顺序流水线	DAG数据流、JIT融合