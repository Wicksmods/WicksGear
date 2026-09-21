# Wick's Gear

## 0.2.2

- Fixed: items still arriving from the server stayed as "item 9454"
  with an empty tooltip. The list waited three seconds and drew
  whatever had turned up; anything later was never drawn again. It now
  redraws as data arrives, coalesced so a flood of them is one redraw,
  and says "loading..." meanwhile instead of showing you an id.

## 0.2.1

- Fixed: right-clicking a piece to try it on threw an error unless you
  had opened the Compare tab at least once first. The paperdoll is
  built on demand now. The tests had been opening the tab before trying
  anything, which is not the order anyone actually does it in.

## 0.2.0

- A Compare tab: a paperdoll with your character on it. Right-click
  anything in Upgrades or Browse to try it on, or drag it onto a slot.
- Stats show what the piece would do, green up and red down. Strength
  through Spirit and armour are exact subtraction.
- So are attack power, crit, health and mana. The client exposes the
  conversions its own character sheet uses and they take a stat value
  as an argument, so the numbers come from asking it twice rather than
  from reimplementing anyone's formulas.

## 0.1.0

First build, for World of Warcraft: Forever.

- Upgrades: best piece per slot, scored against what you have equipped.
- Browse: fourteen levelling dungeons, drops and quest rewards.
- Proficiency aware, so a rogue is never offered mail or a two-hander.
- Ships ids and sources only; the client supplies everything else.
- Gear you cannot use is darkened and its icon desaturated. Muted grey
  against off-white read as the same colour at this size.
