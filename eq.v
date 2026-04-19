module eq (
    input [31:0] a, b,
    output [31:0] c,
    output busy, done,
    output f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);
    assign c = ~(a ^ b);
    assign busy = 0;
    assign done = 1;
    assign f_inv_op = 0;
    assign f_div_zero = 0;
    assign f_overflow = 0;
    assign f_underflow = 0;
    assign f_inexact = 0;
endmodule
