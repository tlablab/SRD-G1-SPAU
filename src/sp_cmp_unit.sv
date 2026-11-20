/*
/   Title: IEEE 754 Binary32 Comparison Unit
/   Author: Samuel Darrall
/   Date: 19-NOV-2026
*/

`include "spau_opcodes.svh"

module sp_cmp_unit
    import spau_opcodes::*;
(
    input  spau_opcodes_t opcode,
    input  cmp_opcodes_t  cmp_op,
    input  logic [31:0]   a, b, c,
    output logic [31:0]   result
);

    localparam logic [31:0] QNAN = 32'h7FC0_0000;

    logic        a_sign, b_sign;
    logic [7:0]  a_exp, b_exp;
    logic [22:0] a_mant, b_mant;

    logic a_is_nan, b_is_nan, any_nan;
    logic a_is_zero, b_is_zero, both_zero;
    logic mag_eq, mag_lt;
    logic a_eq_b, a_lt_b, a_gt_b;
    logic cmp_res;

    always_comb begin
        a_sign = a[31];
        b_sign = b[31];
        a_exp = a[30:23];
        b_exp = b[30:23];
        a_mant = a[22:0];
        b_mant = b[22:0];

        a_is_nan = (a_exp == 8'hff) && (a_mant != 23'd0);
        b_is_nan = (b_exp == 8'hff) && (b_mant != 23'd0);
        any_nan = a_is_nan || b_is_nan;

        a_is_zero = (a_exp == 8'd0);
        b_is_zero = (b_exp == 8'd0);
        both_zero = a_is_zero && b_is_zero;

        mag_eq = (a[30:0] == b[30:0]);
        mag_lt = (a[30:0] <  b[30:0]);

        if (both_zero) begin
            a_eq_b = 1'b1;
            a_lt_b = 1'b0;
            a_gt_b = 1'b0;
        end else if (a_sign != b_sign) begin
            a_eq_b = 1'b0;
            a_lt_b = a_sign;
            a_gt_b = ~a_sign;
        end else begin
            a_eq_b = mag_eq;
            a_lt_b = a_sign ? (~mag_lt && !mag_eq) : mag_lt;
            a_gt_b = a_sign ? mag_lt : (~mag_lt && !mag_eq);
        end

        case (cmp_op)
            EQ: cmp_res = !any_nan && a_eq_b;
            LT: cmp_res = !any_nan && a_lt_b;
            LE: cmp_res = !any_nan && (a_lt_b || a_eq_b);
            GT: cmp_res = !any_nan && a_gt_b;
            GE: cmp_res = !any_nan && (a_gt_b || a_eq_b);
            NE: cmp_res = any_nan || !a_eq_b;
            default: cmp_res = 1'b0;
        endcase

        case (opcode)
            MIN: begin
                if (a_is_nan && b_is_nan) result = QNAN;
                else if (a_is_nan)        result = b;
                else if (b_is_nan)        result = a;
                else                      result = a_lt_b ? a : b;
            end

            MAX: begin
                if (a_is_nan && b_is_nan) result = QNAN;
                else if (a_is_nan)        result = b;
                else if (b_is_nan)        result = a;
                else                      result = a_gt_b ? a : b;
            end

            CMP: begin
                result = cmp_res ? 32'hffff_ffff : 32'd0;
            end

            CND: begin
                result = (c != 32'd0) ? a : b;
            end

            default: result = 32'd0;
        endcase

    end

endmodule
