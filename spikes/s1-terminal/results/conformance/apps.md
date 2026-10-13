# Conformance report

Matching steps per test (screen text / cursor / styles). Steps where an engine switched to 132 columns are counted apart: tmux, the reference, ignores DECCOLM.

| Test | Steps | alacritty | ghostty |
|---|---|---|---|
| colors 256 | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| colors truecolor | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| htop | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| htop quit | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| htop tree | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| less end | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| less open | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| less quit | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| less search | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| man | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| man page | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| man quit | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| shell | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| styles | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim cjk insert | 1 | 0 / 1 / 0 | 1 / 1 / 0 |
| vim insert line | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim open | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim page down | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim quit | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim search | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim split | 1 | 0 / 1 / 0 | 0 / 1 / 0 |
| vim visual block | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| vim vsplit | 1 | 1 / 1 / 1 | 1 / 1 / 1 |

## Where the engines disagree

Steps where the two engines differ from each other, whatever tmux shows.

| Test | Steps | Text differs | Styles differ |
|---|---|---|---|
| vim cjk insert | 1 | 1 | 0 |
| vim split | 1 | 1 | 1 |

## Cursor after each step (row, column)

| Step | ref | alacritty | ghostty |
|---|---|---|---|
| shell | (1, 10) | (1, 10) | (1, 10) |
| vim open | (0, 5) | (0, 5) | (0, 5) |
| vim page down | (0, 13) | (0, 13) | (0, 13) |
| vim search | (3, 9) | (3, 9) | (3, 9) |
| vim insert line | (4, 45) | (4, 45) | (4, 45) |
| vim visual block | (6, 37) | (6, 37) | (6, 37) |
| vim vsplit | (6, 36) | (6, 36) | (6, 36) |
| vim split | (0, 4) | (0, 4) | (0, 4) |
| vim cjk insert | (17, 34) | (17, 34) | (17, 34) |
| vim quit | (2, 10) | (2, 10) | (2, 10) |
| less open | (39, 15) | (39, 15) | (39, 15) |
| less search | (39, 1) | (39, 1) | (39, 1) |
| less end | (39, 5) | (39, 5) | (39, 5) |
| less quit | (3, 10) | (3, 10) | (3, 10) |
| man | (39, 59) | (39, 59) | (39, 59) |
| man page | (39, 60) | (39, 60) | (39, 60) |
| man quit | (4, 10) | (4, 10) | (4, 10) |
| htop | (39, 81) | (39, 81) | (39, 81) |
| htop tree | (39, 81) | (39, 81) | (39, 81) |
| htop quit | (5, 10) | (5, 10) | (5, 10) |
| colors 256 | (15, 10) | (15, 10) | (15, 10) |
| colors truecolor | (17, 10) | (17, 10) | (17, 10) |
| styles | (20, 10) | (20, 10) | (20, 10) |

## Differences

Rows that differ, as `ref` (tmux) and each engine; `·` marks a space. Style differences list the first cells only.

### Step 7 · vim split

```
 6 ref       |··5·0004·é·Привет·─┼─·한국어·中文测试·🚀·─┼─·é·ñ·👍🏽···é·かな|··45·············if·self.port·>·7417:
 6 alacritty |··5·0004·é·Привет·─┼─·한국어·中文测试·🚀·─┼─·é·ñ·👍🏽·é·かな|··45·············if·self.port·>·7417:
 7 ref       |··6·0005·─┼─·한국어·かな·ascii·かな·Привет·─┼─·🚀·👍🏽an······|··46·················raise·ValueError("port·out·of·range:
 7 alacritty |··6·0005·─┼─·한국어·かな·ascii·かな·Привет·─┼─·🚀·👍🏽······|··46·················raise·ValueError("port·out·of·range:·%
 7 ghostty   |··6·0005·─┼─·한국어·かな·ascii·かな·Привет·─┼─·🚀·👍🏽an······|··46·················raise·ValueError("port·out·of·range:·%
12 ref       |··9·0008·ñ·한국어·Привет·é·Ωμέγα·👍🏽···🚀·👍🏽·················|··49·class·Device3:
12 alacritty |··9·0008·ñ·한국어·Привет·é·Ωμέγα·👍🏽·🚀·👍🏽···············|··49·class·Device3:
15 ref       |····漢字·かな·👍🏽ni·漢字·かな································|··52·····def·__init__(self,·name,·port=22):
15 alacritty |····漢字·かな·👍🏽·漢字·かな································|··52·····def·__init__(self,·name,·port=22):
16 ref       |·12·0011·é·👍🏽se·かな·Ωμέγα·ascii·🚀·ascii·👍🏽···é·👍🏽···é·ñ·漢|··53·········self.name·=·name
16 alacritty |·12·0011·é·👍🏽·かな·Ωμέγα·ascii·🚀·ascii·👍🏽·é·👍🏽·é·ñ·漢|··53·········self.name·=·name
styles  alacritty: 42 cells differ
  6,60  alacritty fg Default bg Default attrs 0x100  ref fg Default bg Default attrs 0x0
  6,62  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x100
  6,78  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
  6,79  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
styles  ghostty: 46 cells differ
  6,60  ghostty fg Default bg Default attrs 0x100  ref fg Default bg Default attrs 0x0
  6,62  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x100
  6,78  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
  6,79  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
```

### Step 8 · vim cjk insert

```
 3 ref       |393·0392·Привет·👍🏽·Ω·ñ·ascii·かな·한국어····················|··42·····def·connect(self,·timeout=14):
 3 alacritty |393·0392·Привет·👍🏽·ñ·ascii·かな·한국어····················|··42·····def·connect(self,·timeout=14):
 6 ref       |395·0394·한국어·カタカナ·é·👍🏽···Ωμέγα·ascii·漢字·한국어·漢字|··45·············if·self.port·>·7417:
 6 alacritty |395·0394·한국어·カタカナ·é·👍🏽·Ωμέγα·ascii·漢字·한국어·漢字|··45·············if·self.port·>·7417:
 8 ref       |396·0395·ascii·한국어·한국어·é·Привет·Привет·é·ñ·👍🏽국·é·漢字|·····d"·%·self.port)
 8 alacritty |396·0395·ascii·한국어·한국어·é·Привет·Привет·é·ñ·👍🏽·é·漢字|·····d"·%·self.port)
17 ref       |401·漢字·かな·한국어·café·👍🏽···─┼─··························|··54·········self.port·=·port
17 alacritty |401·漢字·かな·한국어·café·👍🏽·─┼─··························|··54·········self.port·=·port
styles  alacritty: 27 cells differ
  3,60  alacritty fg Default bg Default attrs 0x100  ref fg Default bg Default attrs 0x0
  3,62  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x100
  3,70  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
  3,71  alacritty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
styles  ghostty: 27 cells differ
  3,60  ghostty fg Default bg Default attrs 0x100  ref fg Default bg Default attrs 0x0
  3,62  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x100
  3,70  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
  3,71  ghostty fg Indexed(130) bg Default attrs 0x0  ref fg Default bg Default attrs 0x0
```
