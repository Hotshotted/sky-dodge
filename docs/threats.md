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

All of them can be shot down by the gun perks, and a kill pays coins.

## Gun perks (the first pick)

Flak Cannon (ahead), Wing Pods (sides), Tail Gun (behind). They fire by themselves at the nearest threat in their sector and
range, once per cooldown (levels 1-3: 2.2 / 1.4 / 0.8 s for the Flak), and each shot costs coins (0.7 seconds of what you are
currently earning, at least 2). A kill pays 2-5 seconds of earnings, so a gun that hits pays for itself. Level 3 does double damage
and a wide blast. The first pick of every run offers only these three; the second always offers a level-up of the one you took.

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
