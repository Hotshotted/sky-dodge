# Hunting threats, guns and bosses

The Countryside is no longer only static obstacles. Everything below lives in `scripts/Threats.gd`, is pooled (every node and
material is created once at start-up and only shown / hidden), pre-warmed under the splash, and tuned in `Tuning.gd`
("Hunting threats, swarm pressure, bosses"). `?nofx=threats` switches it all off.

## The threats (each warns before it can hurt)

| Threat | What it does | Telegraph | How to answer |
| --- | --- | --- | --- |
| Hawk | dives on the plane's spot from above | a shadow grows where the plane is for 1.1 s, a screech, the aim locks 0.45 s before the dive | step out of the shadow |
| Geese | a V of five sweeps across the screen, drifting toward the plane | an arrow at the screen edge for 1.5 s, a honk | slip above / below the lane |
| Crows | a flock closes from behind, following the plane's x | chevron at the bottom edge for 1.3 s, caws | dash sideways when they are close (they commit and fly straight once near) |
| Drone | hovers at the top tracking the plane, winds up, darts down a locked lane | the lane glows red and a whine climbs for 0.95 s | leave the lane (the lane obeys the lightning fairness rule) |

All of them can be shot down by the guns or answered by the gear below, and a kill pays coins.

## Active perks (the first pick)

The perk pool is now mostly *active, visible* gear; each is max level 3 and each level changes what you see on the plane.
A first pick offers only these. Four passives stay as the minority (Fuel Miser, Hot Streak, Lucky Whiskers, Scavenger); the rest of
the old perks are defined but no longer offered (`Tuning.perk_pool`).

| Perk | Unlock | What it does |
| --- | --- | --- |
| Flak Cannon / Wing Pods / Tail Gun | start | fire by themselves at the nearest threat ahead / at the sides / behind; **free**; a kill pays 2-5 s of earnings; cooldown 2.2/1.4/0.8 s, level 3 does double damage |
| Wingman | 60 cans | a drone beside you collects nearby coins (never fuel cans) and takes one hit, then needs 75/58/42 s to recharge; level 3 has two |
| Prop Wash | start | a shockwave ring every 8/5.5/3.5 s (radius 4/5.5/7) shoves small obstacles (kites, balloons, hay) and threats aside, never barns, wires or windmills |
| Tow Banner | 25 close calls | a banner 3.5/6/9 units long collects the coins it sweeps |
| Skywriter | 6 Whisker closes | a smoke trail 4/7/11 long scatters birds and kites (and crows / geese threats) that fly into it |
| Magnet Field | start | an aura 3/4.5/6.5 wide pulls coins in (fuel cans you fly to yourself) |
| Barrel Roll | 20 crates | double-tap for a 0.7 s invulnerable roll; ready every 8/5.5/3.5 s |

The second pick always offers a level-up of the best active perk you hold. A build bar under the fuel gauge shows every perk held with level
pips, and the pick screen shows the build at the top.

## Combos (a perk at level 3 plus its partner)

Gold Rush (Flak + Magnet Field: kills pay double and burst coins), Wing Roll (Wingman + Barrel Roll: the wingman rolls with you and each roll ends in a
coin burst), Shock and Awe (Prop Wash + Wing Pods: the wave also knocks threats down), Banner Ad (Tow Banner + Hot Streak: banner coins pay double),
Smokescreen (Skywriter + Tail Gun: smoke hurts every kind of threat), plus Barnstormer, Fuel Overflow and Golden Whiskers. Combos of retired perks stay
defined but are hidden from the Logbook.

## Swarm pressure

After the opening script a threat "budget" fills at a rate that climbs from 0.10/s (80 s) to 0.70/s (330 s), scaled by the intensity
wave (CALM 0.35, BUILD 0.9, PEAK 1.5, BREATHER 0), and each launch spends its price. The number of threats alive at once climbs
from 1 to 4. Kinds unlock in the order they are introduced.

## Bosses

At 5,000 m and then every 2,500 m a boss arrives with a 2.4 s warning banner and a hit-point bar: **Flash the Falcon** (flies alongside
dropping bombs into your path), **the Thunderhead** (a storm cell calling telegraphed bolts), **the Goose General** (three walls of
geese with a moving gap). Defeating one (guns) pays 1.6 pick-prices in coins, surviving it 0.9; both grant a rare pick (three perks,
level-ups favoured). The opening mini-boss at ~90 s is a **rival crop duster** (3 hit points, slow sacks, big payout).

## Fairness

* Nothing is armed until its telegraph has played (tested), and each telegraph is at least ~1 s.
* A hawk's dive and a bomb's blast are local zones; the plane can always step out of them.
* The drone's lane, the Thunderhead's bolts and a boss's strikes use the lightning rule: never the safe path of a row that is passing,
  never the only open column.
* Crows only launch when every passing row has two or more open columns, and commit (stop homing) once close.
* Geese put their lane above a plane that is against the bottom edge.

## Measuring it

`godot --headless --script tests/threat_sim.gd` (env: `SIM_RUNS`, `SIM_MAX`, `SIM_ONLY=NOPERK|BUILD`, `SIM_TRACE=1` for a timeline,
`SIM_FORCE=hawk|goose|crow|drone`, `SIM_BOSS=0|1|2|mini`, `SIM_SOLID=1` to make obstacles lethal too). The autopilot reacts after
0.2 s, flies at 15 units/s and plans around rows and telegraphs; by default it is a *perfect obstacle pilot* (obstacles cannot hurt it) so
that survival measures the threats. `tests/threat_shots.gd` takes screenshots of each threat and boss (`docs/screens/threats/`).

## Hard rules (no AFK, no immortality)

* **Fuel is flown for.** Only the plane touching a can refuels it (Wingman, Banner and Magnet Field handle coins only). The tank burns faster with
  time (x(1 + 0.38 per minute)) and with speed (x(speed / base speed)^1.35), so a faster world never means more fuel per second. Fuel Miser is a plain
  15/28/40% less burn.
* **Standing still is fatal.** Hawks, geese and crows aim at the plane's current position; the drone may take the plane's column even on the safe
  path; the Thunderhead aims 80% of its bolts at the plane; and from 12 s on, 40% (rising 25% per minute, up to 90%) of the rows put a barn in the
  column the plane is flying in (`Spawner.snipe_chance`), always leaving two or more open columns.
* **No ceiling.** Speed steps never stop (+3 per wave cycle past the table), threat rate, concurrent threats, threat hit points and boss hit points
  keep rising with the run. A hit costs a quarter of the CURRENT tank.
* **Rewards cannot feed back.** Kill, boss and Wing Roll coins are excluded from the earning rate that prices picks, guns' payouts and boss rewards,
  and never bring the next pick sooner.
* **CI guard.** The smoke test flies a zero-input bot, a lazy can-only bot and a skilled bot with every active perk at level 3 and every permanent
  upgrade maxed (`tests/bots.gd`): the AFK bot must die within 45 s, the lazy bot well before the skilled one.
