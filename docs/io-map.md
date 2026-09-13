# Modbus TCP I/O map

Single source of truth. Three places must match it exactly:

- `codesys/GVL_IO.st` (the table in the header) and `codesys/PLC_PRG.st` (the
  conversion code)
- `godot/scripts/IoMap.gd`
- This file

CODESYS **Modbus TCP Slave Device** mapping:

| Modbus area | Function code | PLC side | Direction |
|---|---|---|---|
| Holding Registers | FC03 read / FC16 write | `%IW` | Godot → PLC |
| Input Registers | FC04 read | `%QW` | PLC → Godot |

Every scan (20 ms by default) Godot first writes holding registers 0–10 with
FC16, then reads input registers 0–15 with FC04.

---

## Godot → PLC — Holding Registers (`g_awMbIn`)

| # | Name | Contents |
|---|---|---|
| 0 | `HALL_UP` | bit *n* = UP call button on floor *n* (momentary) |
| 1 | `HALL_DOWN` | bit *n* = DOWN call button on floor *n* |
| 2 | `CAR_CALL` | bit *n* = in-car button for floor *n* |
| 3 | `CMD` | command bits — see the table below |
| 4 | `FLOOR_ZONE` | bit *n* = car is in the door zone of floor *n* (±60 mm) |
| 5 | `LIMITS` | limit / lock bits — see the table below |
| 6 | `POS_MM` | absolute encoder position [mm], **signed** — the car really can sit below the bottom floor, in the pit, and a controller that cannot see that drives itself into the buffer |
| 7 | `SPEED_MMS` | measured car speed (absolute value) [mm/s] |
| 8 | `DOOR_PMIL` | door position 0–1000 (0 = fully closed) |
| 9 | `LOAD_KG` | car load [kg] |
| 10 | `HEARTBEAT` | increments every scan; if it stays constant for 2 s the PLC treats the link as lost |
| 11–15 | — | reserved |

### `CMD` (register 3) bits

| Bit | Meaning | Bit | Meaning |
|---|---|---|---|
| 0 | Door-open button | 7 | Fault reset button |
| 1 | Door-close button | 8 | Light curtain interrupted |
| 2 | Alarm button | 9 | Drive ready |
| 3 | Emergency stop | 10 | Drive fault |
| 4 | Overload | 11 | Inspection UP |
| 5 | Fire call | 12 | Inspection DOWN |
| 6 | Inspection mode | 13 | Independent service key |
| | | 14 | Firefighter Phase II key |

### `LIMITS` (register 5) bits

| Bit | Meaning | Bit | Meaning |
|---|---|---|---|
| 0 | Top limit switch | 4 | Landing door lock chain closed |
| 1 | Bottom limit switch | 5 | Brake feedback (released) |
| 2 | Door fully-open limit | 6 | Safety chain healthy |
| 3 | Door fully-closed limit | 7 | Overspeed governor healthy |
| | | 8 | Safety gear set (wedges on the rails) |
| | | 9 | Mains supply healthy |
| | | 10 | Levelling vane: car is below the sill |
| | | 11 | Levelling vane: car is above the sill |
| | | 12 | Terminal slowdown cam, top end |
| | | 13 | Terminal slowdown cam, bottom end |
| | | 14 | Door operator stalled at its force limit |

> Bits 6 and 7 are **1 when healthy**; bit 8 is **1 when tripped**. If the Godot
> link drops, the PLC treats bit 6 as 0.

---

## PLC → Godot — Input Registers (`g_awMbOut`)

| # | Name | Contents |
|---|---|---|
| 0 | `DRIVE_CMD` | b0 enable, b1 up, b2 down, b3 brake-release, b4 levelling |
| 1 | `DOOR_CMD` | b0 open, b1 close, b2 nudge (slow forced closing) |
| 2 | `LAMP_HALL_UP` | bit *n* = up call lamp on floor *n* |
| 3 | `LAMP_HALL_DOWN` | bit *n* = down call lamp on floor *n* |
| 4 | `LAMP_CAR` | bit *n* = in-car lamp for floor *n* |
| 5 | `STATUS` | status bits — see the table below |
| 6 | `CUR_FLOOR` | current floor (0 = ground) |
| 7 | `TGT_FLOOR` | target floor; 65535 (`-1`) when there is none |
| 8 | `DIRECTION` | 0 none, 1 up, 2 down |
| 9 | `SPEED_SP` | speed reference given to the drive [mm/s] |
| 10 | `STATE` | main state machine code (below) |
| 11 | `FAULT` | fault code (below) |
| 12 | `HEARTBEAT` | PLC liveness counter (increments every 100 ms) |
| 13 | `DOOR_TIMER` | dwell time remaining [ms] |
| 14 | `PRETORQUE` | pre-torque reference, **signed**, per mille of the torque needed for a full rated-load imbalance (+ = hold the car up) |
| 15 | — | reserved |

### `STATUS` (register 5) bits

| Bit | Meaning | Bit | Meaning |
|---|---|---|---|
| 0 | Moving | 6 | Inspection mode |
| 1 | Door fully open | 7 | Out of service |
| 2 | Door fully closed | 8 | Gong |
| 3 | Overload lamp | 9 | Up arrow |
| 4 | Fault lamp | 10 | Down arrow |
| 5 | Fire mode | 11 | Car lighting |
| — | | 12 | Alarm bell |
| — | | 13 | Battery rescue (ARD) running |
| — | | 14 | Re-levelling at the floor |
| — | | 15 | Independent service |

---

## State codes (`STATE`)

| Code | State | Code | State |
|---|---|---|---|
| 0 | INIT | 8 | DECEL — decelerating |
| 1 | HOMING | 9 | LEVEL — levelling |
| 2 | IDLE | 10 | ARRIVED |
| 3 | DOOR_OPENING | 11 | FAULT |
| 4 | DOOR_OPEN — dwelling | 12 | FIRE |
| 5 | DOOR_CLOSING | 13 | INSPECTION |
| 6 | START | 14 | PARK |
| 7 | TRAVEL | 15 | RESCUE — battery run (ARD) |
| | | 16 | RELEVEL — creeping back to the sill |
| | | 17 | FIRE_PH2 — firefighter operating the car |

## Fault codes (`FAULT`)

| Code | Cause | How to clear |
|---|---|---|
| 0 | No fault | — |
| 1 | Safety chain open / governor | Close the chain, reset |
| 2 | Door timeout (8 s) | Remove the obstruction, reset |
| 3 | Travel timeout (25 s) | Reset |
| 4 | Drive not ready / drive fault | Fix the drive, reset |
| 5 | Terminal limit switch hit | Move the car out of the zone, reset |
| 6 | Encoder and floor sensor disagree | Correct the position, reset |
| 7 | Door lock lost while moving | Reset |
| 8 | Emergency stop | Release the button, reset |
| 9 | Brake feedback disagrees with the command (1 s) | Free the brake, reset |
| 10 | Overspeed — governor electrical contact (115 %, 0.3 s) | Check the drive, reset |
| 11 | Safety gear set — the wedges are gripping the guide rails (governor mechanical trip at 125 %) | **Not resettable from the panel.** Free the wedges by hand at the car, then reset |

Faults latch. A reset is only accepted once the cause is gone (see the reset
condition in `FB_Safety.st`). When a fault occurs all pending calls are cleared;
if the car is inside a door zone the door opens to let passengers out.
