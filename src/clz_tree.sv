/*
/   Title: Count Leading Zeros Tree
/   Author: Samuel Darrall
/   Date: 23-NOV-2026
*/

module clz_tree #(
    parameter int WIDTH = 76
)(
    input logic [WIDTH-1:0] in,
    output logic zero,
    output logic [$clog2(WIDTH)-1:0] count
);
    localparam int P = 1 << $clog2(WIDTH);

    if (WIDTH < 2) begin : g_bad
        $error("clz_tree: WIDTH must be >= 2 (got %0d)", WIDTH);
    end else if (P != WIDTH) begin : g_pad
        clz_tree #(P) u_pad (.in({in, {(P-WIDTH){1'b1}}}), .zero(), .count(count));
        assign zero = ~|in;
    end else if (WIDTH==2) begin
        assign zero = ~|in;
        assign count = ~in[1];
    end else begin
        logic zl, zr;
        logic [$clog2(WIDTH)-2:0] cl, cr;
        clz_tree #(WIDTH/2) u_hi (.in(in[WIDTH-1:WIDTH/2]), .zero(zl), .count(cl));
        clz_tree #(WIDTH/2) u_lo (.in(in[WIDTH/2-1:0]), .zero(zr), .count(cr));
        assign zero = zl & zr;
        assign count = zl ? {1'b1, cr} : {1'b0, cl};
    end

endmodule
