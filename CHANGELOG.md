# Wick's Gear

## 0.4.0

- The data file now carries a name and a stat line for each item, used
  only when the client has nothing of its own to say. On this beta it
  often has nothing: of the thirteen things in Gnomeregan it could name
  three. The client is still asked first and its answer always wins,
  because it is the one this server is using.
- Data.lua is 41KB, up from 25KB.

## 0.3.1

- Names and stats no longer wait on the server at all. GetItemInfo
  needs an item to have arrived and on this beta many never do, so
  names come from GetItemNameByID and stats are read from an "item:id"
  link built on the spot. Both are answered from the client's own
  files. The real link is still preferred when it turns up, since it
  carries enchants.

## 0.3.0

- Items load properly now. Opening the window used to ask the server
  for all 272 at once, which it throttles, so most requests were
  dropped and rows sat reading "loading..." a minute later. They go out
  a dozen at a time instead, and whatever dungeon you have open jumps
  the queue.
- The list draws immediately with whatever the client already knows
  rather than waiting for the slowest item, and fills in as the rest
  arrives.

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
