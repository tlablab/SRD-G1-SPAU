/*
/   Title: IEEE 754 Binary32 to SINT Converter
/   Author: Samuel Darrall
/   Date: 22-NOV-2026
*/

module sp_cvt_unit
    import spau_opcodes::*;
(
    input  spau_opcodes_t opcode,
    input  logic          sat,
    input  logic [31:0]   op_a,
    output logic [31:0]   result
);

    localparam logic [31:0] F2I_NAN_U   = 32'h7FFF_FFFF;
    localparam logic [31:0] F2I_NAN_S   = 32'h8000_0000;

    // To be replaced by clz_tree.sv when I can be bothered to make that lol
    function automatic logic [4:0] clz32(input logic [31:0] x);
        clz32 = 5'd0;
        for (int i = 0; i < 32; i++)
            if (x[i]) clz32 = 5'(31 - i);
    endfunction
    // --------------------------------------------------------------------------

    logic        sign;
    logic [7:0]  a_exp;
    logic [22:0] a_mant;
    assign {sign, a_exp, a_mant} = op_a;

    logic [31:0] mag_f, mag_i, norm, clamp;
    logic [7:0] exp_i;
    logic [4:0]  lz;
    logic [30:0] exp_mant;
    logic [22:0] mant_i;
    logic        round_up;

    always_comb begin
        result = '0;
        mag_f  = '0; mag_i    = '0; norm     = '0;
        lz     = '0; exp_mant = '0; round_up = '0;
        exp_i  = '0; mant_i   = '0;
        clamp  = F2I_NAN_S;

        unique case (opcode)
            CVT_F2I: begin
                if (sat) clamp = sign ? F2I_NAN_S : F2I_NAN_U;

                if      (a_exp == 8'hFF && a_mant != '0) result = F2I_NAN_U;
                else if (a_exp >= 8'd158)                result = clamp;
                else if (a_exp < 8'd127)                 result = '0;
                else begin
                    mag_f  = {1'b1, a_mant, 8'b0} >> (8'd158 - a_exp);
                    result = sign ? -mag_f : mag_f;
                end
            end

            CVT_I2F: begin
                if (op_a == '0) result = '0;
                else begin
                    mag_i =    sign ? -op_a : op_a;
                    lz =       clz32(mag_i);
                    norm =     mag_i << lz;
                    round_up = norm[7] & ((|norm[6:0]) | norm[8]);
                    exp_i =    8'd158 - {3'b000, lz};
                    mant_i =   norm[30:8];
                    exp_mant = {exp_i, mant_i} + {30'b0, round_up};
                    result =   {sign, exp_mant};
                end
            end

            default: result = op_a;
        endcase
    end

endmodule
