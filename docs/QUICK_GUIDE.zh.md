# Pensees — 快速指南（5 分钟）

5 分钟拿到方向：Pensees 是什么、怎么装、一次真实会话长什么样、产物会落到
哪里。需要展开细节请看 [USER_GUIDE.zh.md](USER_GUIDE.zh.md)。

## 它是什么

Pensees 是一份"技能包"，不是推理服务。它寄生在你已有的 agent 之上
（Cursor / Claude Code / Codex CLI），握住"对话契约"和"HTML demo 模板"
这两件事，把宿主 agent 从"一接到提示就给方案"扳成"先把模糊地方澄清掉再
说"。它不需要 API key，也没有任何登录态——推理由宿主 agent 负责
（BYOCC：bring-your-own-cognition-and-context）。Pensees 只持有规则与
参考资料。

跟普通 agent 对话相比，Pensees 会话有三处区别：

- **一次只问一个问题**（F-07）。每一个 agent 回合的末尾，只有一个 `?`。
  多选项 `(a)/(b)/(c)/(d)` 在结构上仍然算 1 个问题，不是把 3-5 个问题
  一次性扔过来。
- **逃生门是内建的**（F-08、F-31）。每一道选择题都带 `(d) 都不是, 让我
  描述` 以及 `(e) 我想先详细听 (X) 这个选项再决定`。你随时能跳出来，
  也能在不丢失上下文的情况下让 agent 把某个选项讲透。
- **7 行收敛清单**（C-01..C-07）。在 7 行全部 `✅` 并且你显式回了
  `可以` / `go` / `yes` / `ok` 之前，Pensees 不会去写 `requirements.md`
  和 `acceptance-criteria.md`。这道闸是硬的（F-14，HARD-GATE）——既不会
  提前出货，也不会偷偷转交给下游的 skill。

Pensees 故意是"非贪婪"的（AR-06）。没有 [skill/SKILL.md](../skill/SKILL.md)
里列的那几个触发短语，它根本不会被加载。

## 30 秒安装

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

确认装好了：

```bash
ls "$HOME/.cursor/skills-cursor/pensees"
```

应该能看到 `skill/` 目录里的内容已经被链接进去。等价的 symlink 也会同时
落在 `~/.claude/skills/pensees` 和 `~/.codex/skills/pensees`。如果你更
习惯用 `bash`：

```bash
curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | bash
```

生产环境建议固定到某个 release tag：

```bash
PENSEES_VERSION=v0.3.1 curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
```

如果走不通 curl（公司代理、无外网环境等），可以走 `git clone` 或者手动
建 symlink 的兜底路径，见 [README](../README.md#install)。所有安装方式
落地效果完全等价，按自己的沙箱条件选一种就行。

## 第一次会话

打开 Cursor / Claude Code / Codex CLI，在消息里带上任何一个触发短语。
下面是一次"开局 3 回合"，举的是软件场景（Pensees 是领域中性的，研究、
商业决策、生活选择同样适用）：

**回合 1 — 你：**

> pensees, 帮我想清楚要不要给现在的 web app 加缓存

**回合 2 — Pensees（开局/契约回合，F-02）：**

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

**回合 3 — 你：**

> (e)

Pensees 会给出 (b) 的四段拆解：**后果** / **对比** / **场景** / **未知**，
总字数控制在 350 字以内，然后把原问题重新发一遍，末尾追加
`(f) 已了解 (b), 再问 (Y)`。这就是 F-31 在干活：你按需要看细节，但问题
树并不会跑偏。

会话就这样一回合一个问题地推进——直到 7 行清单全部 `✅`、并且你说
`可以` / `go` / `yes` / `ok` 为止。这时（也只有这时）Pensees 会把
`requirements.md` 和 `acceptance-criteria.md` 写到
`.local/pensees/{date}-{slug}/outputs/`。中途想抽身随时可以说
`销毁本会话` / `forget this` / `wipe session`：会话目录会在 2 秒内被
删掉，只在 `.local/pensees/.audit/destruction.log` 留一行"事实"，
不留任何内容。

## 产物落在哪里

Pensees 只往 `.local/pensees/` 下面写东西（相对宿主 agent 当前工作目录），
绝不会动 `skill/`、README，或者任何前缀之外的文件（F-28 / NF-06）。

```
.local/pensees/{YYYY-MM-DD}-{slug}/
├── transcript.md             # 完整对话，按回合分块
├── ontology.yaml             # aspect → dimension → slot 的轻量模型（≤ 50 行）
├── checklist-status.md       # 7 行清单，每回合更新（C-01..C-07）
├── demos/                    # 每次 demo 输出 2-3 份变体 HTML（F-15）
└── outputs/                  # 仅当 HARD-GATE 通过（清单 ✅ + 你的 `go`）才生成
    ├── requirements.md
    └── acceptance-criteria.md
```

每一次完成的会话都会在 `.local/pensees/INDEX.md` 留一行索引。被
`forget this` 掉的会话只会在 `.local/pensees/.audit/destruction.log`
留一行"已销毁"的事实记录，内容从不保留。

## 接下来读

- 完整版指南，覆盖每一个安装参数、每一种预设、每一个宿主的怪癖：
  [USER_GUIDE.zh.md](USER_GUIDE.zh.md)。
- English version of this same guide: [QUICK_GUIDE.md](QUICK_GUIDE.md)。
- 行为契约（F-编号、预设、写路径白名单的唯一来源）：
  [skill/SKILL.md](../skill/SKILL.md)。
- 项目站点（带日夜与中英切换、在线演示）：
  <https://yorha-agents.github.io/Pensees/>。
- 回到项目 [README.md](../README.md)。
