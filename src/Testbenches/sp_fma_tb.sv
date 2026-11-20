/*
/   Title: Testbench for sp_fma (IEEE 754 Binary32 Fused Mult-Add)
/   Author: Samuel Darrall
/   Date: 20-NOV-2026
*/

`include "tb_macros.svh"

module sp_fma_tb;

    `TB_SETUP
    `clock_100m
    `RESET_N(rst_n, 3)
    `TIMEOUT(100ms)
    `DUMP(sp_fma_tb)

    localparam int          LATENCY = 7;
    localparam logic [31:0] QNAN    = 32'h7FC0_0000;
    localparam logic [31:0] P_INF   = 32'h7F80_0000;
    localparam logic [31:0] N_INF   = 32'hFF80_0000;
    localparam logic [31:0] P_ZERO  = 32'h0000_0000;
    localparam logic [31:0] N_ZERO  = 32'h8000_0000;
    localparam logic [31:0] ONE     = 32'h3F80_0000;
    localparam logic [31:0] MAX_F   = 32'h7F7F_FFFF;
    localparam logic [31:0] MIN_SUB = 32'h0000_0001;
    localparam logic [31:0] MIN_NRM = 32'h0080_0000;

    // DUT

    logic        start;
    logic [31:0] a, b, c;
    logic [31:0] result;
    logic        valid, busy;

    sp_fma dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .a      (a),
        .b      (b),
        .c      (c),
        .result (result),
        .valid  (valid),
        .busy   (busy)
    );

    localparam int W   = 600;
    localparam int OFS = 300;

    function automatic logic [31:0] fma_ref(input logic [31:0] fa, fb, fc);
        logic        sa, sb, sc, sp, sr;
        logic [7:0]  ea, eb, ec;
        logic [22:0] ma, mb, mc;
        logic        a_nan, b_nan, c_nan, a_inf, b_inf, c_inf, a_zero, b_zero, c_zero;
        logic [47:0] prod;
        int          ep, ecc, k, e_lead, lsb;
        logic [W-1:0] p_fix, c_fix, m, q, low_mask;
        logic        guard, sticky;
        logic [31:0] bits;

        {sa, ea, ma} = fa;
        {sb, eb, mb} = fb;
        {sc, ec, mc} = fc;
        sp = sa ^ sb;

        a_nan  = (ea == 8'hFF) && (ma != 0);
        b_nan  = (eb == 8'hFF) && (mb != 0);
        c_nan  = (ec == 8'hFF) && (mc != 0);
        a_inf  = (ea == 8'hFF) && (ma == 0);
        b_inf  = (eb == 8'hFF) && (mb == 0);
        c_inf  = (ec == 8'hFF) && (mc == 0);
        a_zero = (ea == 8'h00) && (ma == 0);
        b_zero = (eb == 8'h00) && (mb == 0);
        c_zero = (ec == 8'h00) && (mc == 0);

        if (a_nan || b_nan || c_nan)                 return QNAN;
        if ((a_inf && b_zero) || (b_inf && a_zero))  return QNAN;
        if (a_inf || b_inf) begin
            if (c_inf && (sc != sp))                 return QNAN;
            return {sp, 8'hFF, 23'd0};
        end
        if (c_inf)                                   return fc;
        if (a_zero || b_zero) begin
            if (c_zero)                              return {sp & sc, 31'd0};
            return fc;
        end

        prod  = 48'({ea != 0, ma}) * 48'({eb != 0, mb});
        ep    = ((ea == 0) ? 1 : int'(ea)) - 150 + ((eb == 0) ? 1 : int'(eb)) - 150;
        ecc   = ((ec == 0) ? 1 : int'(ec)) - 150;
        p_fix = W'(prod) << (ep + OFS);
        c_fix = c_zero ? '0 : (W'({ec != 0, mc}) << (ecc + OFS));

        if (sp == sc) begin
            m  = p_fix + c_fix;
            sr = sp;
        end else if (p_fix >= c_fix) begin
            m  = p_fix - c_fix;
            sr = sp;
        end else begin
            m  = c_fix - p_fix;
            sr = sc;
        end

        if (m == 0) return P_ZERO;

        k = 0;
        for (int i = W - 1; i >= 0; i--)
            if (m[i]) begin k = i; break; end
        e_lead = k - OFS;

        lsb = (e_lead >= -126) ? (k - 23) : (OFS - 149);

        q        = m >> lsb;
        guard    = m[lsb - 1];
        low_mask = (W'(1) << (lsb - 1)) - 1;
        sticky   = |(m & low_mask);
        if (guard && (sticky || q[0])) q = q + 1;

        bits = 32'((e_lead >= -126) ? (e_lead + 126) : 0) << 23;
        bits = bits + 32'(q);
        if (bits >= P_INF) return {sr, 8'hFF, 23'd0};
        return {sr, bits[30:0]};
    endfunction


    int n_random = 20000;

    task automatic run_op(input logic [31:0] ia, ib, ic,
                          output logic [31:0] res, output int cycles);
        @(negedge clk);
        a     = ia;
        b     = ib;
        c     = ic;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        a     = 'x;
        b     = 'x;
        c     = 'x;
        cycles = 1;
        while (!valid && cycles < 4 * LATENCY) begin
            @(negedge clk);
            cycles++;
        end
        res = result;
    endtask

    task automatic check_fma(input logic [31:0] ia, ib, ic, input logic [31:0] exp_res = 'x);
        logic [31:0] res, ref_res;
        int          cycles, errs_before;

        errs_before = tb_errors;
        ref_res     = fma_ref(ia, ib, ic);

        if (!$isunknown(exp_res)) begin
            tb_checks++;
            if (ref_res !== exp_res)
                `TB_FAIL($sformatf("reference model: fma(%h,%h,%h) = %h, expected %h",
                                   ia, ib, ic, ref_res, exp_res))
        end

        run_op(ia, ib, ic, res, cycles);

        `CHECK_TRUE(valid)
        `CHECK_EQ(cycles, LATENCY)
        `CHECK_EQ(res, ref_res)

        if (tb_errors != errs_before)
            $display("        a=%h b=%h c=%h  dut=%h ref=%h", ia, ib, ic, res, ref_res);
        else
            `DEBUG($sformatf("a=%h b=%h c=%h -> %h", ia, ib, ic, res))
    endtask

    function automatic logic [31:0] rand_special();
        case ($urandom_range(7))
            0: return P_ZERO;
            1: return N_ZERO;
            2: return P_INF;
            3: return N_INF;
            4: return {1'($urandom), 8'hFF, 23'($urandom) | 23'd1};  // NaN
            5: return {1'($urandom), 8'h00, 23'($urandom)};          // subnormal
            6: return {1'($urandom), 8'h7F, 23'($urandom)};          // ~1.0
            default: return {1'($urandom), MAX_F[30:0]};
        endcase
    endfunction

    function automatic logic [31:0] rand_near_exp(input int e, input int spread);
        int ee;
        ee = e + $urandom_range(2 * spread) - spread;
        if (ee < 0)   ee = 0;
        if (ee > 254) ee = 254;
        return {1'($urandom), 8'(ee), 23'($urandom)};
    endfunction


    initial begin
        logic [31:0] ra, rb, rc;
        int          cycles;

        start = 1'b0;
        a     = '0;
        b     = '0;
        c     = '0;

        if (!$value$plusargs("n=%d", n_random)) n_random = 20000;
        `TB_SEED

        `TEST("reset")
        @(posedge rst_n);
        `TICK_NEG(1)
        `CHECK_EQ(busy, 1'b0)
        `CHECK_EQ(valid, 1'b0)

        `TEST("handshake: busy/valid timing")
        @(negedge clk);
        a = ONE; b = ONE; c = ONE; start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        for (int i = 1; i < LATENCY; i++) begin
            `CHECK_EQ(busy, 1'b1)
            `CHECK_EQ(valid, 1'b0)
            @(negedge clk);
        end
        `CHECK_EQ(valid, 1'b1)
        `CHECK_EQ(busy, 1'b0)
        `CHECK_EQ(result, 32'h4000_0000)  // 1*1+1 = 2
        @(negedge clk);
        `CHECK_EQ(valid, 1'b0)            // single-cycle pulse
        `CHECK_EQ(result, 32'h4000_0000)  // result holds

        `TEST("start ignored while busy")
        @(negedge clk);
        a = 32'h4040_0000; b = 32'h4040_0000; c = P_ZERO; start = 1'b1;  // 3*3+0
        @(negedge clk);
        a = 32'h4100_0000; b = 32'h4100_0000; c = ONE;                    // 8*8+1 (must be ignored)
        repeat (3) @(negedge clk);
        start = 1'b0;
        while (!valid) @(negedge clk);
        `CHECK_EQ(result, 32'h4110_0000)  // 9.0
        `TICK_NEG(2)
        `CHECK_EQ(busy, 1'b0)

        `TEST("basic arithmetic")
        check_fma(ONE,          ONE,          P_ZERO,       ONE);           // 1*1+0
        check_fma(32'h4000_0000, 32'h4040_0000, ONE,         32'h40E0_0000); // 2*3+1 = 7
        check_fma(32'h3FC0_0000, 32'h4000_0000, 32'hC040_0000, P_ZERO);      // 1.5*2-3 = +0
        check_fma(32'hC000_0000, 32'h4040_0000, ONE,         32'hC0A0_0000); // -2*3+1 = -5
        check_fma(32'h3F00_0000, 32'h3F00_0000, 32'h3E80_0000, 32'h3F00_0000); // .5*.5+.25 = .5
        check_fma(32'h4120_0000, 32'h4120_0000, 32'hC2C8_0000, P_ZERO);      // 10*10-100
        check_fma(32'h4120_0000, 32'h4120_0000, 32'hC2C6_0000, ONE);         // 10*10-99 = 1
        check_fma(32'h3DCC_CCCD, 32'h4120_0000, 32'hBF80_0000, 32'h3280_0000); // 0.1f*10-1 = 2^-26 residual

        `TEST("fused (single rounding)")
        check_fma(32'h3F80_0001, 32'h3F80_0001, 32'hBF80_0002, 32'h2880_0000);
        check_fma(32'h3F80_0800, 32'h3F80_0800, 32'hBF80_0000, 32'h3A00_0400);

        `TEST("rounding (RNE)")
        check_fma(ONE, ONE, 32'h3380_0000, ONE);            // 1 + 2^-24: tie -> even (1.0)
        check_fma(32'h3F80_0001, ONE, 32'h3380_0000, 32'h3F80_0002); // 1+2^-23 + 2^-24: tie -> even (up)
        check_fma(ONE, ONE, 32'h3380_0001, 32'h3F80_0001);  // just above tie -> up
        check_fma(ONE, ONE, 32'hB300_0000, ONE);            // 1 - 2^-25 -> 1.0
        check_fma(ONE, ONE, 32'hB380_0000, 32'h3F7F_FFFF);  // 1 - 2^-24 exact
        check_fma(32'h3FFF_FFFF, ONE, 32'h3400_0000, 32'h4000_0000); // carry into exponent

        `TEST("signed zeros")
        check_fma(P_ZERO, ONE,    P_ZERO, P_ZERO);
        check_fma(N_ZERO, ONE,    P_ZERO, P_ZERO);
        check_fma(N_ZERO, ONE,    N_ZERO, N_ZERO);
        check_fma(P_ZERO, ONE,    N_ZERO, P_ZERO);
        check_fma(N_ZERO, N_ZERO, N_ZERO, P_ZERO);
        check_fma(P_ZERO, 32'h4000_0000, 32'h4040_0000, 32'h4040_0000); // 0*2+3 = 3
        check_fma(ONE,    32'hBF80_0000, ONE,  P_ZERO);  // 1*-1+1 = +0

        `TEST("infinities and NaN")
        check_fma(P_INF,  ONE,    ONE,    P_INF);
        check_fma(P_INF,  32'hBF80_0000, ONE, N_INF);
        check_fma(ONE,    ONE,    N_INF,  N_INF);
        check_fma(P_INF,  ONE,    P_INF,  P_INF);
        check_fma(P_INF,  ONE,    N_INF,  QNAN);         // inf - inf
        check_fma(P_INF,  P_ZERO, ONE,    QNAN);         // inf * 0
        check_fma(N_ZERO, N_INF,  ONE,    QNAN);
        check_fma(P_INF,  P_ZERO, 32'h7FC0_1234, QNAN);
        check_fma(32'h7FC0_0001, ONE, ONE, QNAN);
        check_fma(ONE, 32'hFF80_0001, ONE, QNAN);        // signalling NaN
        check_fma(ONE, ONE, 32'h7FFF_FFFF, QNAN);
        check_fma(P_ZERO, ONE, P_INF, P_INF);

        `TEST("overflow")
        check_fma(MAX_F, 32'h4000_0000, P_ZERO, P_INF);
        check_fma(MAX_F, 32'hC000_0000, P_ZERO, N_INF);
        check_fma(MAX_F, ONE,   MAX_F,  P_INF);
        check_fma(MAX_F, ONE,   32'h7300_0000, P_INF);   // + half ulp: tie, odd mantissa -> rounds up to inf
        check_fma(MAX_F, ONE,   32'h72FF_FFFF, MAX_F);   // just under half ulp -> stays
        check_fma(MAX_F, MAX_F, 32'hFF80_0000, N_INF);   // huge product + -inf = -inf
        check_fma(MAX_F, MAX_F, 32'hFF7F_FFFF, P_INF);   // product overflows, c can't pull it back

        `TEST("subnormals")
        check_fma(MIN_SUB, ONE,           P_ZERO,  MIN_SUB);
        check_fma(MIN_SUB, 32'h3F00_0000, P_ZERO,  P_ZERO);   // 2^-150: tie -> even (0)
        check_fma(32'h0000_0003, 32'h3F00_0000, P_ZERO, 32'h0000_0002); // 1.5 ulp -> 2
        check_fma(MIN_SUB, 32'h3F40_0000, P_ZERO,  MIN_SUB);  // 0.75 ulp -> 1
        check_fma(MIN_NRM, 32'h3F00_0000, P_ZERO,  32'h0040_0000);
        check_fma(32'h007F_FFFF, ONE,     MIN_SUB, MIN_NRM);  // subnormal -> normal
        check_fma(MIN_NRM, ONE,           32'h8000_0001, 32'h007F_FFFF); // normal -> subnormal
        check_fma(32'h0040_0000, 32'h4B00_0000, P_ZERO, 32'h0B80_0000); // 2^-127 * 2^23 = 2^-104
        check_fma(32'h0000_1234, 32'h0000_5678, ONE, ONE);    // tiny product
        check_fma(32'h0000_1234, 32'h0000_5678, P_ZERO, P_ZERO); // underflows to +0
        check_fma(32'h8000_1234, 32'h0000_5678, P_ZERO, N_ZERO); // underflows to -0
        check_fma(32'h0012_3456, 32'h5F00_0000, MIN_SUB, 32'h1E91_A2B0); // subnormal * 2^63 + tiny

        `TEST("back-to-back operations")
        for (int i = 0; i < 16; i++) begin
            ra = rand_near_exp(127, 4);
            rb = rand_near_exp(127, 4);
            rc = rand_near_exp(127, 4);
            check_fma(ra, rb, rc);
        end

        `TEST("random: uniform bit patterns")
        for (int i = 0; i < n_random / 4; i++)
            check_fma($urandom, $urandom, $urandom);

        `TEST("random: specials mixed in")
        for (int i = 0; i < n_random / 4; i++) begin
            ra = ($urandom_range(3) == 0) ? rand_special() : rand_near_exp(127, 30);
            rb = ($urandom_range(3) == 0) ? rand_special() : rand_near_exp(127, 30);
            rc = ($urandom_range(3) == 0) ? rand_special() : rand_near_exp(127, 30);
            check_fma(ra, rb, rc);
        end

        `TEST("random: c aligned with product (cancellation)")
        for (int i = 0; i < n_random / 4; i++) begin
            int ea, eb;
            ea = $urandom_range(254);
            eb = $urandom_range(254);
            ra = rand_near_exp(ea, 0);
            rb = rand_near_exp(eb, 0);
            rc = fma_ref(ra, rb, P_ZERO);
            if (rc[30:23] != 8'hFF) begin
                rc[31] = ~rc[31];
                if ($urandom_range(1)) rc[22:0] = rc[22:0] ^ 23'($urandom_range(255));
                if ($urandom_range(3) == 0 && rc[30:23] > 1 && rc[30:23] < 254)
                    rc[30:23] = rc[30:23] + 8'($urandom_range(2)) - 8'd1;
            end
            check_fma(ra, rb, rc);
        end

        `TEST("random: subnormal / underflow region")
        for (int i = 0; i < n_random / 4; i++) begin
            int ea;
            ea = $urandom_range(126);
            ra = rand_near_exp(ea, 10);
            rb = rand_near_exp(127 - ea, 10);
            rc = ($urandom_range(1)) ? rand_near_exp(0, 3) : rand_near_exp(1, 30);
            check_fma(ra, rb, rc);
        end

        `TICK_NEG(2)
        `TB_FINISH
    end

endmodule
