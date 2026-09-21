# Wick's Gear

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
