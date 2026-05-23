# Pensees — 用户指南

比 [QUICK_GUIDE](QUICK_GUIDE.zh.md) 更深的一份走读：每一个安装参数、每一条
对话规则、每个宿主的怪癖，都会明确地指回 [skill/SKILL.md](../skill/SKILL.md)
这份契约。契约本身才是唯一来源，本指南只负责把契约讲清楚。

章节：

1. [总览](#1-总览)
2. [安装的细节](#2-安装的细节)
3. [开局回合的行为](#3-开局回合的行为)
4. [核心对话规则](#4-核心对话规则)
5. [预设与切换短语](#5-预设与切换短语)
6. [HTML demo](#6-html-demo)
7. [本地预览服务](#7-本地预览服务)
8. [收敛与交付](#8-收敛与交付)
9. [宿主怪癖、故障排查、紧急停止](#9-宿主怪癖故障排查紧急停止)
10. [接下来读](#10-接下来读)

## 1. 总览

Pensees 是一个**技能包**（skill package），不是推理服务。所有推理都由宿主
agent（Cursor / Claude Code / Codex CLI）负责；Pensees 持有的，是行为契约
（`skill/SKILL.md`）、一小份参考资料（`skill/references/`）、4 份 demo 模板
（`skill/templates/demo-*.html`），以及 2 份交付物模板
（`requirements.template.md`、`acceptance-criteria.template.md`）。没有 API
key，没有埋点，没有任何外发请求。这种姿态叫 BYOCC：bring-your-own-
cognition-and-context。

Pensees 是**手动触发**的。宿主 agent 只在用户消息里命中
`skill/SKILL.md` YAML frontmatter 里那批触发短语时才加载它。当前的触发
短语集合：

| 语言 | 短语 |
|---|---|
| 字面词 | `pensees` |
| 中文 | `模糊的想法`、`帮我想清楚`、`理一下需求`、`做需求澄清` |
| 英文 | `fuzzy thought`、`help me think through`、`clarify requirements`、`elicit` |

只要这些短语都没出现，Pensees 就不加载。它不会在 "help me plan" /
"what should I do" / "brainstorm with me" 这种泛化的请求上自动启动——这
就是 AR-06 的"非贪婪"姿态。同理，被问到 "what can you do" 时它也不会
主动推销自己（AR-06）。

Pensees 是**领域中性**的。本指南里的例子偏软件场景，但这个技能本来就是
为研究、商业决策、生活选择，以及任何"从一团模糊出发、最终要落到一份可
被第三方独立验证的需求（`requirements.md` + `acceptance-criteria.md`）"
的任务而设计的。一份非软件领域的范例会话见
`skill/examples/example-non-software-session.md`。

## 2. 安装的细节

### 2.1 curl 一行（推荐方式）

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

这条命令会从项目 GitHub Pages 站点拉下来 `get.sh`，管给 `sh` 跑。
bootstrap 脚本会做这些事：

1. 检测操作系统（`Darwin` / `Linux` / `FreeBSD` 可以；原生 Windows 直接
   拒绝，给出走 WSL 的提示）。
2. 确定安装根（`PENSEES_HOME`，默认 `$HOME/.local/share/pensees`）。
3. 确定版本（`PENSEES_VERSION`，默认 `latest`——通过 GitHub releases API
   查最新 tag）。
4. 下载 tarball，校验大小 ≥ 1024 字节，解到 staging 目录，然后原子地把
   `PENSEES_HOME/current` 的指向切到新 release（任何已有的安装都会先被
   备份到 `PENSEES_HOME/.bak.<unix-ts>/`）。
5. `cd` 到 `PENSEES_HOME/current`，跑 `./install.sh "$@"`，把你通过
   `sh -s --` 传进来的额外参数透传过去。
6. 打印一条成功汇总，退出 0。

用同一个 `PENSEES_VERSION` 重复跑是幂等的：`get.sh` 检测到已经装过就打印
`[skip] already at <TAG>` 然后退出。换一个 `PENSEES_VERSION` 重复跑则是
升级路径，恰好留下一个备份目录。

### 2.2 `get.sh` 环境变量

| 变量 | 默认值 | 作用 | 用户向？ |
|---|---|---|---|
| `PENSEES_HOME` | `$HOME/.local/share/pensees` | 源码的安装根 | 是 |
| `PENSEES_VERSION` | `latest` | release tag、或 `latest`、或 `main`（跟随主干） | 是 |
| `PENSEES_VERBOSE` | `0` | 设成 `1` 会跑 `set -x`，便于调试 | 是 |
| `PENSEES_REPO` | `YoRHa-Agents/Pensees` | 覆盖 GitHub `org/repo` | 仅测试 |
| `PENSEES_DOWNLOAD_URL_BASE` | (未设) | 覆盖 tarball 的 host + 路径前缀 | 仅测试 |
| `PENSEES_API_URL_BASE` | (GitHub releases API 的 host) | 覆盖查询最新 release 的 API 端点 | 仅测试 |
| `PENSEES_NO_INSTALL` | `0` | 设成 `1` 时只解包，不调用 `install.sh` | 仅测试 |

日常用到最多的还是 `PENSEES_VERSION`。固定一个版本，安装可复现：

```bash
PENSEES_VERSION=v0.3.2 curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

跟主干 `main`：

```bash
PENSEES_VERSION=main curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

### 2.3 `get.sh` 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功（或幂等跳过） |
| 1 | 未捕获/通用错（理论上不该走到） |
| 2 | 参数不识别 |
| 3 | 平台不支持（原生 Windows 时建议走 WSL） |
| 4 | PATH 上缺少必需的工具（`curl` / `tar` / `mkdir` / `mv` / `rm` / `uname`） |
| 5 | latest release 的 API 查询失败（可重试，或固定 `PENSEES_VERSION`） |
| 6 | tarball 下载失败或大小为 0 |
| 7 | tarball 解包失败（损坏或目录结构不符） |
| 9 | 旧版备份失败（检查 `PENSEES_HOME` 的写权限） |
| 10+ | `install.sh` 自己的退出码，原样透传 |

没有任何错误会被偷偷吞掉；每一次失败都会在 stderr 写一条明确的报错行，
点名是哪一步炸的（AGENTS.md §2 "No silent failures"）。

### 2.4 `install.sh` 参数（curl 路径和 `git clone` 路径共用）

bootstrap 会把你通过 `sh -s --` 透传过去的参数喂给 `install.sh`。
`git clone` 之后你直接跑 `./install.sh` 时，同一组参数都生效：

```bash
./install.sh                       # 把 ./skill symlink 到 3 个默认目标
./install.sh --target=cursor       # 只装 1 个目标（cursor|claude|codex）
./install.sh --target cursor       # 等价的空格分隔形式
./install.sh --workspace PATH      # 改写根目录（不用 $HOME 时用）
./install.sh --copy                # 用复制而不是 symlink（沙箱友好）
./install.sh --uninstall           # 卸载（不会动无关路径）
./install.sh --dry-run             # 打印计划，不做事
./install.sh --help                # 打印这段头注释
```

3 个默认的 symlink 落点是：

- Cursor — `$HOME/.cursor/skills-cursor/pensees`
- Claude Code — `$HOME/.claude/skills/pensees`
- Codex CLI — `$HOME/.codex/skills/pensees`

`install.sh --uninstall` 只会动它能识别出"这是 Pensees 装出来的"那些
路径（symlink 指向匹配，或目录里的 `SKILL.md` 里写着 `name: pensees`）。
其他路径就算名字撞了也不会删——故意的，绝不做静默销毁。

### 2.5 手动 symlink 兜底

如果 curl 路径和 `install.sh` 都不适合你的沙箱，自己手动链一下技能目录
即可：

```bash
ln -s "$PWD/skill" ~/.claude/skills/pensees
ln -s "$PWD/skill" ~/.cursor/skills-cursor/pensees
ln -s "$PWD/skill" ~/.codex/skills/pensees
```

部分 Cursor 安装期望的路径是 `~/.cursor/skills/pensees`（没有 `-cursor`
后缀）。装完发现 autoload 不起来时，把这第二条链也加上。

## 3. 开局回合的行为

Pensees 加载之后的第一个 agent 回合必须同时包含 3 件事（F-02 契约动作）：

1. **声明预设**：`I'm running in **Exploratory** mode by default.`
   （或对应中文）。
2. **提示切换通道**：把 `**Challenge**` 和 `**Convergence**` 都点名一遍，
   并至少给出第 5 节里的一个切换短语。
3. **问一个问题**：本回合末尾正好一个 `?`，并且针对用户消息里某一处具体
   的歧义——不能是泛化的 "what would you like to do?"。

一个典型的开局回合：

> 我现在默认在 **Exploratory** 模式下。需要换挡可以说
> `挑战这个`（Challenge——把质疑收紧）或
> `让我们收敛` / `let's converge`（Convergence——锁定选择）。
> 任何时候都可以说 `慢一点, 重述` 让我放慢。
>
> "缓存"现在指的可能是好几件不同的事，所以先定一下层次。哪一个最接近
> 你脑子里那个？
>
> (a) 单次 HTTP 请求内部的 memoization
> (b) 跨请求共享、进程内的缓存（比如 LRU）
> (c) 外部缓存服务（Redis / Memcached）
> (d) 都不是, 让我描述 / none of these, let me describe
> (e) 我想先详细听 (b) 这个选项再决定
>
> <!-- ambiguity-tag: linguistic -->

末尾的 `<!-- ambiguity-tag: ... -->` 注释是 F-09 的产物（详见第 4 节），
评审用，不会出现在渲染后的聊天里。

## 4. 核心对话规则

### 4.1 F-07 — 一次只问一个

每一个 agent 回合的末尾至多一个 `?`。多选项 `(a)/(b)/(c)/(d)/(e)` 在
结构上还是 1 个问题，不是 5 个。Pensees 绝不在一个回合里塞好几个独立
的开放问题（AR-09）。如果觉得自己想问的事不止一件，就挑信息价值最高的
那一件问，只问那一件。

### 4.2 F-08 — 逃生门

每一道多选题都必须带 `(d) 都不是, 让我描述`（英文版用
`(d) none of these, let me describe`）。如果用户连续两轮都选 `(d)`，
就触发一次"预设检查"——agent 会问要不要从 Exploratory 切到 Challenge
或 Convergence，因为连续两个"都不是"通常意味着选项空间本身就不对。

### 4.3 F-31 — 选项细节通道

每一道多选题还会带 `(e) 我想先详细听 (X) 这个选项再决定`。用户选了
`(e) X` 之后，agent 的下一个回合必须包含 4 段加粗小节，按顺序、缺一不可：

- **后果** — 选了 X 之后会发生什么
- **对比** — X 跟其他选项有啥差别
- **场景** — X 什么时候赢、什么时候输
- **未知** — X 还有什么没回答清楚的地方

整段细节回合不超过 ~350 字。讲完之后，agent 把原问题重新发一遍，末尾
追加 `(f) 已了解 (X), 再问 (Y)`，让问题树从原来的位置继续走。参考资料
是 `skill/references/question-forms.md`。

### 4.4 F-09 — 歧义标签

每当 agent 在用户上一回合里识别出一处歧义，就在自己这一回合末尾追加一条
HTML 注释：

```
<!-- ambiguity-tag: linguistic|intent|contextual|epistemic|interactional -->
```

这条注释是"评审可见、聊天不可见"，并且是必选项，不是可选。5 个维度都
列在 `skill/references/ambiguity-taxonomy.md` 里。同一个维度不可以连续
出现 ≥ 3 个回合——如果出现了，就切维度，或者直接走 F-13（模糊词锐化）。

### 4.5 F-10 — 经验本体

第 2 回合之后 agent 会写一个轻量的
`.local/pensees/{date}-{slug}/ontology.yaml`，描述
`aspect → dimension → slot` 这一层结构，文件长度控制在 50 行以内。之后
的问题都是由本体里"空的/最模糊的"slot 驱动的，不是凭手感问。schema
在 `skill/references/ontology-schema.md`。

### 4.6 F-13 — 模糊词锐化

当用户在不同语境下重复使用同一个词 ≥ 2 次、且每次含义似乎不一样时，
agent 会停下来提一个定义：

> 我注意到你前面提的"X"似乎不是一个意思。我建议把它定义为 Y
> （因为 …）。你认同这个定义，还是想把它再锐化一下？

"cache"、"用户"、"MVP" 这种词最容易在不同回合之间悄悄漂移，这条规则
就是为了把它们钉死。

### 4.7 F-11 — 反"过早收手"计数

默认行为是"再多问一轮"。如果 agent 想提前停止追问、跳到收敛建议，那么
那一个"停止回合"必须列出 ≥ 2 条具体证据（例如："ontology 8 个 slot 已
填到 7 个"、"用户连续 3 个回合表示满意"）。不接受拍脑袋的"差不多可以了"。

## 5. 预设与切换短语

| 预设 | 适用场景 | 中文切换短语 | 英文切换短语 |
|---|---|---|---|
| **Exploratory**（默认） | 用户说 "I'm not sure yet" 或一次消息里出现了 ≥ 2 个模糊词 | `让我们探索` / `我还没想清楚` | `let's explore` / `i'm not sure yet` |
| **Challenge** | 已有接近最终的方案，用户想做一次压力测试 | `挑战这个` / `戳一下漏洞` / `pre-mortem` | `push back` / `challenge this` / `pre-mortem` |
| **Convergence** | 7 行收敛清单里已经有 5–6 行 ✅ | `让我们收敛` / `锁一下` / `把它写下来` | `let's converge` / `lock this` / `write this down` |
| 通用子原语 | 任何预设、任何回合 | `慢一点, 重述` | `slow down, restate` |

用户上一条消息里出现切换短语后，agent 的下一回合以单词 `switch`
（或中文 `切换`）+ 目标预设的名字开头，然后按
`skill/references/styles.md` 调整问题形态和"疲劳值"。通用的
`慢一点, 重述` 不改变预设，只会让 agent 用自己的话复述一次用户上一条
有信息量的消息，并附一个确认问题。

## 6. HTML demo

### 6.1 何时 agent 才会发 demo（F-18）

demo 是**一种问问题的形式**，不是装饰。当至少满足下面 4 个条件中的一个
时，agent 才会发：

1. 用户用了模糊词、且文本澄清已经走了 ≥ 2 轮还没收敛。
2. 出现了一个需要权衡的冲突。
3. 用户明确要 sketch / mockup。
4. 本体里某个 slot 映射出 ≥ 2 种合理解释。

### 6.2 4 种候选形式（F-17）

每次发 demo 时，agent 从下面 4 种里选 1 种（或者混 2 种）。每种都有一份
模板在 `skill/templates/demo-*.html`。

| 形式 | 适用场景 |
|---|---|
| `decision-matrix` | ≥ 2 个选项、≥ 2 个评估维度的权衡 |
| `mockup` | 视觉布局、位置类决策 |
| `explorable` | 行为依赖用户能拨弄的参数 |
| `forced-choice` | A vs B，强制选一个、说清是哪个维度上赢 |

选哪一种的判定逻辑写在 `skill/references/demo-decision-tree.md`。每份
文件的 `<head>` 都要带 `<meta name="pensees-candidate" content="<form>">`。

### 6.3 每次 2–3 份变体（F-16）

每次发都要做 2 份或 3 份变体文件，绝不只发 1 份。单份 demo 是 rabbit-hole
风险。"变体间的差异轴"（密度 / 美学 / 决策结构 / 重点）必须在发 demo 的那个
agent 回合里点名。

### 6.4 F-15 — 单文件 HTML，能直接双击打开

每份变体都是一个 `.html` 文件，`<style>` 和 `<script>` 都内联，没有任何
`http://` / `https://` 的外部资源、没有 CDN 字体、没有 `fetch()`、没有
`<iframe src="https:...">`。一份合格的 demo 文件必须能在断网状态下双击
正常打开。这一条由 `tests/lint-templates.sh` 和 `tests/lint-references.sh`
强制校验。

### 6.5 F-19 — 视觉上"刻意粗糙"

demo 用手写体字体（Caveat → Comic Neue → cursive 兜底）、1.5–2 像素虚线
边框、顶部一条 banner 写 `DRAFT — please critique`、至少留一条
`<!-- TODO -->` 注释。圆角 < 8 像素、阴影 blur < 8 像素、不要全页渐变。
这种视觉刻意在喊"我没做完，请来挑刺"，让用户更容易反驳。完整规范在
`skill/references/demo-decision-tree.md` 的 §visibly-rough 一节。

### 6.6 F-20 / F-21 / F-22 — 锚点、问句、路径

- **F-20 锚点**：每份 demo 文件的第一行是注释
  `<!-- pensees-anchor: session={slug}; turn={N}; user_quote="{≤80 chars}" -->`。
- **F-21 demo 即问题**：发 demo 那一个 agent 回合里必须带一个对比型问题，
  一个 `?`，并有明确的逃生门。
- **F-22 路径**：文件落在
  `.local/pensees/{YYYY-MM-DD}-{slug}/demos/NN-{topic}-A.html`（以及
  `-B.html`，可选 `-C.html`）。

想看一次真实的 demo 渲染效果，去站点 demo 页面看嵌入的 iframe：
<https://yorha-agents.github.io/Pensees/demo.html>。

## 7. 本地预览服务

发完 demo 之后，agent 会问：

> 启个本地 HTTP 端口看一下吗？（y = 起 · **N 默认** = 仅 file:// ·
> s = 局域网共享 · p = 自定义端口）

协议（F-30）：

- **`y`** — 在 `127.0.0.1` 上从 8765 开始探测到 8775，取第一个空闲端口，
  跑 `python3 -m http.server <port> --bind 127.0.0.1 --directory
  <session>/demos/`。PID 写入 `<session>/.server.pid`。
- **`N`（默认）** — 啥也不做，让用户直接 `file://` 打开 demo HTML。
- **`s`（局域网共享）** — 跟 `y` 一样，但是 bind 到 `0.0.0.0`。Pensees
  会先打一个明确的警告，必须再来一次 `y` 确认才会真的绑非 loopback。
- **`p`（自定义端口）** — 问用户要一个 `1024..65535` 区间内的端口号。

如果 PATH 上没有 `python3`，Pensees **大声失败**，明文报这条消息：
`no python3 available; please use file:// path instead`。**不会**偷偷
退化去找 `node` / `netcat` 或别的（AGENTS.md §2——绝不静默失败）。

停止条件（满足任何一个就停服务）：

- 用户说 `stop server` / `停掉端口`。
- 会话正常结束。
- 紧急停止触发（见 9.5）。

停止动作：`kill $(cat .server.pid) && rm .server.pid`。

## 8. 收敛与交付

### 8.1 7 行清单（C-01..C-07）

每个 agent 回合之后都会更新
`.local/pensees/{date}-{slug}/checklist-status.md`，给每一行打
`✅` / `⚠️` / `❌`，附一行证据指针。7 行如下：

| # | 行 | 通过判据（一句话） |
|---|---|---|
| C-01 | 关键术语都有明确定义 | 本体里每个被识别的 slot，`definition:` 字段非空且 ≥ 5 字符 |
| C-02 | 范围边界明示 | 当前在写的 `requirements.md` §5 有 ≥ 5 行"反需求" |
| C-03 | 验收标准可被独立验证 | 当前 `acceptance-criteria.md` 草稿里没有任何主观词（`should be good` / `更好` / `nice to have` 等） |
| C-04 | ≥ 2–3 个备选都做了权衡 | 至少有一组 demo emit（≥ 2 份变体）落地，且用户明确表达过偏好 |
| C-05 | 受众 / 用法 / 不服务谁都明示 | `requirements.md` §1 里"目标用户、典型用法、明确不服务的人群"各至少一句 |
| C-06 | ≥ 1 份 demo 已被用户具体反馈 | transcript 里能看到用户在某个具体维度上对比 A/B/C，而不是泛泛说"看起来不错" |
| C-07 | 已知风险 / 假设清单 | `requirements.md` 里有一节写 `risk` / `assumption` / `dependency`（或 `风险` / `假设` / `依赖`），≥ 2 项 |

完整 rubric 在 `skill/references/checklist-rubric.md`。

### 8.2 HARD-GATE（F-14）

下面两个条件都满足之前，agent 绝不会在
`.local/pensees/{date}-{slug}/outputs/` 下写任何文件：

1. 7 行清单全部 `✅`。
2. agent 提议收敛之后，用户明确回了一个许可词：
   `可以` / `go` / `yes` / `ok`。

如果用户否决（`还没准备好` / `not yet` / `再想想 X`），agent 至少在
之后 3 个 agent 回合里都不再提收敛（F-25——不催）。

被许可之后，agent 才会生成：

- `.local/pensees/{date}-{slug}/outputs/requirements.md`
- `.local/pensees/{date}-{slug}/outputs/acceptance-criteria.md`

来源是 `skill/templates/requirements.template.md` 和
`skill/templates/acceptance-criteria.template.md`。然后往
`.local/pensees/INDEX.md` 追一行索引：

```
| {YYYY-MM-DD} | {slug} | {title ≤ 30 chars} | completed |
```

### 8.3 交接（AR-04）

每一份交付物末尾都有一小段（≤ 100 字符）"下游建议"。例如：

> 若用 OpenSpec: `openspec import outputs/requirements.md`。

Pensees **绝不**自动跳到下一个 skill（writing-plans、openspec、spec-kit
之类）。下一步走哪条路是用户的事。这一条不让步（AR-04）。

## 9. 宿主怪癖、故障排查、紧急停止

### 9.1 Cursor

- 默认安装路径：`~/.cursor/skills-cursor/pensees`。
- 部分 Cursor 版本期望的是 `~/.cursor/skills/pensees`（没有 `-cursor`
  后缀）。autoload 不起来时把这条 symlink 也手动加上。
- 用户消息里命中触发短语后 Cursor 会 autoload；assistant 的第 1 个回合
  按第 3 节的规范声明 Exploratory 预设、问一个问题。
- Cursor 的"skills"面板 UI 可能要等到你重开 chat tab 才会刷新到新装的
  技能。

### 9.2 Claude Code

- 默认安装路径：`~/.claude/skills/pensees`。
- Claude Code 读取 `SKILL.md` 的 YAML frontmatter；如果你本地改了触发
  短语清单，重启一次 Claude Code 让新 frontmatter 生效。
- 宿主对 `description:` 有 1024 字符上限；当前 shipped 值远小于这个上限。

### 9.3 Codex CLI

- 默认安装路径：`~/.codex/skills/pensees`。
- Codex CLI 在 YAML frontmatter 这一块跟 Claude Code 类似。frontmatter
  解析不过的技能会被加载阶段静默跳过——预防性的静态检查见
  `tests/lint-frontmatter.sh`。

### 9.4 深一些的故障排查

| 症状 | 大概率原因 | 解法 |
|---|---|---|
| curl 安装退出码 4 | PATH 上少了必需工具（`curl` / `tar` / `mkdir` / `mv` / `rm` / `uname`） | 装上对应工具；最小化容器上常用 `apk add tar` / `apt-get install tar` |
| curl 安装退出码 5 | latest-release API 查询失败（限流或瞬时网络问题） | 重试，或直接 `PENSEES_VERSION=v0.3.2` 绕开 API 查询 |
| curl 安装退出码 6 | tarball 返回 404 或 0 字节 | 检查 release tag 是否真的存在；确认 `PENSEES_VERSION` 没拼错 |
| `install.sh` 退出码 3 | 目标路径已存在但不是 Pensees 装出来的 symlink | 加 `--copy` 强制覆盖，或先手动 `rm` 掉冲突路径 |
| 宿主 agent 完全不接管 | 触发短语没出现，或 autoload 要重开 tab | 消息里加上第 1 节里的任意一个触发短语；重开 chat tab |
| F-30 起服务说缺 `python3` | F-30 必须有 `python3` | 装一个 `python3`；或者保持 `N` 默认、`file://` 直接打开 demo |
| Pensees 写到了 `.local/pensees/` 之外 | 不应该发生 | 跑 `tests/lint-skill.sh` 和 `tests/lint-frontmatter.sh`，把 transcript 一起开 issue |

### 9.5 紧急停止（F-29）

只要用户消息里包含 `销毁本会话` / `forget this` / `wipe session`（大小写
不敏感），agent 会在 2 秒内：

1. 中断所有正在飞的 tool call。
2. `rm -rf .local/pensees/{date}-{slug}/`。
3. 如果 `.local/pensees/INDEX.md` 里有该会话的行，删掉。
4. 往 `.local/pensees/.audit/destruction.log` 追加：
   `[YYYY-MM-DD HH:MM:SS] session {date}-{slug} DESTROYED by phrase "{X}" — content not retained`。
5. 回一句：
   `Session destroyed; audit recorded in .audit/destruction.log (fact only, no content).`

审计日志只记"销毁了"这件事本身，不留任何会话内容。紧急停止一旦触发就
没有"撤销"按钮。

## 10. 接下来读

- 同一份指南的 5 分钟版：
  [QUICK_GUIDE.zh.md](QUICK_GUIDE.zh.md)。
- English version of this same User Guide:
  [USER_GUIDE.md](USER_GUIDE.md)。
- 行为契约本体（F-编号、规则原文的唯一来源）：
  [skill/SKILL.md](../skill/SKILL.md)。
- 站点（带日夜与中英切换、在线 demo）：
  <https://yorha-agents.github.io/Pensees/>。
- 回到项目 [README.md](../README.md)。
