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

    if (WIDTH==2) begin
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
