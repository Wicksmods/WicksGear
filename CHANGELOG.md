# Wick's Gear

## 0.9.5 — 2026-09-24

### Added

- The right column is a wardrobe. Page through the sets your class can
  wear with the arrows above the model and the character puts one on:
  its pieces light up in the list beside it, and the readings
  underneath say what wearing the set would do to you.
- Drag the model to turn the character, right-click it to put it back
  to front-on. The shoulders are most of what a front view hides.

### Changed

- The character is bigger. The slots moved out from either side of the
  model into one strip beneath it, so the picture gets the whole width
  of the column rather than a third of it. They keep every job they
  had: tooltips, a drop target, right-click to put a piece back.
- The readings under the model are two lanes now. What the gear gives
  you on the left, what the character sheet makes of it on the right,
  each with the total and what the preview would change it by.
- Those totals are the client's own readings rather than our
  conversions run at your current stats. The old way reported health
  from stamina under the word Health, which is not your health and
  disagreed with your character sheet. Anything the client will not
  hand over reads as a dash rather than a guess.

## 0.9.4 — 2026-09-24

### Fixed

- Upgrades suggested pieces you were already wearing. It picked the
  best-scoring item in the data for each slot and never asked whether
  that item was on your back, so your own gear could win its own slot
  and be recommended back to you, scored against itself.
- The slot now falls to the next best piece rather than the row simply
  disappearing, and the question is asked of the whole character: rings
  and trinkets have two slots each, and a ring worn in the second is
  still a ring you own.

## 0.9.3 — 2026-09-24

### Changed

- The window is two columns. The lists keep the left side and their
  tabs; the paperdoll and the stats hold the right and are always on,
  so trying something on no longer costs you your place in the list.
- A row is three lines: the name in its quality colour, what the piece
  gives, and where it comes from, with an icon big enough to find
  things by. Rows band so a row reads as a block, groups wear a bar,
  and anything on the doll is lit in the list.
- Click a row to put a piece on, click it again to take it off.
- Set bonuses read beside the stats rather than as rows in the list,
  where they wrapped into each other. Only the ones you have earned,
  and they count what you are trying on: two pieces of a set in the
  preview shows the two-piece bonus, in green because you would be
  gaining it. Each line carries the count it needs, 2/5 through 5/5,
  rather than repeating how much of the set you are wearing.
- Our own tooltip names the set and lists its bonuses for an item the
  client has never seen, which is the only tooltip those items get.

### Fixed

- The window opened at whatever size it had been before the layout
  changed, which squeezed the list until the source text ran under the
  score and ran the paperdoll through the button below it.
- Taking a piece off did not clear its highlight in the list.
- A row reused as a group header kept the previous item's stats and
  source lines, which drew over the header beneath it.

## 0.9.2

### Fixed

- Comparing a two-hander left your off hand on. The compare was adding
  a two-hander and a shield together, which is not something you can
  wear, so every number it gave was too high. It comes off now, and the
  other way round too: an off hand takes a two-hander off.
- A dungeon in the browse list could look disabled. Rows are reused, and
  a group header was not undoing all of the dimming left by an unusable
  item.
- Upgrades printed "-0" for a slot barely worse off, which reads as a
  downgrade that is not one. An empty slot printed its score without a
  sign while every other row had one; going from nothing to something is
  a gain like any other.

## 0.9.1

### Browse four sources, not one

Dungeons as before, plus what the four gear professions make, quest
rewards worth crossing a zone for, and everything grouped by the set it
belongs to. 1294 crafted pieces and 179 blue and better rewards join the
408 from the dungeons.

A search box spans whichever source is showing, matching the item, the
boss or profession, the slot, and where it comes from. Typing flattens
the list, because a collapsed group hiding the match is the opposite of
searching.

### Set bonuses

A set says how much of it you are wearing, which bonuses that has
earned, and what the next one wants. The count comes off your equipped
slots and the bonus text comes from the client's own tooltip, so both
are this build's rather than a database's guess at it.

### Clicks

Click a row to try it on in the compare view, ctrl-click to open it in
the dressing room, shift-click to put it in chat. An Equippable toggle
hides what your class cannot wear.

### Fixed

- Most items would not shift-click into chat. An item link is a fixed
  shape on a given build and ours was one field long; it reads the shape
  off the gear on your back now.
- Clicking an item sometimes reopened the group it was in, because rows
  are pooled and one that had been a group header kept its toggle.

## 0.9.0

One version across the suite for the Forever beta. Every addon carried a
number of its own that said nothing about how finished it was, so they are
aligned here and the suite goes to 1.0.0 together at launch.

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
