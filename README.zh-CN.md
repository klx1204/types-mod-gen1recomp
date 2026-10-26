# Gen 9 属性与战斗数据

[English](README.md)

给 **gen1recomp** 的内容 mod，为 Gen 3 游戏（FireRed、LeafGreen、Emerald、
Ruby、Sapphire）加入 Gen 9 数据层，不替换引擎。

## 功能

- 加入 **Fairy** 属性和 Gen 6+ 的 18 属性相克表。
- 重新分配 18 只后来获得 Fairy 的 Gen 3 宝可梦。
- 修改 4 个现有招式的属性：
  - Charm：一般 → Fairy
  - Moonlight：一般 → Fairy
  - Sweet Kiss：一般 → Fairy
  - Curse：??? → Ghost
- 加入 18 个 Gen 9 Fairy 招式，使用 Gen 3 引擎支持的效果。
- 43 个物种的升级学习表来自 CFRU 的 Gen 6 数据。
- 每个招式的物理/特殊/变化分类来自 Showdown 的 Gen 9 数据。

## 安装

解压到引擎的 `mods/` 目录：

```text
mods/types_mod_gen1recomp/manifest.json
mods/types_mod_gen1recomp/main.lua
mods/types_mod_gen1recomp/data/...
```

然后在 `MODS` 里启用 **Gen 9 Types & Battle Data**，把
`OPTIONS` → `BATTLE DATA` 切到 `GEN9`。

如果没有物特分家的引擎，mod 仍然会改属性和招式，但物理/特殊按原版
类型决定。

## 引擎兼容

| 引擎 | 属性/物种/招式 | 物特分家 | 菜单染色 |
| --- | --- | --- | --- |
| `gen1recomp-ps-split` | 支持 | 支持 | 支持 |
| 官方 `gen1recomp` | 支持 | 不支持（按属性） | 不支持 |

fork 下载：
https://github.com/klx1204/gen1recomp-ps-split/releases

## 数据

- 324 条属性相克
- 18 只物种属性
- 18 个 Fairy 招式
- 43 个物种学习表（CFRU Gen 6）
- 372 个招式分类（Showdown Gen 9）

学习表覆盖的新招式：

```text
Disarming Voice   Draining Kiss   Play Rough
Fairy Wind        Moonblast       Baby-Doll Eyes
```

Charm / Moonlight / Sweet Kiss 保持 Gen 3 原版等级。

Dazzling Gleam、Fleur Cannon、Light of Ruin、Floral Healing、
Nature's Madness、Sparkly Swirl、Spirit Break、Strange Steam、
Misty Explosion、Springtide Storm、Magical Torque、Alluring Voice
在 Gen 3 物种上没有升级来源，只存在于招式表。

## 限制

- `BATTLE DATA` 在战斗中不能切换。
- 联机需要双方相同的 mod 和模式。
- 关闭 mod 后自定义招式槽位不会回收；有这些招式的宝可梦会回退到
  Gen 3 属性。
- 12 个没有升级来源的招式只能通过修改或其他方式获得。

## 生成数据

```sh
python3 tools/export_showdown.py --showdown /path/to/pokemon-showdown
python3 tools/export_cfru_learnsets.py --cfru /path/to/Complete-Fire-Red-Upgrade
```

`export_showdown.py` 生成属性表、招式和分类；`export_cfru_learnsets.py`
最后生成学习表，覆盖 Showdown 的占位结果。

玩家不需要 Node、Showdown 或 CFRU，仓库已经提交生成好的 Lua。

## 许可

代码和 Lua 数据表使用 MIT。宝可梦名称、招式名称和机制归各自所有者。
本项目不分发 ROM 或 ROM 提取的图像。
