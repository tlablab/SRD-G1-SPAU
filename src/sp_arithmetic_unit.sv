/*
/   Title: IEEE 754 Binary32 Arithmetic Unit Core
/   Author: Samuel Darrall
/   Date: 19-NOV-2026
*/

`include "spau_opcodes.svh"

module sp_arithmetic_unit
    import spau_opcodes::*;
(
    input  logic           clk,
    input  logic           rst_n,
    input  logic           valid_in,
    input  logic           stall,
    input  logic [4:0]     dst_reg_in,
    input  logic           exec_mask_in,
    input  logic [31:0]    op_a, op_b, op_c,
    input  spau_opcodes_t  opcode,
    input  logic [2:0]     abs, neg, // flags for A,B,C respectively
    input  cmp_opcodes_t   cmp_op,
    input  bit_opcodes_t   bit_op,
    input  logic           sat,
    output logic [31:0]    FP32_out,
    output logic [4:0]     dst_reg_out,
    output logic           exec_mask_out,
    output logic           valid_out
);

    logic [26:0] mantissa_in_a;
    logic [26:0] mantissa_in_b;
    logic [26:0] mantissa_in_c;
    logic [7:0]  exponent_in_a;
    logic [7:0]  exponent_in_b;
    logic [7:0]  exponent_in_c;
    logic        sign_a;
    logic        sign_b;
    logic        sign_c;

    logic        is_fp_in;
    logic [31:0] mod_a, mod_b, mod_c;

    assign is_fp_in = (opcode != CVT_I2F) && (opcode != BIT);

    assign mod_a = is_fp_in ? {((op_a[31] & ~abs[0]) ^ neg[0]), op_a[30:0]} : op_a;
    assign mod_b = is_fp_in ? {((op_b[31] & ~abs[1]) ^ neg[1]), op_b[30:0]} : op_b;
    assign mod_c = is_fp_in ? {((op_c[31] & ~abs[2]) ^ neg[2]), op_c[30:0]} : op_c;

    assign a_is_zero = (mod_a[30:23] == 8'd0);
    assign b_is_zero = (mod_b[30:23] == 8'd0);
    assign c_is_zero = (mod_c[30:23] == 8'd0);

    assign mantissa_in_a = a_is_zero ? 27'd0 : {1'b1, mod_a[22:0], 3'd0};
    assign mantissa_in_b = b_is_zero ? 27'd0 : {1'b1, mod_b[22:0], 3'd0};
    assign mantissa_in_c = c_is_zero ? 27'd0 : {1'b1, mod_c[22:0], 3'd0};

    assign exponent_in_a = op_a[30:23];
    assign exponent_in_b = op_b[30:23];
    assign exponent_in_c = op_c[30:23];

    assign sign_a = op_a[31];
    assign sign_b = op_b[31];
    assign sign_c = op_c[31];

    typedef struct packed {
        logic        valid;
        logic [4:0]  dst_reg;
        logic        exec_mask;
        logic        sat;
        spau_opcodes_t opcode;
    } pipe_ctrl_t;

    pipe_ctrl_t ctrl_s1, ctrl_s2, ctrl_s3, ctrl_s4;


endmodule
