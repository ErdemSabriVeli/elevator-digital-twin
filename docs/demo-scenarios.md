# Demo scenarios

Scenarios to run by hand, for a demo or for verification. Each one must produce
the same result in SoftPLC and in CODESYS mode — switch with `F1` and repeat.

---

## 1. Basic trip and levelling

1. Camera: `1` (exterior), then `F` (follow the car).
2. Press **4** on the car panel.
3. What to watch:
   - `STATE` sequence: `DOOR CLOSING → START → TRAVEL → DECEL → LEVELLING → ARRIVED`
   - `SPEED_SP` rises to 1600 mm/s, starts dropping 2000 mm out, and becomes
     150 mm/s inside the door zone.
   - Once stopped, the deviation on the `Position` line is within ±8 mm.
   - The counterweight moves the opposite way and the sheave turns.

## 2. Collective control

1. With the car on the ground floor, press **5**.
2. While the car travels up, place a **floor 3 → up** hall call.
3. The car stops at 3, opens the door, then continues to 5 — with an opposite
   direction call (floor 3 down) it would not have stopped; it would finish 5
   first.

## 3. Light curtain

1. Go to a floor and let the door open.
2. As the door starts closing, press **"Passenger passed (pulse)"**.
3. The door returns to fully open and the dwell timer restarts.
4. Hold the **"Light curtain always blocked"** switch on for 15 s → **nudge**
   engages and the door tries to close slowly (`DOOR_CMD` bit 2 = 1).

## 4. Overload

1. Arrive at a floor and let the door open.
2. Drag the load slider to **750 kg** (the limit is 693 kg).
3. The `OVERLOAD` lamp lights, the door will not close, and no start happens
   even if you place a new call.
4. Lower the load → the trip resumes.

## 5. Emergency stop and fault reset

1. Press `E` while the car is moving.
2. The car stops, `FAULT 8: Emergency stop`, the indicator blinks, calls are
   cleared.
3. Release with `E`, reset with `R` → the fault clears and the car returns to
   `INIT → IDLE`.
4. It is correct that it does not move without a new call (faults clear the
   calls).

**Reset refusal:** press `R` while emergency stop is still engaged — the fault
does not clear. The reset condition in `FB_Safety.st` requires the cause to be
gone.

## 6. Safety chain

1. Turn on the **"Safety chain BROKEN"** switch.
2. `FAULT 1`, the car stops, the car lighting goes out.
3. Turn it off and reset → back to normal.

## 7. Fire scenario

1. Send the car to one of the upper floors.
2. Turn on the **"Fire mode"** switch.
3. All calls are cleared, the car descends to the ground floor, the door opens
   and **stays open**.
4. The landing indicators show `F`. Turning the switch off returns the car to
   normal service.

## 8. Inspection (car-top control)

1. Turn on the **"Inspection mode"** switch → the indicator shows `R` and calls
   are refused.
2. Hold `PgUp` / `PgDn` → the car moves at 300 mm/s and stops the instant you
   let go.
3. Turn the switch off → normal service resumes via `INIT`.

## 9. Link loss (CODESYS mode only)

1. In CODESYS: **Online → Stop**.
2. Godot notices within 1.5 s; the HUD shows "CODESYS offline → SoftPLC
   fallback" and the simulation continues without interruption.
3. **Start** → the real PLC takes over again.

The other direction: close Godot and, in the CODESYS watch window,
`g_xTwinOnline` goes FALSE after 2 s, `g_stIn.xSafetyChain` is forced FALSE and
the elevator refuses to move.

## 10. Encoder drift

1. Turn on the **"Rope slip (encoder)"** switch and run a few trips.
2. When the encoder position and the floor sensor disagree, `FAULT 6` is raised.
   This demonstrates that the cross-check between the floor sensor and the
   absolute position works.

---

## Automated run

Most of the scenarios above are also written as regression tests:

```bash
godot --headless --path godot --script res://tests/sim_test.gd
```

Run this after any change to the control logic — and remember to mirror every
change you make on the ST side into `SoftPlc.gd`.
