/*
/   Title: Testbench for sp_cmp_unit (IEEE 754 Binary32 Comparison Unit)
/   Author: Samuel Darrall
/   Date: 20-NOV-2026
*/

`include "tb_macros.svh"

module sp_cmp_unit_tb;

    import spau_opcodes::*;

    `TB_SETUP
    `TIMEOUT(100ms)
    `DUMP(sp_cmp_unit_tb)

    localparam logic [31:0] QNAN    = 32'h7FC0_0000;
    localparam logic [31:0] SNAN    = 32'h7F80_0001;
    localparam logic [31:0] P_INF   = 32'h7F80_0000;
    localparam logic [31:0] N_INF   = 32'hFF80_0000;
    localparam logic [31:0] P_ZERO  = 32'h0000_0000;
    localparam logic [31:0] N_ZERO  = 32'h8000_0000;
    localparam logic [31:0] ONE     = 32'h3F80_0000;
    localparam logic [31:0] N_ONE   = 32'hBF80_0000;
    localparam logic [31:0] TWO     = 32'h4000_0000;
    localparam logic [31:0] N_TWO   = 32'hC000_0000;
    localparam logic [31:0] MAX_F   = 32'h7F7F_FFFF;
    localparam logic [31:0] MIN_SUB = 32'h0000_0001;
    localparam logic [31:0] MAX_SUB = 32'h007F_FFFF;
    localparam logic [31:0] MIN_NRM = 32'h0080_0000;
    localparam logic [31:0] TRUE    = 32'hFFFF_FFFF;
    localparam logic [31:0] FALSE   = 32'h0000_0000;

    spau_opcodes_t opcode;
    cmp_opcodes_t  cmp_op;
    logic [31:0]   a, b, c;
    logic [31:0]   result;

    sp_cmp_unit dut (
        .opcode (opcode),
        .cmp_op (cmp_op),
        .a      (a),
        .b      (b),
        .c      (c),
        .result (result)
    );

    bit strict_zero = 0;
    int n_random    = 20000;

    typedef enum {R_LT, R_EQ, R_GT, R_UN} rel_t;

    function automatic bit is_nan(input logic [31:0] x);
        return (x[30:23] == 8'hFF) && (x[22:0] != 23'd0);
    endfunction

    function automatic bit is_zero(input logic [31:0] x);
        return x[30:0] == 31'd0;
    endfunction

    function automatic longint fkey(input logic [31:0] x);
        return x[31] ? -longint'(x[30:0]) : longint'(x[30:0]);
    endfunction

    function automatic rel_t rel_ref(input logic [31:0] x, y);
        if (is_nan(x) || is_nan(y)) return R_UN;
        if (fkey(x) < fkey(y))      return R_LT;
        if (fkey(x) > fkey(y))      return R_GT;
        return R_EQ;
    endfunction

    function automatic rel_t rel_swap(input rel_t r);
        case (r)
            R_LT:    return R_GT;
            R_GT:    return R_LT;
            default: return r;
        endcase
    endfunction

    function automatic logic cmp_bit(input cmp_opcodes_t op, input rel_t r);
        case (op)
            EQ:      return r == R_EQ;
            LT:      return r == R_LT;
            LE:      return r == R_LT || r == R_EQ;
            GT:      return r == R_GT;
            GE:      return r == R_GT || r == R_EQ;
            NE:      return r != R_EQ;
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic [31:0] cmp_ref(input cmp_opcodes_t op, input logic [31:0] x, y);
        return cmp_bit(op, rel_ref(x, y)) ? TRUE : FALSE;
    endfunction

    function automatic logic [31:0] minmax_ref(input bit is_max, input logic [31:0] x, y);
        rel_t r;
        if (is_nan(x) && is_nan(y)) return QNAN;
        if (is_nan(x))              return y;
        if (is_nan(y))              return x;
        if (is_zero(x) && is_zero(y) && x[31] != y[31])
            return is_max ? P_ZERO : N_ZERO;
        r = rel_ref(x, y);
        if (is_max) return (r == R_LT) ? y : x;
        else        return (r == R_GT) ? y : x;
    endfunction

    function automatic logic [31:0] cnd_ref(input logic [31:0] x, y, sel);
        return (sel != 32'd0) ? x : y;
    endfunction

    function automatic cmp_opcodes_t rand_cmp_op();
        return cmp_opcodes_t'($urandom_range(7));
    endfunction

    function automatic logic [31:0] rand_special();
        case ($urandom_range(9))
            0: return P_ZERO;
            1: return N_ZERO;
            2: return P_INF;
            3: return N_INF;
            4: return {1'($urandom), 8'hFF, 23'($urandom) | 23'd1};  // NaN
            5: return {1'($urandom), 8'h00, 23'($urandom)};          // subnormal
            6: return {1'($urandom), 8'h00, 23'($urandom_range(3))}; // tiny subnormal / zero
            7: return {1'($urandom), MIN_NRM[30:0]};
            8: return {1'($urandom), 8'h7F, 23'($urandom)};          // ~1.0
            default: return {1'($urandom), MAX_F[30:0]};
        endcase
    endfunction

    function automatic logic [31:0] rand_near(input logic [31:0] x);
        logic [31:0] y;
        y = x;
        case ($urandom_range(4))
            0: ;
            1: y[31] = ~y[31];
            2: y[30:0] = y[30:0] + 31'($urandom_range(3));
            3: y[30:0] = y[30:0] - 31'($urandom_range(3));
            default: y[30:23] = y[30:23] ^ 8'd1;
        endcase
        return y;
    endfunction


    task automatic apply(input spau_opcodes_t op, input cmp_opcodes_t cop,
                         input logic [31:0] ia, ib, ic);
        opcode = op;
        cmp_op = cop;
        a      = ia;
        b      = ib;
        c      = ic;
        #1;
    endtask

    task automatic check_cmp(input cmp_opcodes_t cop, input logic [31:0] ia, ib,
                             input logic exp_bit = 1'bx);
        logic [31:0] ref_res;
        int          errs_before;

        errs_before = tb_errors;
        ref_res     = cmp_ref(cop, ia, ib);

        if (!$isunknown(exp_bit)) begin
            tb_checks++;
            if (ref_res !== {32{exp_bit}})
                `TB_FAIL($sformatf("reference model: %s(%h,%h) = %h, expected %b",
                                   cop.name(), ia, ib, ref_res, exp_bit))
        end

        apply(CMP, cop, ia, ib, $urandom);
        `CHECK_EQ(result, ref_res)

        if (tb_errors != errs_before)
            $display("        CMP.%s a=%h b=%h  dut=%h ref=%h", cop.name(), ia, ib, result, ref_res);
        else
            `DEBUG($sformatf("CMP.%s a=%h b=%h -> %h", cop.name(), ia, ib, result))
    endtask

    task automatic check_rel(input logic [31:0] x, y, input rel_t rel);
        cmp_opcodes_t op;
        for (int k = 0; k < 6; k++) begin
            op = cmp_opcodes_t'(k);
            check_cmp(op, x, y, cmp_bit(op, rel));
            check_cmp(op, y, x, cmp_bit(op, rel_swap(rel)));
        end
    endtask

    task automatic check_all_cmp(input logic [31:0] x, y);
        for (int k = 0; k < 6; k++)
            check_cmp(cmp_opcodes_t'(k), x, y);
    endtask

    task automatic check_minmax(input bit is_max, input logic [31:0] ia, ib,
                                input logic [31:0] exp_res = 'x);
        logic [31:0] ref_res;
        int          errs_before;
        bit          zero_tie;
        string       name;

        name        = is_max ? "MAX" : "MIN";
        errs_before = tb_errors;
        ref_res     = minmax_ref(is_max, ia, ib);
        zero_tie    = is_zero(ia) && is_zero(ib) && (ia[31] != ib[31]);

        if (!$isunknown(exp_res)) begin
            tb_checks++;
            if (ref_res !== exp_res)
                `TB_FAIL($sformatf("reference model: %s(%h,%h) = %h, expected %h",
                                   name, ia, ib, ref_res, exp_res))
        end

        apply(is_max ? MAX : MIN, rand_cmp_op(), ia, ib, $urandom);

        if (zero_tie && !strict_zero) begin
            tb_checks++;
            if (result !== ia && result !== ib)
                `TB_FAIL($sformatf("result = 0x%0h, expected +0 or -0", result))
        end else begin
            `CHECK_EQ(result, ref_res)
        end

        if (tb_errors != errs_before)
            $display("        %s a=%h b=%h  dut=%h ref=%h", name, ia, ib, result, ref_res);
        else
            `DEBUG($sformatf("%s a=%h b=%h -> %h", name, ia, ib, result))
    endtask

    task automatic check_cnd(input logic [31:0] ia, ib, ic, input logic [31:0] exp_res = 'x);
        logic [31:0] ref_res;
        int          errs_before;

        errs_before = tb_errors;
        ref_res     = cnd_ref(ia, ib, ic);

        if (!$isunknown(exp_res)) begin
            tb_checks++;
            if (ref_res !== exp_res)
                `TB_FAIL($sformatf("reference model: CND(%h,%h,%h) = %h, expected %h",
                                   ia, ib, ic, ref_res, exp_res))
        end

        apply(CND, rand_cmp_op(), ia, ib, ic);
        `CHECK_EQ(result, ref_res)

        if (tb_errors != errs_before)
            $display("        CND a=%h b=%h c=%h  dut=%h ref=%h", ia, ib, ic, result, ref_res);
    endtask

    task automatic check_unsupported(input spau_opcodes_t op, input logic [31:0] ia, ib, ic);
        apply(op, rand_cmp_op(), ia, ib, ic);
        `CHECK_EQ(result, 32'd0)
    endtask

    task automatic check_everything(input logic [31:0] x, y, z);
        check_all_cmp(x, y);
        check_minmax(0, x, y);
        check_minmax(1, x, y);
        check_cnd(x, y, z);
    endtask


    initial begin
        logic [31:0] ra, rb, rc, mask;

        opcode = CMP;
        cmp_op = EQ;
        a      = '0;
        b      = '0;
        c      = '0;

        if (!$value$plusargs("n=%d", n_random)) n_random = 20000;
        strict_zero = $test$plusargs("strict_zero");
        `TB_SEED
        #1;

        `TEST("CMP: ordinary values")
        check_rel(ONE,          TWO,          R_LT);
        check_rel(ONE,          ONE,          R_EQ);
        check_rel(N_ONE,        ONE,          R_LT);
        check_rel(N_TWO,        N_ONE,        R_LT);
        check_rel(ONE,          32'h3F80_0001, R_LT);  // 1 ulp apart
        check_rel(32'h3F7F_FFFF, ONE,         R_LT);  // across exponent boundary
        check_rel(32'hBF80_0001, N_ONE,       R_LT);
        check_rel(32'h4120_0000, 32'h42C8_0000, R_LT); // 10 < 100
        check_rel(32'hC2C8_0000, 32'h4120_0000, R_LT); // -100 < 10

        `TEST("CMP: signed zeros")
        check_rel(P_ZERO, N_ZERO, R_EQ);
        check_rel(P_ZERO, P_ZERO, R_EQ);
        check_rel(N_ZERO, N_ZERO, R_EQ);
        check_rel(N_ZERO, ONE,    R_LT);
        check_rel(N_ONE,  P_ZERO, R_LT);

        `TEST("CMP: subnormals")
        check_rel(P_ZERO,       MIN_SUB,       R_LT);
        check_rel(N_ZERO,       MIN_SUB,       R_LT);
        check_rel(32'h8000_0001, P_ZERO,       R_LT);
        check_rel(32'h8000_0001, N_ZERO,       R_LT);
        check_rel(MIN_SUB,      32'h0000_0002, R_LT);
        check_rel(MIN_SUB,      MIN_SUB,       R_EQ);
        check_rel(32'h8000_0002, 32'h8000_0001, R_LT);
        check_rel(32'h8000_0001, MIN_SUB,      R_LT);
        check_rel(MAX_SUB,      MIN_NRM,       R_LT);
        check_rel(32'h0012_3456, 32'h0012_3457, R_LT);

        `TEST("CMP: infinities")
        check_rel(MAX_F,  P_INF, R_LT);
        check_rel(N_INF,  32'hFF7F_FFFF, R_LT);
        check_rel(N_INF,  P_INF, R_LT);
        check_rel(P_INF,  P_INF, R_EQ);
        check_rel(N_INF,  N_INF, R_EQ);
        check_rel(N_INF,  N_ZERO, R_LT);

        `TEST("CMP: NaN is unordered")
        check_rel(QNAN,          ONE,           R_UN);
        check_rel(QNAN,          QNAN,          R_UN);
        check_rel(SNAN,          SNAN,          R_UN);
        check_rel(SNAN,          P_INF,         R_UN);
        check_rel(32'hFFC0_0000, N_INF,         R_UN);  // negative NaN
        check_rel(32'h7FFF_FFFF, P_ZERO,        R_UN);
        check_rel(32'hFFFF_FFFF, N_ZERO,        R_UN);
        check_rel(QNAN,          MIN_SUB,       R_UN);

        `TEST("CMP: result is all-ones / all-zeros")
        apply(CMP, LT, ONE, TWO, 32'h1234_5678);
        `CHECK_EQ(result, TRUE)
        apply(CMP, GT, ONE, TWO, 32'h1234_5678);
        `CHECK_EQ(result, FALSE)

        `TEST("CMP: undefined cmp_op returns 0")
        for (int k = 6; k < 8; k++) begin
            check_cmp(cmp_opcodes_t'(k), ONE,  ONE,  1'b0);
            check_cmp(cmp_opcodes_t'(k), ONE,  TWO,  1'b0);
            check_cmp(cmp_opcodes_t'(k), TWO,  ONE,  1'b0);
            check_cmp(cmp_opcodes_t'(k), QNAN, ONE,  1'b0);
        end

        `TEST("MIN/MAX: ordinary values")
        check_minmax(0, ONE,   TWO,   ONE);
        check_minmax(1, ONE,   TWO,   TWO);
        check_minmax(0, TWO,   ONE,   ONE);
        check_minmax(1, TWO,   ONE,   TWO);
        check_minmax(0, N_ONE, ONE,   N_ONE);
        check_minmax(1, N_ONE, ONE,   ONE);
        check_minmax(0, N_TWO, N_ONE, N_TWO);
        check_minmax(1, N_TWO, N_ONE, N_ONE);
        check_minmax(0, ONE,   ONE,   ONE);
        check_minmax(1, N_TWO, N_TWO, N_TWO);
        check_minmax(0, ONE,   32'h3F80_0001, ONE);
        check_minmax(1, ONE,   32'h3F80_0001, 32'h3F80_0001);

        `TEST("MIN/MAX: infinities")
        check_minmax(0, N_INF, MAX_F, N_INF);
        check_minmax(1, N_INF, MAX_F, MAX_F);
        check_minmax(0, P_INF, MAX_F, MAX_F);
        check_minmax(1, P_INF, MAX_F, P_INF);
        check_minmax(0, P_INF, N_INF, N_INF);
        check_minmax(1, P_INF, N_INF, P_INF);

        `TEST("MIN/MAX: subnormals")
        check_minmax(0, MIN_SUB,       32'h0000_0002, MIN_SUB);
        check_minmax(1, MIN_SUB,       32'h0000_0002, 32'h0000_0002);
        check_minmax(0, 32'h8000_0001, P_ZERO,        32'h8000_0001);
        check_minmax(1, 32'h8000_0001, P_ZERO,        P_ZERO);
        check_minmax(0, MIN_SUB,       N_ZERO,        N_ZERO);
        check_minmax(1, MIN_SUB,       N_ZERO,        MIN_SUB);
        check_minmax(0, MAX_SUB,       MIN_NRM,       MAX_SUB);
        check_minmax(1, MAX_SUB,       MIN_NRM,       MIN_NRM);

        `TEST("MIN/MAX: signed zeros")
        check_minmax(0, P_ZERO, N_ZERO, N_ZERO);
        check_minmax(0, N_ZERO, P_ZERO, N_ZERO);
        check_minmax(1, P_ZERO, N_ZERO, P_ZERO);
        check_minmax(1, N_ZERO, P_ZERO, P_ZERO);
        check_minmax(0, P_ZERO, P_ZERO, P_ZERO);
        check_minmax(1, N_ZERO, N_ZERO, N_ZERO);

        `TEST("MIN/MAX: NaN handling (number wins, two NaNs -> canonical qNaN)")
        check_minmax(0, QNAN,          ONE,           ONE);
        check_minmax(0, ONE,           QNAN,          ONE);
        check_minmax(1, QNAN,          N_ONE,         N_ONE);
        check_minmax(1, N_ONE,         QNAN,          N_ONE);
        check_minmax(0, SNAN,          TWO,           TWO);
        check_minmax(1, TWO,           SNAN,          TWO);
        check_minmax(0, 32'hFFC0_1234, N_INF,         N_INF);
        check_minmax(1, P_INF,         32'h7FFF_FFFF, P_INF);
        check_minmax(0, QNAN,          N_ZERO,        N_ZERO);
        check_minmax(0, QNAN,          QNAN,          QNAN);
        check_minmax(1, SNAN,          32'hFFC0_1234, QNAN);
        check_minmax(0, 32'hFFFF_FFFF, 32'h7F80_0001, QNAN);

        `TEST("CND: select on c != 0")
        check_cnd(ONE, TWO, TRUE,          ONE);
        check_cnd(ONE, TWO, FALSE,         TWO);
        check_cnd(ONE, TWO, N_ZERO,        ONE);
        check_cnd(ONE, TWO, 32'h0000_0001, ONE);
        check_cnd(ONE, TWO, 32'h7FFF_FFFF, ONE);
        check_cnd(QNAN, N_INF, TRUE,       QNAN);
        check_cnd(QNAN, N_INF, FALSE,      N_INF);
        check_cnd(SNAN, MIN_SUB, FALSE,    MIN_SUB);

        `TEST("CND: chained from CMP result")
        for (int i = 0; i < 64; i++) begin
            ra = ($urandom_range(3) == 0) ? rand_special() : $urandom;
            rb = ($urandom_range(1)) ? rand_near(ra) : $urandom;
            apply(CMP, LT, ra, rb, '0);
            mask = result;
            check_cnd(ra, rb, mask, cmp_ref(LT, ra, rb) == TRUE ? ra : rb);
        end

        `TEST("unsupported opcodes return 0")
        for (int i = 0; i < 16; i++) begin
            ra = $urandom; rb = $urandom; rc = $urandom;
            check_unsupported(FMA,     ra, rb, rc);
            check_unsupported(CVT_F2I, ra, rb, rc);
            check_unsupported(CVT_I2F, ra, rb, rc);
            check_unsupported(BIT,     ra, rb, rc);
        end

        `TEST("random: uniform bit patterns")
        for (int i = 0; i < n_random / 4; i++)
            check_everything($urandom, $urandom, $urandom);

        `TEST("random: specials mixed in")
        for (int i = 0; i < n_random / 4; i++) begin
            ra = ($urandom_range(1)) ? rand_special() : $urandom;
            rb = ($urandom_range(1)) ? rand_special() : $urandom;
            rc = ($urandom_range(1)) ? rand_special() : $urandom;
            check_everything(ra, rb, rc);
        end

        `TEST("random: near-equal pairs")
        for (int i = 0; i < n_random / 4; i++) begin
            ra = ($urandom_range(3) == 0) ? rand_special() : $urandom;
            rb = rand_near(ra);
            check_everything(ra, rb, ($urandom_range(1)) ? 32'd0 : $urandom);
        end

        `TEST("random: subnormal / zero region")
        for (int i = 0; i < n_random / 4; i++) begin
            ra = {1'($urandom), 8'($urandom_range(1)), 23'($urandom)};
            rb = ($urandom_range(1)) ? rand_near(ra) : {1'($urandom), 8'($urandom_range(1)), 23'($urandom)};
            check_everything(ra, rb, $urandom);
        end

        #1;
        `TB_FINISH
    end

endmodule
