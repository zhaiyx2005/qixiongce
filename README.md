# 七雄策

战国题材单人卡牌对战 Demo，基于 Godot 4.7 + GDScript 开发。

## 下载即玩（免安装）

不想配环境？直接下载打包好的 Windows 免安装版：

- **Gitee Releases（国内推荐，秒开）**：https://gitee.com/zhaiyx2005/qixiongce/releases/tag/v1.1 （约 38 MB）
- **GitHub Releases**：https://github.com/zhaiyx2005/qixiongce/releases/latest （约 38 MB）

解压后双击 `七雄策.exe` 即可开始游戏，**请保持 `七雄策.pck` 与 exe 在同一目录**。
若被 Windows SmartScreen 拦截，右键 exe → 属性 → 勾选「解除锁定」后重试。

> 需要从源码运行或自行导出，见下方「开发环境」。

## 玩法

三局两胜制。每回合通过出牌与 Pass 进行**三行战力比拼**，先赢下两行者获胜。

## 技术特性

- **逻辑层与表现层分离**：规则、卡牌、AI、卡组校验均可脱离界面独立运行，界面全部由代码构建
- **命令模式驱动**：所有玩家操作统一抽象为可序列化的 `Command` 对象，为联机与回放提供基础
- **ENet 主机权威联机**：全量状态同步 + 指令序号去重，含断线重连与回合卡死兜底
- **数据驱动**：7 个阵营的卡牌数值外置为 JSON 配置，新增卡牌无需改动战斗逻辑
- **可扩展效果系统**：`EffectResolver` 负责解析、`EffectRunner` 负责执行，支持条件判定、目标选择与连锁触发

## 数据规模

| 项目 | 数量 |
| --- | --- |
| 卡牌 | 315 条（7 阵营 × 45 张） |
| 能力 | 46 个 |
| 流派 | 14 套（7 阵营 × 2） |
| GDScript | 11148 行，32 个脚本 |

## 目录结构

```
scripts/          游戏逻辑（战斗 / 状态 / 效果 / AI / 网络 / 界面）
scenes/Main.tscn  主场景
data/             卡牌与流派配置（JSON，7 个阵营）
assets/           美术与音频素材
音乐素材/          BGM 源文件
功能清单.md        完整功能规格文档
```

## 自动化验证

项目包含 8 个无界面（headless）检查脚本，可在不启动图形界面的情况下验证核心逻辑是否被改动破坏：

| 脚本 | 用途 |
| --- | --- |
| `_smoke_boot.gd` | 冒烟启动，确认工程可正常加载 |
| `_regress_rules.gd` | 规则回归，验证出牌与结算逻辑 |
| `_regress_net.gd` | 网络同步回归，覆盖联机指令与状态一致性 |
| `_check_faction_effects.gd` | 七国专属机制校验，覆盖各阵营能力触发条件 |
| `_check_ai_balance.gd` | 数值平衡体检，批量自动对战统计各阵营胜率 |
| `_check_archetypes.gd` | 流派配置校验 |
| `_check_layout.gd` | 界面布局校验 |
| `_check_audio.gd` | 音频资源校验 |

运行示例：

```bash
godot --headless --script res://scripts/_check_ai_balance.gd
```

## 更新日志

### v1.1 — 阵营专属机制 + 音画打磨

- **七国专属机制**：新增 `FactionEffects.gd`，把原本通用的一套能力拆解为七国各自专属
  （秦 军功成长 / 齐 步弩协同 / 楚 多路展开 / 燕 边塞固守 / 韩 劲弩集结 / 赵 骑兵策应 / 魏 武卒结阵），
  7 个阵营的 315 张卡牌数据同步更新，阵营之间的打法差异被拉开
- **界面表现**：新增 `CardDecoration`（卡牌装饰）、`InkBackdrop`（水墨背景）两个可复用组件
- **音频**：新增阵营主题曲、势力选择音效、战力升/降音效
- **自动化验证**：新增 `_check_faction_effects.gd`，把七国机制的触发条件纳入回归覆盖

### v1.0 — 首个可玩版本

三局两胜的三行战力比拼、7 阵营 315 张卡牌、14 套流派、人机对战与 P2P 联机。

## 运行

用 Godot 4.7 或更高版本打开 `project.godot`，按 `F5` 启动。

## 备注

个人学习与作品集项目，仅供简历与技术交流使用。
