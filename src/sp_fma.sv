/*
/   Title: IEEE 754 Binary32 Fused Mult-Add
/   Author: Samuel Darrall
/   Date: 19-NOV-2026
*/

module sp_fma (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [31:0] a, b, c,
    output logic [31:0] result,
    output logic        valid,
    output logic        busy
);

    localparam logic [31:0] QNAN = 32'h7FC0_0000;

    // replaced by clz_tree.sv
    /*
    function automatic logic [4:0] clz24(input logic [23:0] x);
        clz24 = 5'd24;
        for (int i = 0; i < 24; i++)
            if (x[i]) clz24 = 5'(23 - i);
    endfunction

    function automatic logic [6:0] clz76(input logic [75:0] x);
        clz76 = 7'd76;
        for (int i = 0; i < 76; i++)
            if (x[i]) clz76 = 7'(75 - i);
    endfunction
    */
    // --------------------------------------------------------------------------

    // control

    typedef enum logic [2:0] {
        S_IDLE   = 3'd0,
        S_UNPACK = 3'd1,
        S_MULT   = 3'd2,
        S_ADD    = 3'd3,
        S_LZC    = 3'd4,
        S_SHIFT  = 3'd5,
        S_ROUND  = 3'd6
    } stage_t;

    stage_t stage;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage <= S_IDLE;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            unique case (stage)
                S_IDLE:   if (start) stage <= S_UNPACK;
                S_UNPACK: stage <= S_MULT;
                S_MULT:   stage <= S_ADD;
                S_ADD:    stage <= S_LZC;
                S_LZC:    stage <= S_SHIFT;
                S_SHIFT:  stage <= S_ROUND;
                S_ROUND: begin
                    stage <= S_IDLE;
                    valid <= 1'b1;
                end
                default:  stage <= S_IDLE;
            endcase
        end
    end

    assign busy = (stage != S_IDLE);

    // registers

    // S_IDLE
    logic [31:0]        a_reg, b_reg, c_reg;

    // S_UNPACK
    logic               is_special_reg;
    logic [31:0]        special_result_reg;
    logic               prod_sign_reg, c_sign_reg, c_is_zero_reg;
    logic [23:0]        a_sig_reg, b_sig_reg, c_sig_reg;
    logic signed [10:0] prod_exp_reg;
    logic signed [10:0] c_exp_reg;

    // S_MULT
    logic [47:0]        prod_sig_reg;
    logic [73:0]        c_aligned_reg;
    logic               c_sticky_reg;
    logic signed [10:0] sum_exp_reg;

    // S_ADD
    logic [75:0]        sum_reg;
    logic               res_sign_reg;
    logic               sum_is_zero_reg;

    // S_LZC
    logic signed [11:0] res_exp_reg;
    logic               shift_right_reg;
    logic [6:0]         shift_amt_reg;

    // S_SHIFT
    logic [23:0]        res_mant_reg;
    logic               guard_reg, sticky_reg;
    logic [7:0]         res_exp_field_reg;
    logic               overflow_reg;

    // S_UNPACK

    logic        a_sign, b_sign, c_sign;
    logic [7:0]  a_exp, b_exp, c_exp;
    logic [22:0] a_mant, b_mant, c_mant;

    logic        a_is_zero, b_is_zero, c_is_zero;
    logic        a_is_inf,  b_is_inf,  c_is_inf;
    logic        a_is_nan,  b_is_nan,  c_is_nan;

    logic        prod_sign;
    logic [23:0] a_sig, b_sig;
    logic [7:0]  a_exp_eff, b_exp_eff, c_exp_eff;
    logic [4:0]  a_lead_zeros, b_lead_zeros;

    clz_tree #(.WIDTH(24)) clz24_0 (.in(a_sig), .zero(), .count(a_lead_zeros));
    clz_tree #(.WIDTH(24)) clz24_1 (.in(b_sig), .zero(), .count(b_lead_zeros));

    assign {a_sign, a_exp, a_mant} = a_reg;
    assign {b_sign, b_exp, b_mant} = b_reg;
    assign {c_sign, c_exp, c_mant} = c_reg;

    assign a_is_zero = (a_exp == 8'h00) && (a_mant == '0);
    assign b_is_zero = (b_exp == 8'h00) && (b_mant == '0);
    assign c_is_zero = (c_exp == 8'h00) && (c_mant == '0);
    assign a_is_inf  = (a_exp == 8'hFF) && (a_mant == '0);
    assign b_is_inf  = (b_exp == 8'hFF) && (b_mant == '0);
    assign c_is_inf  = (c_exp == 8'hFF) && (c_mant == '0);
    assign a_is_nan  = (a_exp == 8'hFF) && (a_mant != '0);
    assign b_is_nan  = (b_exp == 8'hFF) && (b_mant != '0);
    assign c_is_nan  = (c_exp == 8'hFF) && (c_mant != '0);

    assign prod_sign = a_sign ^ b_sign;

    assign a_sig = {a_exp != 8'h00, a_mant};
    assign b_sig = {b_exp != 8'h00, b_mant};

    assign a_exp_eff = (a_exp == 8'h00) ? 8'd1 : a_exp;
    assign b_exp_eff = (b_exp == 8'h00) ? 8'd1 : b_exp;
    assign c_exp_eff = (c_exp == 8'h00) ? 8'd1 : c_exp;

    //assign a_lead_zeros = clz24(a_sig);
    //assign b_lead_zeros = clz24(b_sig);

    logic        is_special;
    logic [31:0] special_result;

    always_comb begin
        is_special     = 1'b1;
        special_result = QNAN;
        if (a_is_nan || b_is_nan || c_is_nan)                        special_result = QNAN;
        else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) special_result = QNAN;
        else if (a_is_inf || b_is_inf) begin
             if (c_is_inf && (c_sign != prod_sign))                  special_result = QNAN;
             else                                                    special_result = {prod_sign, 8'hFF, 23'd0};
        end
        else if (c_is_inf)                                           special_result = c_reg;
        else if (a_is_zero || b_is_zero) begin
             if (c_is_zero)                                          special_result = {prod_sign & c_sign, 31'd0};
             else                                                    special_result = c_reg;
        end
        else                                                         is_special     = 1'b0;
    end

    // S_MULT

    logic signed [10:0] c_align_shift_raw;
    logic [6:0]         c_align_shift;
    logic [97:0]        c_aligned;

    assign c_align_shift_raw = prod_exp_reg - c_exp_reg - 11'sd100;

    always_comb begin
        if (c_is_zero_reg || c_align_shift_raw > 11'sd74) c_align_shift = 7'd74;
        else if (c_align_shift_raw < 11'sd0)              c_align_shift = 7'd0;
        else                                              c_align_shift = c_align_shift_raw[6:0];
    end

    assign c_aligned = {c_sig_reg, 74'd0} >> c_align_shift;

    // S_ADD

    logic [75:0] prod_ext, c_ext;
    logic [75:0] sum_p_plus_c, diff_p_minus_c, diff_c_minus_p;
    logic        is_eff_sub;

    assign prod_ext       = {27'd0, prod_sig_reg, 1'b0};
    assign c_ext          = {1'b0, c_aligned_reg, c_sticky_reg};
    assign is_eff_sub     = prod_sign_reg ^ c_sign_reg;
    assign sum_p_plus_c   = prod_ext + c_ext;
    assign diff_p_minus_c = prod_ext - c_ext;
    assign diff_c_minus_p = c_ext - prod_ext;

    // S_LZC

    logic [6:0]         sum_lead_zeros;
    logic signed [11:0] res_exp;
    logic signed [11:0] denorm_shift;

    clz_tree #(.WIDTH(76)) clz76 (.in(sum_reg), .zero(), .count(sum_lead_zeros));
    //assign sum_lead_zeros = clz76(sum_reg);
    assign res_exp        = 12'(sum_exp_reg) - 12'sd99 - $signed({5'd0, sum_lead_zeros});
    assign denorm_shift   = 12'(sum_exp_reg) - 12'sd100;

    // S_SHIFT

    logic [75:0]  norm_left;
    logic [151:0] norm_right;
    logic [75:0]  norm_sum;
    logic         right_shift_lost;

    assign norm_left        = sum_reg << shift_amt_reg;
    assign norm_right       = {sum_reg, 76'd0} >> shift_amt_reg;
    assign norm_sum         = shift_right_reg ? norm_right[151:76] : norm_left;
    assign right_shift_lost = shift_right_reg & (|norm_right[75:0]);

    // S_ROUND

    logic        round_up;
    logic [30:0] rounded_mag;

    assign round_up    = guard_reg & (sticky_reg | res_mant_reg[0]);
    assign rounded_mag = {res_exp_field_reg, res_mant_reg[22:0]} + 31'(round_up);

    // stage reg updates

    always_ff @(posedge clk) begin
        unique case (stage)
            S_IDLE: if (start) begin
                a_reg <= a;
                b_reg <= b;
                c_reg <= c;
            end

            S_UNPACK: begin
                is_special_reg     <= is_special;
                special_result_reg <= special_result;
                prod_sign_reg      <= prod_sign;
                c_sign_reg         <= c_sign;
                c_is_zero_reg      <= c_is_zero;
                a_sig_reg          <= a_sig << a_lead_zeros;
                b_sig_reg          <= b_sig << b_lead_zeros;
                c_sig_reg          <= {c_exp != 8'h00, c_mant};
                prod_exp_reg       <= 11'(a_exp_eff) - 11'(a_lead_zeros) + 11'(b_exp_eff) - 11'(b_lead_zeros);
                c_exp_reg          <= 11'(c_exp_eff);
            end

            S_MULT: begin
                prod_sig_reg  <= a_sig_reg * b_sig_reg;
                c_aligned_reg <= c_aligned[97:24];
                c_sticky_reg  <= |c_aligned[23:0];
                sum_exp_reg   <= (!c_is_zero_reg && c_align_shift_raw < 11'sd0) ? (c_exp_reg + 11'sd100) : prod_exp_reg;
            end

            S_ADD: begin
                if (!is_eff_sub) begin
                    sum_reg      <= sum_p_plus_c;
                    res_sign_reg <= prod_sign_reg;
                end else if (diff_p_minus_c[75]) begin
                    sum_reg      <= diff_c_minus_p;
                    res_sign_reg <= c_sign_reg;
                end else begin
                    sum_reg      <= diff_p_minus_c;
                    res_sign_reg <= prod_sign_reg;
                end
                sum_is_zero_reg <= is_eff_sub && (diff_p_minus_c == '0);
            end

            S_LZC: begin
                res_exp_reg <= res_exp;
                if (res_exp >= 12'sd1) begin
                    shift_right_reg <= 1'b0;
                    shift_amt_reg   <= sum_lead_zeros;
                end else if (denorm_shift >= 12'sd0) begin
                    shift_right_reg <= 1'b0;
                    shift_amt_reg   <= denorm_shift[6:0];
                end else begin
                    shift_right_reg <= 1'b1;
                    shift_amt_reg   <= (denorm_shift < -12'sd76) ? 7'd76 : 7'(-denorm_shift);
                end
            end

            S_SHIFT: begin
                res_mant_reg      <= norm_sum[75:52];
                guard_reg         <= norm_sum[51];
                sticky_reg        <= (|norm_sum[50:0]) | right_shift_lost;
                res_exp_field_reg <= (res_exp_reg >= 12'sd1) ? res_exp_reg[7:0] : 8'd0;
                overflow_reg      <= (res_exp_reg >= 12'sd255);
            end

            S_ROUND: begin
                if (is_special_reg)       result <= special_result_reg;
                else if (sum_is_zero_reg) result <= 32'h0000_0000;
                else if (overflow_reg)    result <= {res_sign_reg, 8'hFF, 23'd0};
                else                      result <= {res_sign_reg, rounded_mag};
            end

            default: ;
        endcase
    end

endmodule
