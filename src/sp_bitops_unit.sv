/*
/   Title: Bit Operations Unit
/   Author: Samuel Darrall
/   Date: 24-NOV-2026
*/

`include "spau_opcodes.svh"

module sp_bitops_unit
    import spau_opcodes::*;
(
    input  logic [31:0]   op_a, op_b,
    input  bit_opcodes_t  bit_op,
    output logic [31:0]   result
);

always_comb begin
    unique case (bit_op)
        AND:  result = op_a & op_b;
        OR :  result = op_a | op_b;
        XOR:  result = op_a ^ op_b;
        NOT:  result = ~op_a;
        SHL:  result = op_a << op_b[4:0];
        SHR:  result = op_a >> op_b[4:0];
        SRA:  result = $signed(op_a) >>> op_b[4:0];
        ANDN: result = op_a & ~op_b;
        default: result = 32'd0;
    endcase
end

endmodule
