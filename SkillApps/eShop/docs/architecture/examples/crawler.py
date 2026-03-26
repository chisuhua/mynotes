#!/usr/bin/env python3
"""
电商商品爬虫脚本
使用方法：python3 crawler.py <config_file> <output_dir>
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("错误：请先安装 playwright: pip install playwright")
    print("然后运行：playwright install chromium")
    sys.exit(1)


# 用户代理池（避免被封禁）
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
]


def crawl_taobao(url: str, output_dir: Path) -> dict:
    """爬取淘宝商品数据"""
    print(f"  爬取淘宝：{url}")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        
        # 设置 UA
        page.set_extra_http_headers({
            "User-Agent": USER_AGENTS[0]
        })
        
        try:
            page.goto(url, wait_until="networkidle", timeout=30000)
            
            # 提取商品数据
            data = {
                "platform": "taobao",
                "url": url,
                "title": page.query_selector("#MainInfo h1") and page.query_selector("#MainInfo h1").inner_text() or "",
                "price": page.query_selector(".price") and page.query_selector(".price").inner_text() or "",
                "description": page.query_selector("#desc") and page.query_selector("#desc").inner_text() or "",
                "reviews": [],
                "crawl_time": datetime.now().isoformat()
            }
            
            # 提取评价（最多 50 条）
            review_elements = page.query_selector_all(".review-item")
            for el in review_elements[:50]:
                data["reviews"].append({
                    "content": el.query_selector(".text") and el.query_selector(".text").inner_text() or "",
                    "rating": int(el.query_selector(".rating").get_attribute("data-value") or 0),
                    "date": el.query_selector(".date") and el.query_selector(".date").inner_text() or ""
                })
            
            browser.close()
            return data
            
        except Exception as e:
            print(f"    ❌ 爬取失败：{e}")
            browser.close()
            return None


def crawl_jd(url: str, output_dir: Path) -> dict:
    """爬取京东商品数据"""
    print(f"  爬取京东：{url}")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        
        page.set_extra_http_headers({
            "User-Agent": USER_AGENTS[1]
        })
        
        try:
            page.goto(url, wait_until="networkidle", timeout=30000)
            
            data = {
                "platform": "jd",
                "url": url,
                "title": page.query_selector(".sku-name") and page.query_selector(".sku-name").inner_text() or "",
                "price": page.query_selector(".p-price") and page.query_selector(".p-price").inner_text() or "",
                "description": page.query_selector("#detail") and page.query_selector("#detail").inner_text() or "",
                "reviews": [],
                "crawl_time": datetime.now().isoformat()
            }
            
            review_elements = page.query_selector_all(".review-item")
            for el in review_elements[:50]:
                data["reviews"].append({
                    "content": el.query_selector(".review-content") and el.query_selector(".review-content").inner_text() or "",
                    "rating": 5,  # 京东默认 5 星
                    "date": el.query_selector(".review-date") and el.query_selector(".review-date").inner_text() or ""
                })
            
            browser.close()
            return data
            
        except Exception as e:
            print(f"    ❌ 爬取失败：{e}")
            browser.close()
            return None


def main():
    if len(sys.argv) != 3:
        print("使用方法：python3 crawler.py <config_file> <output_dir>")
        print("示例：python3 crawler.py ~/.openclaw/ecommerce/config/product_urls.json ~/.openclaw/ecommerce/raw_data/20260326")
        sys.exit(1)
    
    config_file = Path(sys.argv[1]).expanduser()
    output_dir = Path(sys.argv[2]).expanduser()
    
    # 创建输出目录
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 读取配置
    with open(config_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    all_data = []
    
    # 爬取淘宝
    for url in config.get('taobao', []):
        data = crawl_taobao(url, output_dir)
        if data:
            all_data.append(data)
    
    # 爬取京东
    for url in config.get('jd', []):
        data = crawl_jd(url, output_dir)
        if data:
            all_data.append(data)
    
    # 保存数据
    output_file = output_dir / f"products_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_data, f, ensure_ascii=False, indent=2)
    
    print(f"✅ 爬取完成，共 {len(all_data)} 个商品，保存到：{output_file}")


if __name__ == "__main__":
    main()
