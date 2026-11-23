/*
/   Title: Testbench for clz_tree (Count Leading Zeros Tree)
/   Author: Samuel Darrall
/   Date: 23-NOV-2026
*/

`include "tb_macros.svh"

module clz_tree_tb;

    `TB_SETUP
    `TIMEOUT(100ms)
    `DUMP(clz_tree_tb)

    localparam int NW   = 11;
    localparam int MAXW = 128;

    function automatic int width_of(input int g);
        case (g)
            7:       return 3;
            8:       return 12;
            9:       return 24;
            10:      return 76;
            default: return 2 << g;
        endcase
    endfunction

    logic [MAXW-1:0] in_bus;
    logic            zero_o [NW];
    logic [7:0]      cnt_o  [NW];

    for (genvar g = 0; g < NW; g++) begin : g_dut
        localparam int W = width_of(g);
        logic [$clog2(W)-1:0] cnt;

        clz_tree #(.WIDTH(W)) dut (
            .in    (in_bus[W-1:0]),
            .zero  (zero_o[g]),
            .count (cnt)
        );

        assign cnt_o[g] = 8'(cnt);
    end

    bit strict_zero = 0;
    int n_random    = 20000;

    function automatic logic [MAXW-1:0] mask_of(input int w);
        return (w >= MAXW) ? '1 : ((MAXW'(1) << w) - 1);
    endfunction

    function automatic int clz_ref(input int w, input logic [MAXW-1:0] x);
        for (int i = w - 1; i >= 0; i--)
            if (x[i]) return w - 1 - i;
        return w;
    endfunction

    function automatic logic [MAXW-1:0] rand_vec();
        logic [MAXW-1:0] v;
        for (int i = 0; i < MAXW; i += 32)
            v[i +: 32] = $urandom;
        return v;
    endfunction

    function automatic logic [MAXW-1:0] rand_lead(input int w);
        int pos;
        pos = $urandom_range(w - 1);
        return (MAXW'(1) << pos) | (rand_vec() & mask_of(pos));
    endfunction

    function automatic logic [MAXW-1:0] rand_sparse();
        logic [MAXW-1:0] v;
        v = '0;
        repeat ($urandom_range(3)) v[$urandom_range(MAXW - 1)] = 1'b1;
        return v;
    endfunction


    task automatic apply(input logic [MAXW-1:0] x);
        in_bus = x;
        #1;
    endtask

    task automatic check_clz(input int g, input logic [MAXW-1:0] x, input int exp_cnt = -1);
        int          w, ref_cnt, errs_before;
        bit          ref_zero;
        logic [MAXW-1:0] xm;

        w           = width_of(g);
        xm          = x & mask_of(w);
        errs_before = tb_errors;
        ref_cnt     = clz_ref(w, xm);
        ref_zero    = (ref_cnt == w);

        if (exp_cnt >= 0) begin
            tb_checks++;
            if (ref_cnt != exp_cnt)
                `TB_FAIL($sformatf("reference model: CLZ%0d(%h) = %0d, expected %0d",
                                   w, xm, ref_cnt, exp_cnt))
        end

        if (in_bus !== x) apply(x);

        `CHECK_EQ(zero_o[g], ref_zero)
        `CHECK_KNOWN(cnt_o[g])
        if (!ref_zero) begin
            `CHECK_EQ(cnt_o[g], 8'(ref_cnt))
        end else if (strict_zero) begin
            `CHECK_EQ(cnt_o[g], 8'(((w & (w - 1)) == 0) ? w - 1 : w))
        end

        if (tb_errors != errs_before)
            $display("        CLZ%0d in=%h  dut=(zero=%b cnt=%0d) ref=(zero=%b cnt=%0d)",
                     w, xm, zero_o[g], cnt_o[g], ref_zero, ref_cnt);
        else
            `DEBUG($sformatf("CLZ%0d in=%h -> zero=%b cnt=%0d", w, xm, zero_o[g], cnt_o[g]))
    endtask

    task automatic check_all_widths(input logic [MAXW-1:0] x);
        apply(x);
        for (int g = 0; g < NW; g++)
            check_clz(g, x);
    endtask


    initial begin
        logic [MAXW-1:0] rv;
        int              w;

        in_bus = '0;

        if (!$value$plusargs("n=%d", n_random)) n_random = 20000;
        strict_zero = $test$plusargs("strict_zero");
        `TB_SEED
        #1;

        `TEST("zero input sets zero flag")
        for (int g = 0; g < NW; g++)
            check_clz(g, '0, width_of(g));

        `TEST("all ones gives 0")
        for (int g = 0; g < NW; g++)
            check_clz(g, '1, 0);

        `TEST("upper bits outside WIDTH are ignored")
        for (int g = 0; g < NW; g++) begin
            w = width_of(g);
            if (w >= MAXW) continue;
            check_clz(g, ~mask_of(w),                      w);
            check_clz(g, ~mask_of(w) | MAXW'(1),           w - 1);
            check_clz(g, ~mask_of(w) | (MAXW'(1) << (w-1)), 0);
        end

        `TEST("one-hot: every bit position")
        for (int g = 0; g < NW; g++) begin
            w = width_of(g);
            for (int i = 0; i < w; i++)
                check_clz(g, MAXW'(1) << i, w - 1 - i);
        end

        `TEST("leading one with ones below it")
        for (int g = 0; g < NW; g++) begin
            w = width_of(g);
            for (int i = 0; i < w; i++)
                check_clz(g, mask_of(i + 1), w - 1 - i);
        end

        `TEST("leading one with random bits below it")
        for (int g = 0; g < NW; g++) begin
            w = width_of(g);
            for (int i = 0; i < w; i++)
                check_clz(g, (MAXW'(1) << i) | (rand_vec() & mask_of(i)), w - 1 - i);
        end

        `TEST("exhaustive: widths 2 .. 16")
        for (int g = 0; g < NW; g++) begin
            w = width_of(g);
            if (w > 16) continue;
            for (int x = 0; x < (1 << w); x++)
                check_clz(g, MAXW'(x));
        end

        `TEST("random: uniform bit patterns")
        for (int i = 0; i < n_random / 4; i++)
            check_all_widths(rand_vec());

        `TEST("random: sparse vectors")
        for (int i = 0; i < n_random / 4; i++)
            check_all_widths(rand_sparse());

        `TEST("random: leading one placed per width")
        for (int i = 0; i < n_random / 4; i++)
            for (int g = 0; g < NW; g++)
                check_clz(g, rand_lead(width_of(g)));

        `TEST("random: short prefixes (small counts)")
        for (int i = 0; i < n_random / 4; i++) begin
            rv = rand_vec() >> $urandom_range(7);
            rv = (rv == '0) ? MAXW'(1) : rv;
            check_all_widths(rv);
        end

        #1;
        `TB_FINISH
    end

endmodule
