/*
/   Title: IEEE 754 Binary32 Arithmetic Unit Core Opcodes
/   Author: Samuel Darrall
/   Date: 19-NOV-2026
*/


`ifndef SPAU_OPCODES_SVH
`define SPAU_OPCODES_SVH

package spau_opcodes;

    typedef enum logic [2:0] {
        FMA     = 3'd0,
        MIN     = 3'd1,
        MAX     = 3'd2,
        CMP     = 3'd3,
        CND     = 3'd4,
        CVT_F2I = 3'd5,
        CVT_I2F = 3'd6,
        BIT     = 3'd7
    } spau_opcodes_t;

    typedef enum logic [2:0] {
        EQ = 3'd0,
        LT = 3'd1,
        LE = 3'd2,
        GT = 3'd3,
        GE = 3'd4,
        NE = 3'd5
    } cmp_opcodes_t;

endpackage // opcodes

`endif
