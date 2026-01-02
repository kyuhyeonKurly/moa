#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# 2025년 전체 64개 티켓을 쿼터별로 정리

FEATURED = {
    # 대표 작업 (사용자가 선택한 34개)
    "KMA-5268", "KMA-6005", "KMA-6167",  # 📊 마케팅 인프라
    "KMA-5474", "KMA-5392", "KMA-6184", "KMA-5686",  # 데이터 & 그로스 인프라
    "KMA-5974", "KMA-5849", "KMA-5733", "KMA-5788", "KMA-6093",  # 플랫폼 인프라
    "KMA-4817", "KMA-4764", "KMA-4799", "KMA-5124", "KMA-5338",  # 디스커버리/검색
    "KMA-5478", "KMA-5600", "KMA-5640", "KMA-6143", "KMA-5480", "KMA-6105", "KMA-6125",
    "KMA-5252", "KMA-5629", "KMA-5926", "KMA-5628", "KMA-5470", "KMA-5764",
    "KMA-5036", "KMA-5379", "KMA-5529",  # 디스커버리/필터
    "KMA-5293",  # 디스커버리/카테고리
}

DEPRECATED = {
    # 누락된 작업 (단순 개선/버그 - 30개)
    "KMA-4771", "KMA-4768",  # 검색 초반
    "KMA-5448", "KMA-5449", "KMA-5471", "KMA-5467", "KMA-5513", "KMA-5573", "KMA-5620",  # QA & 버그
    "KMA-5059", "KMA-5103", "KMA-5121", "KMA-5136", "KMA-5179", "KMA-5190", "KMA-5222", "KMA-5220", "KMA-5234", "KMA-5257", "KMA-5323",  # 세부 작업
    "KMA-5740",  # 하단 섹션
    "KMA-5734", "KMA-5539",  # 캐시/성능/백로그
    "KMA-6050", "KMA-6052", "KMA-6158", "KMA-6209",  # Appsflyer
    "KMA-6008",  # 기타
}

QUARTERS = {
    "Q1": ["KMA-4771", "KMA-4768", "KMA-4817", "KMA-4764", "KMA-4799"],
    "Q2": ["KMA-5121", "KMA-5103", "KMA-5059", "KMA-5036", "KMA-5124", "KMA-5136", "KMA-5179", "KMA-5190", "KMA-5222", "KMA-5220", "KMA-5234", "KMA-5257", "KMA-5252"],
    "Q3": ["KMA-5338", "KMA-5379", "KMA-5392", "KMA-5448", "KMA-5449", "KMA-5471", "KMA-5470", "KMA-5474", "KMA-5478", "KMA-5467", "KMA-5513", "KMA-5529", "KMA-5480", "KMA-5573", "KMA-5293", "KMA-5600", "KMA-5620", "KMA-5704", "KMA-5629", "KMA-5323", "KMA-5640", "KMA-5733", "KMA-5740", "KMA-5769"],
    "Q4": ["KMA-5268", "KMA-5686", "KMA-5628", "KMA-5764", "KMA-5734", "KMA-5926", "KMA-5539", "KMA-6005", "KMA-5974", "KMA-5849", "KMA-6008", "KMA-6050", "KMA-6052", "KMA-6158", "KMA-6105", "KMA-6143", "KMA-5939", "KMA-6093", "KMA-6167", "KMA-6125", "KMA-6209", "KMA-6184"],
}

def generate_markdown():
    md = """# 📊 2025년 iOS 릴리스 - 쿼터별 작업 요약

> **총 64개 티켓**
> - 🔵 대표 작업: 34개 (사용자 선택)
> - ⚪ 개선/버그: 30개 (자동 분류)

---

"""

    for quarter, tickets in QUARTERS.items():
        featured_count = sum(1 for t in tickets if t in FEATURED)
        deprecated_count = sum(1 for t in tickets if t in DEPRECATED)
        
        md += f"## {quarter} ({len(tickets)}개)\n\n"
        md += f"| 타입 | 개수 | 티켓 |\n"
        md += f"|------|------|------|\n"
        md += f"| 🔵 대표 작업 | {featured_count} | "
        
        featured_tickets = [t for t in tickets if t in FEATURED]
        if featured_tickets:
            md += ", ".join([f"[{t}](https://kurly0521.atlassian.net/browse/{t})" for t in featured_tickets])
        else:
            md += "없음"
        md += " |\n"
        
        md += f"| ⚪ 개선/버그 | {deprecated_count} | "
        deprecated_tickets = [t for t in tickets if t in DEPRECATED]
        if deprecated_tickets:
            md += ", ".join([f"[{t}](https://kurly0521.atlassian.net/browse/{t})" for t in deprecated_tickets])
        else:
            md += "없음"
        md += " |\n\n"
    
    # 전체 요약
    md += "---\n\n"
    md += "## 📈 전체 요약\n\n"
    md += "| 쿼터 | 대표 작업 | 개선/버그 | 합계 |\n"
    md += "|------|----------|-----------|------|\n"
    
    for quarter, tickets in QUARTERS.items():
        featured_count = sum(1 for t in tickets if t in FEATURED)
        deprecated_count = sum(1 for t in tickets if t in DEPRECATED)
        md += f"| {quarter} | {featured_count} | {deprecated_count} | {len(tickets)} |\n"
    
    total_featured = len(FEATURED)
    total_deprecated = len(DEPRECATED)
    md += f"| **합계** | **{total_featured}** | **{total_deprecated}** | **{total_featured + total_deprecated}** |\n"
    
    return md

if __name__ == "__main__":
    content = generate_markdown()
    
    output_path = "/Users/g30x74w9xy/Documents/Company/Tool/Moa/exports/2025-quarterly-release.md"
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✅ Generated: {output_path}")
    print(content)
