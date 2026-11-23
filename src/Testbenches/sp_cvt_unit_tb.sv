/*
/   Title: Testbench for sp_cvt_unit (IEEE 754 Binary32 <-> INT32 Conversion Unit)
/   Author: Samuel Darrall
/   Date: 23-NOV-2026
*/

`include "tb_macros.svh"

module sp_cvt_unit_tb;

    import spau_opcodes::*;

    `TB_SETUP
    `TIMEOUT(100ms)
    `DUMP(sp_cvt_unit_tb)

    localparam logic [31:0] F2I_NAN_U   = 32'h7FFF_FFFF;
    localparam logic [31:0] F2I_NAN_S   = 32'h8000_0000;

    localparam logic [31:0] QNAN    = 32'h7FC0_0000;
    localparam logic [31:0] SNAN    = 32'h7F80_0001;
    localparam logic [31:0] P_INF   = 32'h7F80_0000;
    localparam logic [31:0] N_INF   = 32'hFF80_0000;
    localparam logic [31:0] P_ZERO  = 32'h0000_0000;
    localparam logic [31:0] N_ZERO  = 32'h8000_0000;
    localparam logic [31:0] ONE     = 32'h3F80_0000;
    localparam logic [31:0] N_ONE   = 32'hBF80_0000;
    localparam logic [31:0] TWO     = 32'h4000_0000;
    localparam logic [31:0] MAX_F   = 32'h7F7F_FFFF;
    localparam logic [31:0] MIN_SUB = 32'h0000_0001;
    localparam logic [31:0] MAX_SUB = 32'h007F_FFFF;
    localparam logic [31:0] MIN_NRM = 32'h0080_0000;
    localparam logic [31:0] P_2_31  = 32'h4F00_0000;
    localparam logic [31:0] N_2_31  = 32'hCF00_0000;
    localparam logic [31:0] INT_MAX = 32'h7FFF_FFFF;
    localparam logic [31:0] INT_MIN = 32'h8000_0000;

    spau_opcodes_t opcode;
    logic          sat;
    logic [31:0]   op_a;
    logic [31:0]   result;

    sp_cvt_unit dut (
        .opcode (opcode),
        .sat    (sat),
        .op_a   (op_a),
        .result (result)
    );

    int n_random = 20000;

    function automatic bit is_nan(input logic [31:0] x);
        return (x[30:23] == 8'hFF) && (x[22:0] != 23'd0);
    endfunction

    function automatic bit is_zero(input logic [31:0] x);
        return x[30:0] == 31'd0;
    endfunction

    function automatic logic [31:0] f2i_ref(input bit s, input logic [31:0] x);
        int     e;
        longint mag;
        longint v;

        if (is_nan(x)) return F2I_NAN_U;

        e = int'(x[30:23]) - 127;
        if (e < 0) return 32'd0;

        if (e > 31) mag = longint'(1) << 32;
        else begin
            mag = longint'({1'b1, x[22:0]});
            mag = (e >= 23) ? (mag << (e - 23)) : (mag >> (23 - e));
        end
        v = x[31] ? -mag : mag;

        if (v > longint'(32'sh7FFF_FFFF) || v < -longint'(64'd2147483648))
            return s ? (x[31] ? INT_MIN : INT_MAX) : F2I_NAN_S;
        return v[31:0];
    endfunction

    function automatic logic [31:0] i2f_ref(input logic [31:0] x);
        logic        s;
        longint      mag, keep, rem, half;
        int          p, sh;

        if (x == 32'd0) return P_ZERO;

        s   = x[31];
        mag = s ? -longint'($signed(x)) : longint'(x);

        p = 0;
        for (int i = 0; i < 32; i++)
            if (mag[i]) p = i;

        if (p <= 23) begin
            keep = mag << (23 - p);
        end else begin
            sh   = p - 23;
            keep = mag >> sh;
            rem  = mag & ((longint'(1) << sh) - 1);
            half = longint'(1) << (sh - 1);
            if (rem > half || (rem == half && keep[0])) keep++;
            if (keep[24]) begin
                keep = keep >> 1;
                p++;
            end
        end

        return {s, 8'(127 + p), keep[22:0]};
    endfunction

    function automatic logic [31:0] rand_special();
        case ($urandom_range(9))
            0: return P_ZERO;
            1: return N_ZERO;
            2: return P_INF;
            3: return N_INF;
            4: return {1'($urandom), 8'hFF, 23'($urandom) | 23'd1};  // NaN
            5: return {1'($urandom), 8'h00, 23'($urandom)};          // subnormal
            6: return {1'($urandom), 8'd126 + 8'($urandom_range(2)), 23'($urandom)};  // ~0.5 .. ~4
            7: return {1'($urandom), 8'd157 + 8'($urandom_range(1)), 23'($urandom)};  // int32 boundary
            8: return {1'($urandom), 8'd150, 23'($urandom)};         // ulp == 1
            default: return {1'($urandom), MAX_F[30:0]};
        endcase
    endfunction

    function automatic logic [31:0] rand_f_inrange();
        return {1'($urandom), 8'($urandom_range(160, 120)), 23'($urandom)};
    endfunction

    function automatic logic [31:0] rand_i_width();
        int          w;
        logic [31:0] m;
        w = $urandom_range(32, 1);
        m = (w == 32) ? 32'hFFFF_FFFF : ((32'd1 << w) - 1);
        return $urandom & m;
    endfunction

    function automatic logic [31:0] rand_i_tie();
        int          p, sh;
        logic [31:0] x, half;
        p    = $urandom_range(31, 24);
        sh   = p - 23;
        half = 32'd1 << (sh - 1);
        x    = (32'd1 << p) | ($urandom & ((32'd1 << p) - 1));
        x    = (x & ~((32'd1 << sh) - 1)) | half;
        case ($urandom_range(2))
            0: ;
            1: x = x + 1;
            default: x = x - 1;
        endcase
        return ($urandom_range(1)) ? -x : x;
    endfunction


    task automatic apply(input spau_opcodes_t op, input logic isat, input logic [31:0] ia);
        opcode = op;
        sat    = isat;
        op_a   = ia;
        #1;
    endtask

    task automatic check_f2i(input logic isat, input logic [31:0] ia,
                             input logic [31:0] exp_res = 'x);
        logic [31:0] ref_res;
        int          errs_before;

        errs_before = tb_errors;
        ref_res     = f2i_ref(isat, ia);

        if (!$isunknown(exp_res)) begin
            tb_checks++;
            if (ref_res !== exp_res)
                `TB_FAIL($sformatf("reference model: F2I(sat=%b,%h) = %h, expected %h",
                                   isat, ia, ref_res, exp_res))
        end

        apply(CVT_F2I, isat, ia);
        `CHECK_EQ(result, ref_res)

        if (tb_errors != errs_before)
            $display("        F2I sat=%b a=%h  dut=%h ref=%h", isat, ia, result, ref_res);
        else
            `DEBUG($sformatf("F2I sat=%b a=%h -> %h", isat, ia, result))
    endtask

    task automatic check_f2i_both(input logic [31:0] ia,
                                  input logic [31:0] exp_nosat = 'x,
                                  input logic [31:0] exp_sat   = 'x);
        check_f2i(1'b0, ia, exp_nosat);
        check_f2i(1'b1, ia, exp_sat);
    endtask

    task automatic check_i2f(input logic [31:0] ia, input logic [31:0] exp_res = 'x);
        logic [31:0] ref_res;
        int          errs_before;

        errs_before = tb_errors;
        ref_res     = i2f_ref(ia);

        if (!$isunknown(exp_res)) begin
            tb_checks++;
            if (ref_res !== exp_res)
                `TB_FAIL($sformatf("reference model: I2F(%h) = %h, expected %h",
                                   ia, ref_res, exp_res))
        end

        apply(CVT_I2F, 1'($urandom), ia);
        `CHECK_EQ(result, ref_res)

        if (tb_errors != errs_before)
            $display("        I2F a=%h (%0d)  dut=%h ref=%h", ia, $signed(ia), result, ref_res);
        else
            `DEBUG($sformatf("I2F a=%h -> %h", ia, result))
    endtask

    task automatic check_passthrough(input spau_opcodes_t op, input logic [31:0] ia);
        apply(op, 1'($urandom), ia);
        `CHECK_EQ(result, ia)
    endtask

    task automatic check_everything(input logic [31:0] x);
        check_f2i_both(x);
        check_i2f(x);
    endtask


    initial begin
        logic [31:0] ra, rf, ri;

        opcode = CVT_F2I;
        sat    = 1'b0;
        op_a   = '0;

        if (!$value$plusargs("n=%d", n_random)) n_random = 20000;
        `TB_SEED
        #1;

        `TEST("F2I: ordinary values")
        check_f2i_both(ONE,           32'h0000_0001, 32'h0000_0001);
        check_f2i_both(N_ONE,         32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check_f2i_both(TWO,           32'h0000_0002, 32'h0000_0002);
        check_f2i_both(32'h42C8_0000, 32'h0000_0064, 32'h0000_0064);  // 100.0
        check_f2i_both(32'hC2C8_0000, 32'hFFFF_FF9C, 32'hFFFF_FF9C);  // -100.0
        check_f2i_both(32'h4E80_0000, 32'h4000_0000, 32'h4000_0000);  // 2^30
        check_f2i_both(32'h4B00_0000, 32'h0080_0000, 32'h0080_0000);  // 2^23
        check_f2i_both(32'h4B7F_FFFF, 32'h00FF_FFFF, 32'h00FF_FFFF);  // 2^24 - 1

        `TEST("F2I: truncates toward zero")
        check_f2i_both(32'h3FC0_0000, 32'h0000_0001, 32'h0000_0001);  //  1.5
        check_f2i_both(32'hBFC0_0000, 32'hFFFF_FFFF, 32'hFFFF_FFFF);  // -1.5
        check_f2i_both(32'h4020_0000, 32'h0000_0002, 32'h0000_0002);  //  2.5
        check_f2i_both(32'h4060_0000, 32'h0000_0003, 32'h0000_0003);  //  3.5
        check_f2i_both(32'hC060_0000, 32'hFFFF_FFFD, 32'hFFFF_FFFD);  // -3.5
        check_f2i_both(32'h3FFF_FFFF, 32'h0000_0001, 32'h0000_0001);  // 1.999...
        check_f2i_both(32'h4AFF_FFFF, 32'h007F_FFFF, 32'h007F_FFFF);  // 2^23 - 0.5

        `TEST("F2I: |x| < 1 gives 0")
        check_f2i_both(P_ZERO,        32'd0, 32'd0);
        check_f2i_both(N_ZERO,        32'd0, 32'd0);
        check_f2i_both(32'h3F00_0000, 32'd0, 32'd0);  //  0.5
        check_f2i_both(32'hBF00_0000, 32'd0, 32'd0);  // -0.5
        check_f2i_both(32'h3F7F_FFFF, 32'd0, 32'd0);  //  0.99999994
        check_f2i_both(32'hBF7F_FFFF, 32'd0, 32'd0);
        check_f2i_both(MIN_SUB,       32'd0, 32'd0);
        check_f2i_both(MAX_SUB,       32'd0, 32'd0);
        check_f2i_both(32'h8000_0001, 32'd0, 32'd0);
        check_f2i_both(MIN_NRM,       32'd0, 32'd0);

        `TEST("F2I: int32 range boundary")
        check_f2i_both(32'h4EFF_FFFF, 32'h7FFF_FF80, 32'h7FFF_FF80);  // largest float < 2^31
        check_f2i_both(32'hCEFF_FFFF, 32'h8000_0080, 32'h8000_0080);
        check_f2i_both(N_2_31,        INT_MIN,       INT_MIN);        // -2^31 is representable
        check_f2i_both(P_2_31,        F2I_NAN_S,     INT_MAX);        //  2^31 overflows
        check_f2i_both(32'h4F00_0001, F2I_NAN_S,     INT_MAX);
        check_f2i_both(32'hCF00_0001, F2I_NAN_S,     INT_MIN);
        check_f2i_both(MAX_F,         F2I_NAN_S,     INT_MAX);
        check_f2i_both(32'hFF7F_FFFF, F2I_NAN_S,     INT_MIN);

        `TEST("F2I: infinities")
        check_f2i_both(P_INF, F2I_NAN_S, INT_MAX);
        check_f2i_both(N_INF, F2I_NAN_S, INT_MIN);

        `TEST("F2I: NaN returns 0x7FFFFFFF")
        check_f2i_both(QNAN,          F2I_NAN_U, F2I_NAN_U);
        check_f2i_both(SNAN,          F2I_NAN_U, F2I_NAN_U);
        check_f2i_both(32'hFFC0_0000, F2I_NAN_U, F2I_NAN_U);  // negative NaN
        check_f2i_both(32'hFF80_0001, F2I_NAN_U, F2I_NAN_U);
        check_f2i_both(32'h7FFF_FFFF, F2I_NAN_U, F2I_NAN_U);
        check_f2i_both(32'hFFFF_FFFF, F2I_NAN_U, F2I_NAN_U);

        `TEST("I2F: exact values")
        check_i2f(32'd0,         P_ZERO);
        check_i2f(32'd1,         ONE);
        check_i2f(32'hFFFF_FFFF, N_ONE);
        check_i2f(32'd2,         TWO);
        check_i2f(32'd100,       32'h42C8_0000);
        check_i2f(-32'd100,      32'hC2C8_0000);
        check_i2f(32'h0080_0000, 32'h4B00_0000);  // 2^23
        check_i2f(32'h00FF_FFFF, 32'h4B7F_FFFF);  // 2^24 - 1
        check_i2f(32'h0100_0000, 32'h4B80_0000);  // 2^24
        check_i2f(32'hFF00_0000, 32'hCB80_0000);  // -2^24
        check_i2f(32'h4000_0000, 32'h4E80_0000);  // 2^30
        check_i2f(32'h7FFF_FF80, 32'h4EFF_FFFF);
        check_i2f(INT_MIN,       N_2_31);

        `TEST("I2F: round to nearest even")
        check_i2f(32'h0100_0001, 32'h4B80_0000);  // 2^24+1: tie, even stays down
        check_i2f(32'h0100_0002, 32'h4B80_0001);  // 2^24+2: exact
        check_i2f(32'h0100_0003, 32'h4B80_0002);  // 2^24+3: tie, odd rounds up
        check_i2f(32'hFEFF_FFFD, 32'hCB80_0002);  // -(2^24+3)
        check_i2f(32'h0200_0001, 32'h4C00_0000);  // 2^25+1: below half, rounds down
        check_i2f(32'h0200_0003, 32'h4C00_0001);  // 2^25+3: above half, rounds up
        check_i2f(32'h0200_0005, 32'h4C00_0001);  // 2^25+5: below half, rounds down
        check_i2f(32'h0200_0006, 32'h4C00_0002);  // 2^25+6: tie, odd rounds up
        check_i2f(32'h7FFF_FF3F, 32'h4EFF_FFFE);  // below half, rounds down
        check_i2f(32'h7FFF_FF7F, 32'h4EFF_FFFF);  // above half, rounds up
        check_i2f(32'h7FFF_FFC0, P_2_31);         // tie, odd -> carries into exponent
        check_i2f(INT_MAX,       P_2_31);         // rounds up to 2^31
        check_i2f(32'h8000_0001, N_2_31);         // -(2^31-1)

        `TEST("I2F: every single-bit power of two")
        for (int i = 0; i < 32; i++) begin
            check_i2f(32'd1 << i);
            check_i2f(-(32'd1 << i));
        end

        `TEST("round trip: F2I(I2F(i)) == i for |i| <= 2^24")
        for (int i = 0; i < 256; i++) begin
            ri = rand_i_width();
            if (ri > 32'h0100_0000 && ri < 32'hFF00_0000) ri = ri >> 8;
            apply(CVT_I2F, 1'b0, ri);
            rf = result;
            check_f2i($urandom_range(1), rf, ri);
        end

        `TEST("round trip: I2F(F2I(f)) == f for integral f")
        for (int i = 0; i < 256; i++) begin
            rf = {1'($urandom), 8'($urandom_range(157, 150)), 23'($urandom)};
            apply(CVT_F2I, 1'b0, rf);
            ri = result;
            check_i2f(ri, rf);
        end

        `TEST("other opcodes pass op_a through")
        for (int i = 0; i < 16; i++) begin
            ra = $urandom;
            check_passthrough(FMA, ra);
            check_passthrough(MIN, ra);
            check_passthrough(MAX, ra);
            check_passthrough(CMP, ra);
            check_passthrough(CND, ra);
            check_passthrough(BIT, ra);
        end

        `TEST("random: uniform bit patterns")
        for (int i = 0; i < n_random / 4; i++)
            check_everything($urandom);

        `TEST("random: specials mixed in")
        for (int i = 0; i < n_random / 4; i++)
            check_everything(($urandom_range(1)) ? rand_special() : $urandom);

        `TEST("random: F2I near int32 range")
        for (int i = 0; i < n_random / 4; i++)
            check_f2i_both(rand_f_inrange());

        `TEST("random: I2F varied widths and rounding ties")
        for (int i = 0; i < n_random / 4; i++) begin
            ri = rand_i_width();
            check_i2f(($urandom_range(1)) ? -ri : ri);
            check_i2f(rand_i_tie());
        end

        #1;
        `TB_FINISH
    end

endmodule
