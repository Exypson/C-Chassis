<div align="center">

# C-Chassis

<p>A fork of B-Chassis that keeps A-Chassis plugin support and adds live tuning, presets, driving feel and a server-side watchdog.</p>

<p>
  <a href="https://opensource.org/licenses/MPL-2.0"><img src="https://img.shields.io/badge/License-MPL_2.0-blue.svg?style=flat-square" alt="License: MPL-2.0"></a>
  <img src="https://img.shields.io/badge/Rojo-7.7-orange?style=flat-square" alt="Rojo 7.7">
</p>

</div>

## 🔗 Lineage

C-Chassis is forked from [B-Chassis](https://github.com/VanillaEdge/B-Chassis) 1.0.1, which is forked from
[A-Chassis](https://github.com/lisphm/A-Chassis) 1.7.2. Instance names (`A-Chassis Tune`, `A-Chassis Interface`,
`Values`) are kept on purpose, so existing A-Chassis plugins keep working.

## Features

-  **Everything B-Chassis does:** same physics, same Tune values, same plugin support, Input Action System controls.
-  **Modular drive code:** the 1,400-line `Drive` script is split into `Engine`, `Gearbox`, `Steering`,
  `Differential`, `Assists`, `Wheels`, `Input` and `Flip`, sharing one `State` table.
-  **Presets:** set `Tune.Preset` to `"Grip"`, `"Drift"`, `"Offroad"` or `"Truck"`. A preset only overwrites the
  keys it lists; every other Tune value stays yours.
-  **Tune validation:** a Tune that can't drive (ShiftRPM above Redline, no Neutral gear, unknown `Config`...) stops
  the car at startup with every problem listed, instead of failing silently mid-drive.
-  **Live tuner:** press **T** while driving. Adjust torque, steering, springs, differential and brakes; the
  torque/horsepower graph redraws as you go; **Print** writes your changes to the Output window, ready to paste.
-  **Feel layer:** tyre smoke and skid marks driven by real tread slip, speed-based field of view, camera kick on
  crashes.
-  **Watchdog:** while a car is driven, the server checks it against the top speed its gearing allows. Speed hacks and
  teleports reset the car and eject the driver, with a log line.

## Installation

**From a release:**

1. Download `C-Chassis.rbxm` from the Releases page.
2. Drag it into a Roblox Studio place and position it.

**From source** (needs [Rokit](https://github.com/rojo-rbx/rokit)):

```bash
rokit install
rojo build model.project.json -o C-Chassis.rbxm
```

To work on the chassis with the showcase place (a baseplate and a car spawner):

```bash
rojo build -o C-Chassis.rbxlx
rojo serve
```

Open `C-Chassis.rbxlx` in Studio and connect the Rojo plugin.

## Tuning

All values live in the `A-Chassis Tune` module, with a comment on each.

- Pick a starting point with `Tune.Preset`.
- Drive, press **T**, adjust and **Print**.
- Paste the printed lines into the Tune.

The live tuner leaves gearing, redline and the speed limit out on purpose. The server's Watchdog computes top speed from
the Tune it loaded, so change those values in the Tune module itself.

## Project layout

```
src/Car/                       the car: build it as a model, or Rojo maps it to ServerStorage.C-Chassis
  A-Chassis Tune/              Tune config + Presets, Validate, Watchdog
    Initialize/                server: builds the constraints, hands the car to the driver
    A-Chassis Interface/Drive/ client: the drive loop, one module per system
    Plugins/                   Feel, Tuner and the B-Chassis plugins
  Body, Wheels, DriveSeat, Misc    geometry (.rbxmx)
src/server/                    showcase spawner
```

## Plugins

Drop a plugin into `A-Chassis Tune/Plugins`, exactly as with A-Chassis.

- **Reading state:** plugins read the `Values` folder, which C-Chassis keeps in sync.
- **Server code:** a plugin that needs the server can ship a `RemoteEvent` with a `Script` inside it. Initialize moves
  the remote onto the car and enables the script.

## Known limits

- Physics runs on the driver's client, like A-Chassis and B-Chassis. The Watchdog catches impossible motion, not every
  exploit.
- Smoke, skid marks and live-tuner changes are only visible to the driver.

## Credits

- A-Chassis by its original authors and contributors: [lisphm/A-Chassis](https://github.com/lisphm/A-Chassis).
- B-Chassis by VanillaEdge: [VanillaEdge/B-Chassis](https://github.com/VanillaEdge/B-Chassis).

## License

Distributed under the MPL-2.0 License, inherited from A-Chassis and B-Chassis. See `LICENSE`.
