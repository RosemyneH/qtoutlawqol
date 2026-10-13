<div align="center">

# qtOutlawQoL

**Crafting tab, break-down all, shift-click smart deposit, and lockbox sort for OutlawCraft.**

<br/>

[![WoW](https://img.shields.io/badge/WoW-3.3.5a-6f42c1?style=flat-square)](#)
[![For](https://img.shields.io/badge/for-OutlawCraft-1784d1?style=flat-square)](#)
[![Release](https://img.shields.io/github/v/release/RosemyneH/qtoutlawqol?style=flat-square&label=release)](https://github.com/RosemyneH/qtoutlawqol/releases/latest)

<br/>

[**Latest Release**](https://github.com/RosemyneH/qtoutlawqol/releases/latest)

</div>

---

<div align="center">

## Features

| | |
| :---: | :--- |
| **Crafting tab** | A tab under the spellbook school tabs that opens the Blueprints window. |
| **Break down all** | An All button on the Break down header. Each ready piece is its own cast, and the next waits until that piece is gone. |
| **Smart deposit** | Shift-click Deposit All to send only stacks the chest already holds. Shift-click a bag item to pour in every stack of it, and only when the open chest already has that item. An unfinished stack in the chest is taken out first so it can join the one in your bags, then the stack goes back. A plain click is still Deposit All. |
| **Lockbox sort** | Open stacks of the same item are taken out and put straight back so they join, then the columns fill downward. Common on the left, rarer to the right. |

</div>

---

<div align="center">

## Install

</div>

1. Download the zip from the [latest release](https://github.com/RosemyneH/qtoutlawqol/releases/latest).
2. Extract the `qtoutlawqol` folder into `Interface\AddOns`.
3. Enable **OutlawCraft** and **qtOutlawQoL**, then `/reload`.

This addon does not need ElvUI. OutlawCraft does.

Keep the folder name as it is. The `.toc` must sit at:

```text
Interface\AddOns\qtoutlawqol\qtoutlawqol.toc
```

ElvUI_Outlawcraft includes the same hooks. While this addon is enabled, that pack leaves them alone so a shift-click is not sent twice.

---

<div align="center">

## Commands

| Command | Action |
| :---: | :--- |
| `/qol` | List what is on |
| `/qol craft` | Toggle the crafting tab |
| `/qol break` | Toggle break down all |
| `/qol deposit` | Toggle smart deposit |
| `/qol sort` | Toggle lockbox sort |

`/qtqol` is the same command.

</div>

---

<div align="center">

## Dev symlink

</div>

The live OutlawCraft client loads a directory junction:

| | |
| :---: | :--- |
| **Repo** | `W:\Repos\qtoutlawqol` |
| **Client** | `W:\outlawcraft\Interface\AddOns\qtoutlawqol` |

Recreate it from PowerShell:

```powershell
New-Item -ItemType Junction -Force `
  -Path "W:\outlawcraft\Interface\AddOns\qtoutlawqol" `
  -Target "W:\Repos\qtoutlawqol"
```

Edit here, `/reload` in-game. No copy step.

</div>
