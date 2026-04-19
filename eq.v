module eq (
    input [31:0] a, b,
    output [31:0] c,
    output busy, done,
    output f_inv_op, f_overflow, f_underflow, f_inexact
);
    //retornos:
    // 1(true)  = 0 01111111 00000000000000000000000
    // 0(false) = 0 00000000 00000000000000000000000

    wire equal = &(~(a^b)); //São iguais desconsiderando casos execepcionais
    wire both_zero = ~( (|(a[30:0])) | (|(b[30:0])) ); // Ambos são zero (incluindo +0 e -0)
    wire NaN = (&(a[30:23]) & (|(a[22:0]))) | (&(b[30:23]) & (|(b[22:0]))); // Algum é NaN

    wire is_true = (equal | both_zero) & ~NaN;

    assign c[31:30] = 0;
    assign c[22:0] = 0;
    assign c[29:23] = {7{ is_true }};

    assign busy = 0;
    assign done = 1;
    
    assign f_inv_op = NaN;
    assign f_overflow = 0;
    assign f_underflow = 0;
    assign f_inexact = 0;

endmodule
