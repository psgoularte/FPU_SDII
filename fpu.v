module fpu (
    input clock, reset, start,
    input [31:0] a, b,
    input [2:0] op, // ADD, SUB, MUL, DIV, EQ, SLT
    output [31:0] c,
    output busy, done,
    output f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

endmodule