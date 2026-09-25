# Chinese style

Apply these checks to Chinese artifacts: replies, code comments, documentation, commit messages, reports. The English rules in the parent skill still apply; this file covers habits that only appear in Chinese prose.

Language habit: plain and natural, keeping only the technical terms that carry meaning.

## Quotation marks

Do not use U+201C or U+201D, unless the user explicitly asks for a verbatim quotation.

Use inline code formatting for identifiers, paths, and commands. Do not quote a term in order to emphasize it.

Do not wrap abbreviations, industry slang, or four-character phrases in quotes; write the full expression instead.

错误：这套系统做到了 U+201C高可用U+201D，前端实现了 U+201C多端适配U+201D，后端进行了 U+201C冷热分离U+201D，线程池本身只提供 U+201C常驻线程反复取活U+201D的机制。

正确：这套系统具备高可用性，前端实现了多平台适配，后端实现了冷热数据分离存储，线程池本身只提供常驻线程循环取任务的机制。

## Translationese

Avoid idioms translated word by word from English, and verbs that do not fit Chinese technical usage. Watch for: 接住、击穿、锋利、不崩、不爆、打穿、扛住.

错误：当遇到大流量时，如果缓存被击穿，系统能否扛住压力？如果代码有漏洞，很容易被黑客打穿防线。

正确：当遭遇大流量并发时，若缓存失效导致请求直达数据库，系统能否承受此负载压力？若代码存在安全漏洞，防线极易被黑客攻破。

## Over-compressed vocabulary

Do not shorten technical terms for brevity. The abbreviation usually loses the meaning or creates a second reading.

错误：服务器出现高负，导致微服响应超时，建议排查连池配置。

正确：服务器出现高负载情况，导致微服务响应超时，建议排查数据库连接池配置。

## Invented terms

Do not fuse an English concept into a Chinese compound that never appears in real technical writing.

错误：该架构具有极高的高并发抗性，代码的自解释度出色，并展现出良好的容灾力。

正确：该架构能够有效应对高并发冲击，代码可读性强且易于理解，同时具备良好的容灾能力。

## The 不是……而是…… pattern

Avoid the contrast construction unless a comparison or a correction is genuinely intended. State the affirmative fact directly.

错误：该接口响应变慢的原因不是服务器负载过高，而是缓存策略失效。

正确：该接口响应变慢的原因是缓存策略失效。

# Structural patterns

The checks above work on single words and phrases. These work on the shape of a section, which survives even after every banned word is gone.

## Forced parallelism and uniform counts

Do not build a three-item list because the sentence reaches for three. Two items, or one plain sentence, is usually the real content. Do not give every section the same number of bullets or pad a list to a round number; a section with one point stays one point.

错误：该系统具备高效性、稳定性与可扩展性。

正确：该系统在高并发下响应稳定，扩容时不需要停机。

## Empty openers and closers

Delete framing that carries no information: 在当今快速发展的时代、众所周知、从某种意义上说、综上所述、由此可见、总而言之、具有重要的意义。

错误：综上所述，合理的缓存设计对系统具有重要意义。

正确：删掉整句，直接从结论开始。

## Hedging without information

Remove 可能、或许、在一定程度上、需要注意的是、不难看出 when they mark nothing. Keep a hedge that signals real uncertainty.

错误：需要注意的是，这种做法在一定程度上可能会带来性能问题。

正确：这种做法在批量写入时可能带来性能问题。

## Abstract jargon

Replace noun-heavy business jargon with the concrete action it stands for: 赋能、闭环、抓手、痛点、拉通、对齐、颗粒度、组合拳、生态。

错误：通过拉通各方对齐颗粒度，形成数据治理的闭环。

正确：数据由同一个负责人维护，字段定义写入同一份文档。

## Restating transitions

Do not chain paragraphs with 首先、其次、最后 when nothing is actually ordered, and do not restate the previous paragraph before continuing.

错误：首先，我们分析了日志。其次，我们定位了超时。最后，我们修复了连接池。

正确：日志里出现大量连接池等待超时，把池大小从 10 调到 50 后消失。

## Empty adjectives

Delete stacked praise that no measurement backs: 强大的、完善的、全方位的、卓越的、极致的。

错误：该方案提供了完善的全方位监控能力。

正确：该方案采集响应时间、错误率和连接池等待时长。
