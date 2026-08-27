# CODESYS setup — step by step

CODESYS V3.5 SP17 or newer. If you do not have a real PLC, **CODESYS Control
Win V3** (the soft PLC) is enough; it can run on the same machine as Godot.

> **Start the soft PLC first.** Control Win ships with CODESYS but does not run
> by itself. Open **CODESYS Control Win SysTray** from the Start menu, then
> right-click the tray icon and choose **Start PLC**. If it is not running, no
> PLC shows up in the device scan.

---

## 1. Project and device

1. **File → New Project → Standard Project**, name: `ElevatorTwin`.
2. Device: your real PLC, or **CODESYS Control Win V3 x64**.
3. Set the `PLC_PRG` language to **ST (Structured Text)**.

## 2. Creating the POUs

Add each file in the `codesys/` folder as the matching object type and paste its
contents. You can keep the header comment at the top of each file.

| Source file | Object to add | Object name |
|---|---|---|
| `DUT_Types.st` | **DUT** × 7 (each `TYPE` block is its own DUT) | `E_LiftState`, `E_Direction`, `E_DoorState`, `E_Fault`, `ST_CallSet`, `ST_LiftInputs`, `ST_LiftOutputs` |
| `GVL_Config.st` | Global Variable List | `GVL_Config` |
| `GVL_IO.st` | Global Variable List | `GVL_IO` |
| `FUN_Bits.st` | **Function** × 2 | `F_GetBit` (BOOL), `F_SetBit` (WORD) |
| `FB_CallRegistry.st` | Function Block | `FB_CallRegistry` |
| `FB_Dispatcher.st` | Function Block | `FB_Dispatcher` |
| `FB_DoorCtrl.st` | Function Block | `FB_DoorCtrl` |
| `FB_Motion.st` | Function Block | `FB_Motion` |
| `FB_Safety.st` | Function Block | `FB_Safety` |
| `FB_LiftCore.st` | Function Block | `FB_LiftCore` |
| `PLC_PRG.st` | Program (the existing `PLC_PRG`) | `PLC_PRG` |

### Methods (skip this and the project will not compile)

The `METHOD ... END_METHOD` blocks in the files are **not pasted into the FB
body**; add each one via right-click on the FB → **Add Object → Method**. Take
the method name and return type from the `METHOD <name> : <type>` line, then
paste the `VAR_INPUT` block below it and the body. Methods without a return type
are untyped (`VOID`).

| FB | Methods (return type) |
|---|---|
| `FB_CallRegistry` | `ServeFloor` (—), `CallAbove` (BOOL), `CallBelow` (BOOL) |
| `FB_Dispatcher` | `StopHere` (BOOL), `CallAtFloor` (BOOL), `AnyAbove` (BOOL), `AnyBelow` (BOOL), `NearestAbove` (INT), `NearestBelow` (INT), `FarthestAbove` (INT), `FarthestBelow` (INT), `NearestAny` (INT) |
| `FB_DoorCtrl` | `Reset` (—) |
| `FB_Motion` | `ResetTimeout` (—), `FloorFromPos` (INT), `BrakeMismatch` (BOOL) |
| `FB_Safety` | `OverspeedTrip` (BOOL) |
| `FB_LiftCore` | no methods |

**17 methods** in total. `godot/tests/st_lint_test.gd` keeps this list honest
(check E): it verifies that every `fbX.Method()` call resolves to a method
declared on the target FB.

`GVL_Config` is used unqualified — constants are referenced directly as
`C_FLOOR_COUNT`. If your project adds `{attribute 'qualified_only'}` by default,
delete that line, otherwise you have to write `GVL_Config.C_FLOOR_COUNT`.

## 3. Task configuration

**Task Configuration → MainTask**:

- Type: **Cyclic**
- Interval: **10 ms** (20 ms works too; the Godot side runs one exchange every
  20 ms)
- `PLC_PRG` must be assigned to this task.

The door and motion timers run on `TIME` constants, so the scan interval does
not change behaviour — only its resolution.

## 4. Modbus TCP Slave Device

1. Right-click the PLC in the device tree → **Add Device → Fieldbus → Ethernet
   Adapter → Ethernet**.
2. Right-click the `Ethernet` node → **Add Device → Modbus → Modbus TCP Slave
   Device**.
3. Open the **Ethernet** node and pick a **Network interface** Godot can reach
   (`lo` / `127.0.0.1` is fine for testing on one machine).
4. **Modbus TCP Slave Device → General** tab:
   - Port: **502**
   - Unit ID: **1**
   - **Holding Registers (%IW)**: at least **16**
   - **Input Registers (%QW)**: at least **16**

### Mapping the addresses

Open the **Modbus TCP Slave Device → Modbus TCP Slave Device I/O Mapping** tab.
Note the real start addresses of the channels — usually `%IW0` and `%QW0`, but
they may differ in your project. Adjust the two lines in `GVL_IO` accordingly:

```iecst
g_awMbIn  AT %IW0 : ARRAY[0..15] OF WORD;   // <- real Holding start address
g_awMbOut AT %QW0 : ARRAY[0..15] OF WORD;   // <- real Input start address
```

If you would rather not use `AT`: delete the `AT %IW0` / `AT %QW0` parts from
those two lines and bind each channel individually in the I/O Mapping tab to
`GVL_IO.g_awMbIn[0]` … `[15]` and `GVL_IO.g_awMbOut[0]` … `[15]`.

Set **Always update variables** to **Enabled 2 (always in bus cycle task)**,
otherwise the registers are only refreshed when they happen to be used.

## 5. Build and download

1. **Build → Generate Code** — there should be no errors.
2. **Online → Login** → download → **Start**.
3. In the `GVL_IO` watch window you should see `g_stOut.eState` = `LS_INIT`.
   Until Godot connects, `g_xTwinOnline` stays FALSE and the elevator does not
   move — that is the expected behaviour (see the heartbeat supervision in
   `PLC_PRG.st`).

## 6. Connecting Godot

In Godot, HUD → **CONTROL SOURCE**:

1. Type the PLC's address in the IP box (`127.0.0.1` on the same machine).
2. Port `502`.
3. Press **Connect**.

Once connected, the top-left line reads **"● CODESYS CONNECTED … rtt N ms"** and
the register table on the right comes alive. `F1` toggles between SoftPLC and
CODESYS — that is how you compare whether the two behave identically in the same
scenario.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "CODESYS OFFLINE … connecting" | The PLC is not running, the port is closed, or a firewall blocks 502. Allow inbound connections for CODESYS Control in Windows Defender. |
| Connects but all registers stay 0 | "Always update variables" is off in the I/O Mapping, or the `%IW/%QW` start addresses do not match `GVL_IO`. |
| Elevator never moves, `eFault = 1` | No heartbeat is arriving. Check whether register 10 written by Godot changes; if the write (FC16) does not work, the slave may have fewer than 16 Holding Registers. |
| `eState` stuck at `LS_INIT` | `xHomed` was never set: the car is not in any floor's door zone. On the Godot side the car starts on the ground floor, so bit 0 of the `FLOOR_ZONE` register should be 1. |
| Car oscillates / does not settle at a floor | The speed or floor-height values differ between `GVL_Config` and `Config.gd`. |
| Modbus exception 2 (illegal data address) | Fewer than 16 registers are defined on the slave. |
| Scan time overrun | Increase the `MainTask` interval from 10 ms to 20 ms. |

## Link-loss test

Stop the PLC while everything is running (**Online → Stop**). Godot treats the
link as lost within 1.5 s; because `PlcLink.fallback_to_soft` is enabled the
SoftPLC takes over and the HUD shows "CODESYS offline → SoftPLC fallback". To
disable that behaviour set `fallback_to_soft = false` in `PlcLink.gd` — then the
car simply stops when the PLC goes away, because it receives no commands.
