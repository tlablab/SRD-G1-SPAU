# SRD-SPAU

A IEEE 754 Binary32 compute pipeline.

# Core Pipeline Operations

3'd0: FMA, axb+c
3'd1: MIN, min(a,b)
3'd2: MAX, max(a,b)
3'd3: CMP, compare A vs B
3'd4: CND, C[31] ? A : B
3'd5: CVT_F2I, convert FP32 to INT32
3'd6: CVT_I2F, convert INT32 to FP32
3'd7: BIT, bitwise logic

CMP_OPS:
EQ: 3'd0
LT: 3'd1
LE: 3'd2
GT: 3'd3
GE: 3'd4
NE: 3'd5
