module div_fd(
    input clock, reset,
    input [31:0] a, b,
    output [31:0] c,

    // controle vindo da uc
    input load, prep, shift, sub, restore, set_q1, set_q0, count_en, grs_en, normalize, round, write_result,

    // status para uc
    output a_neg, count_done, grs_done, norm_done,

    // flags IEEE
    output f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);
    // ------------- FLAGS DE ENTRADA -------------
    wire a_is_zero = ~(|a[30:0]);
    wire b_is_zero = ~(|b[30:0]);
    wire a_is_NaN  = (&a[30:23]) & (|a[22:0]);
    wire b_is_NaN  = (&b[30:23]) & (|b[22:0]);

    // Operacao Invalida: 0/0 ou se algum for NaN -----> c = NaN = {x, {31{1'b1}}}
    assign f_inv_op = (a_is_zero & b_is_zero) | a_is_NaN | b_is_NaN;

    // Divisao por Zero: x/0 (onde x != 0) -----> c = +- infinito = {a[31], {8{1'b1}}, {23{1'b0}}}
    assign f_div_zero = b_is_zero & ~a_is_zero & ~a_is_NaN;

    // ------------- CALCULO SINAL ------------------
    assign c[31] = ((a[31]^b[31]) & (~f_inv_op & ~f_div_zero)) | ((a[31] & f_div_zero) | (1'bx)); 

    // ------------- CALCULO EXPOENTE ------------------
    wire [8:0]exp_a_minus_b;
    // exp_a - exp_b + bias
    wire [8:0] exp_calc;

    n_bit_adder #(9) exp_sub (
        .a({1'b0, a[30:23]}),
        .b({1'b1, ~b[30:23]}),
        .cin(1'b1),
        .s(exp_a_minus_b),
        .cout()
    );
    n_bit_adder #(9) exp_add (
        .a(exp_a_minus_b),
        .b(9'd127),
        .cin(1'b0),
        .s(exp_calc),
        .cout()
    ); 

    wire is_nan_any = f_inv_op | f_div_zero;
    // Overflow ocorre se for >= 255 e não for NaN/Div0 
    wire overflow_det = (exp_calc[8] | (&exp_calc[7:0])) & ~is_nan_any;
    // Underflow ocorre se for 0 (ou negativo no bit 8) e nao for zero na entrada   
    // A mantissa pode gerar underflow -> flag apenas apos a divisao
    wire underflow_det= (~(|exp_calc[7:0]) | exp_calc[8]) & (|a[30:0]) & ~is_nan_any;

    wire sel_ff = f_div_zero | f_inv_op | overflow_det;
    wire sel_00 = underflow_det;
    wire sel_norm = ~(sel_ff | sel_00);

    wire [7:0] exp_final = (exp_calc[7:0] & {8{sel_norm}}) | (8'hFF & {8{sel_ff}}) | (8'h00 & {8{sel_00}});

    // ------------- CALCULO MANTISSA ------------------
    
    
endmodule

// Modulos Auxiliares

module full_adder (
    input a, b, cin,
    output s, cout
);
    assign s = a ^ b ^ cin;
    assign cout = (a & b) | (cin & (a ^ b));
endmodule

module n_bit_adder #(parameter N = 32) (
    input [N-1:0] a,
    input [N-1:0] b,
    input cin,
    output [N-1:0] s,
    output cout
);
    wire [N:0] carry;
    assign carry[0] = cin;
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_adder
            full_adder fa_inst (
                .a(a[i]),
                .b(b[i]),
                .cin(carry[i]),
                .s(s[i]),
                .cout(carry[i+1])
            );
        end
    endgenerate
    assign cout = carry[N];
endmodule
