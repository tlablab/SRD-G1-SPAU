# SRD-SPAU

An IEEE 754 Binary32 compute pipeline.

## Core Pipeline Operations

| Opcode | Operation | Description               |
| ------ | --------- | ------------------------- |
| `3'd0` | `FMA`     | a.b + c                 |
| `3'd1` | `MIN`     | min(a, b)                 |
| `3'd2` | `MAX`     | max(a, b)                 |
| `3'd3` | `CMP`     | Compare A vs B            |
| `3'd4` | `CND`     | `C[31] ? A : B`           |
| `3'd5` | `CVT_F2I` | Convert FP32 to INT32     |
| `3'd6` | `CVT_I2F` | Convert INT32 to FP32     |
| `3'd7` | `BIT`     | Bitwise logic             |

### CMP_OPS

| Code   | Op   |
| ------ | ---- |
| `3'd0` | `EQ` |
| `3'd1` | `LT` |
| `3'd2` | `LE` |
| `3'd3` | `GT` |
| `3'd4` | `GE` |
| `3'd5` | `NE` |
