# SRD-SPAU

An IEEE 754 Binary32 compute pipeline.

## Core Pipeline Operations

| Opcode | Operation | Description               |
| ------ | --------- | ------------------------- |
| `3'd0` | `FMA`     | a.b + c                   |
| `3'd1` | `MIN`     | min(a, b)                 |
| `3'd2` | `MAX`     | max(a, b)                 |
| `3'd3` | `CMP`     | Compare A vs B            |
| `3'd4` | `CND`     | `c != 0 ? A : B`          |
| `3'd5` | `CVT_F2I` | Convert FP32 to INT32     |
| `3'd6` | `CVT_I2F` | Convert INT32 to FP32     |
| `3'd7` | `BIT`     | Bitwise logic             |

## Comparison unit

### CMP_OPS

| Code   | Op   |
| ------ | ---- |
| `3'd0` | `EQ` |
| `3'd1` | `LT` |
| `3'd2` | `LE` |
| `3'd3` | `GT` |
| `3'd4` | `GE` |
| `3'd5` | `NE` |


## Fused multiply addition unit

Currently a single-cycle process, pipelining will come in future.

The 7 stages:
| Stage      | Description                          |
| ---------- | ------------------------------------ |
| `S_IDLE`   | Waits for start                      |
| `S_UNPACK` | Assigns registers                    |
| `S_MULT`   | a.b                                  |
| `S_ADD`    | product + c                          |
| `S_LZC`    | Sets shift amount register           |
| `S_SHIFT`  | Shifts result to end back at 32 bits |
| `S_ROUND`  | Rounds according to `{G, R, S}`      |

## Conversion unit

### F2I
- Converts bin32 to signed-int and vice versa.
- Truncates towards zero.
- Clamps to `0x80000000` for OOR.
- NaN returns `0x80000000`.

### I2F
- Ints above 2^24 lose precision. Rounds to nearest even.
- Zero in returns positive `0.0`.
