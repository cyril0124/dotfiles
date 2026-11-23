---
name: dense-output
description: Use when asked to compress a reply or deliverable into scannable, high-density form without losing key information.
---

# Dense Output

## Bad

低信息密度：
- 长篇大论（不管简单与复杂）
- 大段文字
- 有效信息混杂在无效信息中
- 需要用户完整阅读后提取出有效信息
- 夹杂很多与用户的对话残留内容

例子：
```
xxx<useful info>xxxxxx<slop>, xxxxxxx, <slop>, xxxxx<slop>. xxxx
xxxxxxxxxxxxxxx<useful info>xxxxxxxxxxxxx. xxxxxxxxxx<slop>. xxx
xxxxxxxx. <slop>xxxxxxxxxxxxxxxxxx<useful info>xx.
```

## Good

高信息密度：
- 分点描述
- 没有废话
- 直击要害
- 一眼看到都是关键信息
- 没有用户对话残留内容
- ADHD 友好
- 简洁清爽

例子：
```
- <useful info>
- <useful info>
- <useful info>
```

格式不限制死（重点是内容的高密度，不是 markdown 排版，不一定是严格按照上面的模板）：
```
<useful info>
- <useful info>
- <useful info>
- <useful info>

# <section>

## <subsection>

<useful info>
- <useful info>
- <useful info>
- <useful info>

1. <useful info>
2. <useful info>
3. <useful info>
```

## Compression Report

额外简单跟用户说明压缩效果，用百分比表示，例如：100%（压缩前） -> 60%（压缩后）。百分比按字符数计算，不按行数。

## Constraints

- 从 "低信息密度" 到 "高信息密度" 转换的时候，保持原有表达的意思/功能不变
- 不要生搬硬套，要有灵活的空间，如果这种信息密度的转换不合适，那就不转换或者只转必要的部分，尽最大能力进行转换
- 假设：压缩前的字符数 A、压缩后的字符数 B
    - 那么：A >= B
    - 否则：你压缩的不对，没有达到信息密度的转换要求，一定要达到要求
- 不止适用于文字内容，代码的注释也是目标（前提是用户有要求）
- 本 SKILL 最终要达到的效果是：保留关键内容、减少 token 消耗、用户阅读顺畅
