// ============================================================================
// MODULO PRINCIPAL: ADD_SUB IEEE 754 (TOP LEVEL)
// ============================================================================
module add_sub (
    input  wire        clock, 
    input  wire        reset, 
    input  wire        start,
    input  wire [31:0] a, 
    input  wire [31:0] b,
    input  wire        op,         // 0: ADD, 1: SUB
    output wire [31:0] c,
    output wire        busy, 
    output wire        done,
    output wire        f_inv_op, 
    output wire        f_div_zero, 
    output wire        f_overflow, 
    output wire        f_underflow, 
    output wire        f_inexact
);

    wire cmd_load_ab, cmd_calc, cmd_finish;

    add_sub_uc UC (
        .clock(clock), .reset(reset), .start(start),
        .cmd_load_ab(cmd_load_ab), .cmd_calc(cmd_calc), .cmd_finish(cmd_finish),
        .busy(busy), .done(done)
    );

    add_sub_fd FD (
        .clock(clock), .reset(reset),
        .a(a), .b(b), .op(op),
        .cmd_load_ab(cmd_load_ab), .cmd_calc(cmd_calc), .cmd_finish(cmd_finish),
        .c(c), .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

endmodule

// ============================================================================
// UNIDADE DE CONTROLE (UC)
// ============================================================================
module add_sub_uc (
    input  wire clock, reset, start,
    output reg  cmd_load_ab, cmd_calc, cmd_finish,
    output reg  busy, done
);
    reg [1:0] state, next_state;
    localparam IDLE = 2'd0, CALC = 2'd1, FINISH = 2'd2;

    always @(posedge clock or posedge reset) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end

    always @(*) begin
        next_state  = state;
        cmd_load_ab = 0; cmd_calc = 0; cmd_finish = 0;
        busy = 1; done = 0;

        case(state)
            IDLE: begin
                busy = 0;
                if (start) begin
                    cmd_load_ab = 1;
                    next_state = CALC;
                end
            end
            CALC: begin
                cmd_finish = 1;
                next_state = FINISH;
            end
            FINISH: begin
                done = 1;
                busy = 0;
                next_state = IDLE;
            end
        endcase
    end
endmodule

// ============================================================================
// FLUXO DE DADOS (FD) - PURAMENTE ESTRUTURAL E COMBINACIONAL
// ============================================================================
module add_sub_fd (
    input  wire clock, reset,
    input  wire [31:0] a, b,
    input  wire op,
    input  wire cmd_load_ab, cmd_calc, cmd_finish,
    
    output reg  [31:0] c,
    output reg  f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

    reg [31:0] reg_A, reg_B;
    reg        reg_Op;

    // --- 1. Extração ---
    wire sign_a = reg_A[31];
    wire [7:0] exp_a = reg_A[30:23];
    wire [22:0] frac_a = reg_A[22:0];

    wire sign_b = reg_B[31];
    wire [7:0] exp_b = reg_B[30:23];
    wire [22:0] frac_b = reg_B[22:0];

    wire sign_b_eff = sign_b ^ reg_Op;

    // --- 2. Decodificação ---
    wire a_is_zero = ~(|exp_a) & ~(|frac_a);
    wire b_is_zero = ~(|exp_b) & ~(|frac_b);
    wire a_is_inf  = (&exp_a)  & ~(|frac_a);
    wire b_is_inf  = (&exp_b)  & ~(|frac_b);
    wire a_is_nan  = (&exp_a)  &  (|frac_a);
    wire b_is_nan  = (&exp_b)  &  (|frac_b);

    wire hidden_a = |exp_a;
    wire hidden_b = |exp_b;
    wire [7:0] exp_a_eff = hidden_a ? exp_a : 8'd1;
    wire [7:0] exp_b_eff = hidden_b ? exp_b : 8'd1;

    wire [26:0] mant_a = {hidden_a, frac_a, 3'b000};
    wire [26:0] mant_b = {hidden_b, frac_b, 3'b000};

    // --- 3. Escolha do Big e Small ---
    wire a_is_bigger = (exp_a_eff > exp_b_eff) || ((exp_a_eff == exp_b_eff) && (mant_a >= mant_b));
    
    wire [7:0]  exp_big    = a_is_bigger ? exp_a_eff : exp_b_eff;
    wire [7:0]  exp_small  = a_is_bigger ? exp_b_eff : exp_a_eff;
    wire [26:0] mant_big   = a_is_bigger ? mant_a    : mant_b;
    wire [26:0] mant_small = a_is_bigger ? mant_b    : mant_a;
    wire        sign_big   = a_is_bigger ? sign_a    : sign_b_eff;
    wire        sign_small = a_is_bigger ? sign_b_eff: sign_a;
    
    wire same_sign = (sign_big == sign_small);

    // --- 4. Alinhamento (Subtrator Estrutural + Barrel Shifter) ---
    wire [7:0] exp_diff;
    n_bit_subtractor #(8) sub_exp_align (
        .a(exp_big), .b(exp_small), .sum(exp_diff), .cout()
    );

    wire [26:0] mant_small_shifted;
    wire align_sticky;
    
    barrel_shifter #(.WIDTH(27), .SHAMT_WIDTH(8)) aligner (
        .in(mant_small), .shamt(exp_diff), .dir(1'b0), // 0 = Right Shift
        .out(mant_small_shifted), .sticky(align_sticky)
    );

    // --- 5. Aritmética Principal (Soma/Sub usando Adder Estrutural) ---
    wire [27:0] mant_big_ext   = {1'b0, mant_big};
    wire [27:0] mant_small_ext = {1'b0, mant_small_shifted};
    
    wire [27:0] mant_sum;
    n_bit_adder #(28) add_mant_sum (
        .a(mant_big_ext), .b(mant_small_ext), .cin(1'b0), .sum(mant_sum), .cout()
    );

    wire [27:0] mant_diff;
    n_bit_adder #(28) add_mant_diff (
        .a(mant_big_ext), .b(~mant_small_ext), .cin(~align_sticky), .sum(mant_diff), .cout()
    );

    wire carry_out = same_sign ? mant_sum[27] : 1'b0;

    // --- 6. Normalização Lógica ---
    function [4:0] count_leading_zeros;
        input [26:0] m;
        integer i;
        begin
            count_leading_zeros = 5'd27;
            for (i = 0; i <= 26; i = i + 1)
                if (m[i]) count_leading_zeros = 5'd26 - i[4:0];
        end
    endfunction

    wire [4:0] lz = count_leading_zeros(mant_diff[26:0]);
    
    wire [4:0] lz_limit;
    n_bit_subtractor #(5) sub_lz_limit (
        .a(exp_big[4:0]), .b(5'd1), .sum(lz_limit), .cout()
    );
    wire [4:0] lz_used = (exp_big == 0) ? 5'd0 : ({3'd0, lz} >= exp_big) ? lz_limit : lz;

    wire [26:0] mant_norm_sub;
    barrel_shifter #(.WIDTH(27), .SHAMT_WIDTH(5)) lsh_norm (
        .in(mant_diff[26:0]), .shamt(lz_used), .dir(1'b1), // 1 = Left Shift
        .out(mant_norm_sub), .sticky() 
    );

    wire [26:0] mant_norm_add = carry_out ? mant_sum[27:1] : mant_sum[26:0];
    wire sticky_add = carry_out ? (mant_sum[0] | align_sticky) : align_sticky;
    wire sticky_sub = align_sticky;

    wire [26:0] mant_norm = same_sign ? {mant_norm_add[26:1], mant_norm_add[0] | sticky_add}
                                      : {mant_norm_sub[26:1], mant_norm_sub[0] | sticky_sub};

    // Ajuste Estrutural do Expoente
    wire [7:0] exp_norm_add, exp_norm_sub;
    n_bit_adder #(8) add_exp_norm (
        .a(exp_big), .b({7'd0, carry_out}), .cin(1'b0), .sum(exp_norm_add), .cout()
    );
    n_bit_subtractor #(8) sub_exp_norm (
        .a(exp_big), .b({3'd0, lz_used}), .sum(exp_norm_sub), .cout()
    );
    wire [7:0] exp_norm = same_sign ? exp_norm_add : exp_norm_sub;

    // --- 7. Arredondamento (Round to Nearest Even) ---
    wire guard_bit  = mant_norm[2];
    wire round_bit  = mant_norm[1];
    wire sticky_bit = mant_norm[0];
    wire round_up   = guard_bit & (round_bit | sticky_bit | mant_norm[3]);

    wire [24:0] mant_rounded;
    n_bit_adder #(25) add_round (
        .a({1'b0, mant_norm[26:3]}), .b(25'd0), .cin(round_up), .sum(mant_rounded), .cout()
    );
    wire round_carry = mant_rounded[24];

    wire [22:0] final_frac = round_carry ? mant_rounded[23:1] : mant_rounded[22:0];
    
    wire [7:0] final_exp;
    n_bit_adder #(8) add_exp_final (
        .a(exp_norm), .b({7'd0, round_carry}), .cin(1'b0), .sum(final_exp), .cout()
    );

    // --- 8. Formatação e Seleção de Saída ---
    wire is_inexact = guard_bit | round_bit | sticky_bit | align_sticky;
    wire result_is_zero = (mant_norm == 27'd0);
    
    // Solução do Paradoxo do Subnormal
    wire is_subnormal = (final_exp == 8'd1) && (mant_rounded[23] == 1'b0);
    wire [7:0] out_exp = is_subnormal ? 8'd0 : final_exp;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            reg_A <= 0; reg_B <= 0; reg_Op <= 0;
            c <= 0; f_inv_op <= 0; f_div_zero <= 0; f_overflow <= 0; f_underflow <= 0; f_inexact <= 0;
        end else begin
            if (cmd_load_ab) begin
                reg_A <= a; reg_B <= b; reg_Op <= op;
                f_inv_op <= 0; f_div_zero <= 0; f_overflow <= 0; f_underflow <= 0; f_inexact <= 0;
            end
            
            if (cmd_finish) begin
                if (a_is_nan | b_is_nan) begin
                    c <= 32'h7FC00000; f_inv_op <= 1;
                end else if (a_is_inf | b_is_inf) begin
                    if (a_is_inf & b_is_inf & ~same_sign) begin
                        c <= 32'h7FC00000; f_inv_op <= 1;
                    end else begin
                        c <= {a_is_inf ? sign_a : sign_b_eff, 8'hFF, 23'd0};
                    end
                end else if (result_is_zero) begin
                    c <= { (sign_a & sign_b_eff), 31'd0 };
                end else if (out_exp >= 8'hFF) begin
                    c <= {sign_big, 8'hFF, 23'd0}; 
                    f_overflow <= 1; f_inexact <= 1;
                end else if (out_exp == 8'd0) begin
                    c <= {sign_big, 8'd0, final_frac}; 
                    f_underflow <= is_inexact; f_inexact <= is_inexact;
                end else begin
                    c <= {sign_big, out_exp, final_frac}; 
                    f_inexact <= is_inexact;
                end
            end
        end
    end
endmodule


// ============================================================================
// MODULOS BASE ESTRUTURAIS (HARDWARE GATES E BARREL SHIFTER)
// ============================================================================

module full_adder (
    input  wire a, b, cin,
    output wire sum, cout
);
    assign sum    = a ^ b ^ cin;
    assign cout = (a & b) | (cin & (a ^ b));
endmodule

module n_bit_adder #(parameter N = 32) (
    input  wire [N-1:0] a, b,
    input  wire         cin,
    output wire [N-1:0] sum,
    output wire         cout
);
    wire [N:0] carry;
    assign carry[0] = cin;
    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : gen_add
            full_adder fa (
                .a(a[k]), .b(b[k]), .cin(carry[k]),
                .sum(sum[k]), .cout(carry[k+1])
            );
        end
    endgenerate
    assign cout = carry[N];
endmodule

module n_bit_subtractor #(parameter N = 32) (
    input  wire [N-1:0] a, b,
    output wire [N-1:0] sum,
    output wire         cout
);
    n_bit_adder #(N) sub_add (
        .a(a), .b(~b), .cin(1'b1),
        .sum(sum), .cout(cout)
    );
endmodule

module barrel_shifter #(
    parameter WIDTH = 27,
    parameter SHAMT_WIDTH = 8
)(
    input  wire [WIDTH-1:0]       in,
    input  wire [SHAMT_WIDTH-1:0] shamt,
    input  wire                   dir,    // 0 = Right Shift, 1 = Left Shift
    output wire [WIDTH-1:0]       out,
    output wire                   sticky
);
    wire [WIDTH-1:0] stage_in     [0:SHAMT_WIDTH];
    wire             stage_sticky [0:SHAMT_WIDTH];

    genvar i, j, k;

    generate
        // ETAPA 1: Reversão de Bits (Left Shift)
        wire [WIDTH-1:0] in_reversed;
        for (i = 0; i < WIDTH; i = i + 1) begin : gen_rev_in
            assign in_reversed[i] = in[WIDTH-1-i];
        end

        assign stage_in[0]     = dir ? in_reversed : in;
        assign stage_sticky[0] = 1'b0;

        // ETAPA 2: Matrizes do Barrel Shifter
        for (j = 0; j < SHAMT_WIDTH; j = j + 1) begin : gen_stages
            localparam SHIFT_VAL = 1 << j;
            
            wire stage_dropped_bits;
            if (SHIFT_VAL < WIDTH) begin : gen_drop_partial
                assign stage_dropped_bits = |stage_in[j][SHIFT_VAL-1 : 0];
            end else begin : gen_drop_all
                assign stage_dropped_bits = |stage_in[j];
            end
            
            assign stage_sticky[j+1] = shamt[j] ? (stage_sticky[j] | stage_dropped_bits) : stage_sticky[j];

            for (k = 0; k < WIDTH; k = k + 1) begin : gen_mux
                if (k + SHIFT_VAL < WIDTH) begin : gen_mux_norm
                    assign stage_in[j+1][k] = shamt[j] ? stage_in[j][k + SHIFT_VAL] : stage_in[j][k];
                end else begin : gen_mux_zero
                    assign stage_in[j+1][k] = shamt[j] ? 1'b0 : stage_in[j][k];
                end
            end
        end

        // ETAPA 3: Reversão de Saída (Left Shift)
        wire [WIDTH-1:0] out_reversed;
        for (i = 0; i < WIDTH; i = i + 1) begin : gen_rev_out
            assign out_reversed[i] = stage_in[SHAMT_WIDTH][WIDTH-1-i];
        end

        // ETAPA 4: Saída e Proteção
        wire overshift = (shamt >= WIDTH);
        assign out = overshift ? {WIDTH{1'b0}} : (dir ? out_reversed : stage_in[SHAMT_WIDTH]);
        assign sticky = dir ? 1'b0 : (overshift ? (|in) : stage_sticky[SHAMT_WIDTH]);

    endgenerate
endmodule

`timescale 1ns/1ps

module tb_add_sub_exhaustive;

    reg clock, reset, start;
    reg [31:0] a, b;
    reg op; // 0 = ADD, 1 = SUB
    
    wire [31:0] c;
    wire busy, done, f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    // Instanciação do DUT (Device Under Test)
    add_sub DUT (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op), .c(c),
        .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero), 
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    always #5 clock = ~clock;

    // Task de teste automatizada (expandida para 35 caracteres na descrição)
    task run_test;
        input [31:0] val_a, val_b;
        input val_op;
        input [8*35:1] name;
        begin
            @(posedge clock);
            a = val_a; b = val_b; op = val_op; start = 1;
            @(posedge clock); start = 0;
            
            wait(done);
            @(posedge clock);
            #1; // Atraso mágico para ler o registrador atualizado
            $display("[%s] %h %c %h = %h | Flags: O:%b U:%b I:%b Inv:%b", 
                     name, val_a, (val_op ? "-" : "+"), val_b, c, 
                     f_overflow, f_underflow, f_inexact, f_inv_op);
        end
    endtask

    initial begin
        clock = 0; reset = 1; start = 0; a = 0; b = 0; op = 0;
        #20 reset = 0;

        $display("\n=========================================================================");
        $display("   BATERIA EXAUSTIVA DE TESTES - ADD/SUB IEEE 754 (ESTRUTURAL)");
        $display("=========================================================================\n");

        $display("--- 1. MATEMÁTICA BÁSICA E SINAIS CRUZADOS ---");
        run_test(32'h40000000, 32'h40000000, 0, "  2.0 +  2.0 =  4.0                ");
        run_test(32'h40000000, 32'h40000000, 1, "  2.0 -  2.0 = +0.0                ");
        run_test(32'h40000000, 32'h40400000, 1, "  2.0 -  3.0 = -1.0                ");
        run_test(32'h40400000, 32'hC0000000, 0, "  3.0 + -2.0 =  1.0                ");
        run_test(32'hC0A00000, 32'hC0000000, 1, " -5.0 - -2.0 = -3.0                ");
        run_test(32'h3FC00000, 32'h40200000, 0, "  1.5 +  2.5 =  4.0                ");

        $display("\n--- 2. CANCELAMENTO CATASTRÓFICO (SHIFT DE NORMALIZAÇÃO) ---");
        // Quando subtraímos números muito próximos, a mantissa zera e o LZC precisa trabalhar duro
        run_test(32'h3F800000, 32'h3F7FFFFF, 1, "  1.0 - 0.99999994 = 2^-24         ");
        run_test(32'h40000000, 32'h3FFFFFFF, 1, "  2.0 - 1.99999988 = 2^-23         ");
        run_test(32'h40800000, 32'h407FFFFF, 1, "  4.0 - 3.99999976 = 2^-22         ");

        $display("\n--- 3. ARREDONDAMENTO (ROUND TO NEAREST EVEN E STICKY BIT) ---");
        // Soma que joga o menor valor exatamente no limite da precisão (Bits: Guard, Round, Sticky)
        run_test(32'h4B000000, 32'h3F800000, 0, "  Grande + 1.0 = (Arredondamento)  ");
        // Empate perfeito (Round=1, Sticky=0). Deve arredondar pro bit par.
        run_test(32'h3F800000, 32'h33800000, 0, "  1.0 + 2^-24  = 1.0 (Tie to Even) ");
        // Mais da metade (Round=1, Sticky=1). Deve arredondar pra cima.
        run_test(32'h3F800000, 32'h33C00000, 0, "  1.0 + 1.5*2^-24 = 1.0 + 2^-23    ");

        $display("\n--- 4. AS REGRAS DO ZERO (+0 E -0) ---");
        run_test(32'h00000000, 32'h00000000, 0, " +0.0 + +0.0 = +0.0                ");
        run_test(32'h80000000, 32'h80000000, 0, " -0.0 + -0.0 = -0.0                ");
        run_test(32'h00000000, 32'h80000000, 0, " +0.0 + -0.0 = +0.0                ");
        run_test(32'h00000000, 32'h00000000, 1, " +0.0 - +0.0 = +0.0                ");
        run_test(32'h80000000, 32'h80000000, 1, " -0.0 - -0.0 = +0.0 (Cancelamento) ");

        $display("\n--- 5. MATEMÁTICA DE SUBNORMAIS (DENORMALIZADOS) ---");
        run_test(32'h00000001, 32'h00000001, 0, "  MinDenorm + MinDenorm            ");
        run_test(32'h007FFFFF, 32'h00000001, 0, "  MaxDenorm + MinDenorm = MinNormal");
        run_test(32'h00800000, 32'h00000001, 1, "  MinNormal - MinDenorm = MaxDenorm");
        run_test(32'h00800000, 32'h00400000, 1, "  MinNormal - Denorm = Denorm      ");
        run_test(32'h3F800000, 32'h00400000, 0, "  1.0 + Denorm = 1.0 (Inexato)     ");

        $display("\n--- 6. OPERAÇÕES COM INFINITOS ---");
        run_test(32'h7F800000, 32'h40000000, 0, " +Inf +  2.0 = +Inf                ");
        run_test(32'hFF800000, 32'h40000000, 0, " -Inf +  2.0 = -Inf                ");
        run_test(32'h7F800000, 32'h7F800000, 0, " +Inf + +Inf = +Inf                ");
        run_test(32'hFF800000, 32'hFF800000, 0, " -Inf + -Inf = -Inf                ");
        run_test(32'h7F800000, 32'hFF800000, 1, " +Inf - -Inf = +Inf                ");

        $display("\n--- 7. OPERAÇÕES INVÁLIDAS (GERAÇÃO E PROPAGAÇÃO DE NaN) ---");
        run_test(32'h7F800000, 32'h7F800000, 1, " +Inf - +Inf = NaN                 ");
        run_test(32'hFF800000, 32'h7F800000, 0, " -Inf + +Inf = NaN                 ");
        run_test(32'h7FC00000, 32'h40000000, 0, "  NaN +  2.0 = NaN                 ");
        run_test(32'h40000000, 32'h7FC00000, 1, "  2.0 -  NaN = NaN                 ");
        run_test(32'h7FC00000, 32'h7FC00000, 0, "  NaN +  NaN = NaN                 ");

        $display("\n--- 8. SATURAÇÃO E LIMITES EXTREMOS (OVERFLOW) ---");
        run_test(32'h7F7FFFFF, 32'h7F7FFFFF, 0, "  Max + Max = +Inf (Overflow)      ");
        run_test(32'hFF7FFFFF, 32'h7F7FFFFF, 1, " -Max - Max = -Inf (Overflow)      ");

        $display("\n=========================================================================");
        $display("                           FIM DOS TESTES");
        $display("=========================================================================\n");

        #50 $finish;
    end
endmodule
