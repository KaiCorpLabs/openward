# Conformance report

Matching steps per test (screen text / cursor / styles). Steps where an engine switched to 132 columns are counted apart: tmux, the reference, ignores DECCOLM.

| Test | Steps | alacritty | ghostty |
|---|---|---|---|
| CJK ideograph | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| ZWJ family | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| arabic letter | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| ascii | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| box drawing | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| devanagari conjunct | 1 | 1 / 1 / 1 | 1 / 0 / 1 |
| e + combining acute | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| ellipsis (ambiguous) | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| emoji | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| emoji modifier alone | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| flag ES | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| fullwidth A | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| greek alpha (ambiguous) | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| hangul jamo L+V+T | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| hangul syllable | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| heart + VS16 | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| keycap 1 | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| precomposed e-acute | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| rainbow flag (ZWJ + VS16) | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| smiley + VS15 | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| soft hyphen | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| thai + vowel mark | 1 | 1 / 1 / 1 | 1 / 1 / 1 |
| thumbs up + skin tone | 1 | 1 / 0 / 1 | 1 / 1 / 1 |
| zero-width space | 1 | 1 / 1 / 1 | 0 / 1 / 1 |

## Where the engines disagree

Steps where the two engines differ from each other, whatever tmux shows.

| Test | Steps | Text differs | Styles differ |
|---|---|---|---|
| zero-width space | 1 | 1 | 0 |

## Cursor after each step (row, column)

| Step | ref | alacritty | ghostty |
|---|---|---|---|
| ascii | (1, 2) | (1, 2) | (1, 2) |
| precomposed e-acute | (1, 2) | (1, 2) | (1, 2) |
| e + combining acute | (1, 2) | (1, 2) | (1, 2) |
| CJK ideograph | (1, 3) | (1, 3) | (1, 3) |
| fullwidth A | (1, 3) | (1, 3) | (1, 3) |
| hangul syllable | (1, 3) | (1, 3) | (1, 3) |
| hangul jamo L+V+T | (1, 3) | (1, 3) | (1, 3) |
| emoji | (1, 3) | (1, 3) | (1, 3) |
| heart + VS16 | (1, 3) | **(1, 2)** | (1, 3) |
| smiley + VS15 | (1, 2) | (1, 2) | (1, 2) |
| thumbs up + skin tone | (1, 3) | **(1, 5)** | (1, 3) |
| ZWJ family | (1, 3) | **(1, 7)** | (1, 3) |
| flag ES | (1, 3) | (1, 3) | (1, 3) |
| keycap 1 | (1, 3) | **(1, 2)** | (1, 3) |
| devanagari conjunct | (1, 4) | (1, 4) | **(1, 3)** |
| thai + vowel mark | (1, 2) | (1, 2) | (1, 2) |
| arabic letter | (1, 2) | (1, 2) | (1, 2) |
| zero-width space | (1, 3) | (1, 3) | (1, 3) |
| soft hyphen | (1, 4) | **(1, 3)** | (1, 4) |
| ellipsis (ambiguous) | (1, 2) | (1, 2) | (1, 2) |
| greek alpha (ambiguous) | (1, 2) | (1, 2) | (1, 2) |
| box drawing | (1, 4) | (1, 4) | (1, 4) |
| emoji modifier alone | (1, 3) | (1, 3) | (1, 3) |
| rainbow flag (ZWJ + VS16) | (1, 3) | **(1, 4)** | (1, 3) |

## Differences

Rows that differ, as `ref` (tmux) and each engine; `·` marks a space. Style differences list the first cells only.

### Step 8 · heart + VS16

```
cursor  ref (1, 3)  alacritty (1, 2)
```

### Step 10 · thumbs up + skin tone

```
cursor  ref (1, 3)  alacritty (1, 5)
```

### Step 11 · ZWJ family

```
cursor  ref (1, 3)  alacritty (1, 7)
```

### Step 13 · keycap 1

```
cursor  ref (1, 3)  alacritty (1, 2)
```

### Step 14 · devanagari conjunct

```
cursor  ref (1, 4)  ghostty (1, 3)
```

### Step 17 · zero-width space

```
 1 ref       |a​b|
 1 ghostty   |ab|
```

### Step 18 · soft hyphen

```
cursor  ref (1, 4)  alacritty (1, 3)
```

### Step 23 · rainbow flag (ZWJ + VS16)

```
cursor  ref (1, 3)  alacritty (1, 4)
```
