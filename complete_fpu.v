module fpu (
    input  wire        clock, reset, start,
    input  wire [31:0] a, b,
    input  wire [2:0]  op, // 000:ADD, 001:SUB, 010:MUL, 011:DIV, 100:EQ, 101:SLT
    output wire [31:0] c,
    output wire        busy, done,
    output wire        f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

    // Sinais internos para cada módulo
    wire [31:0] c_addsub, c_mul, c_div, c_eq, c_slt;
    wire        busy_addsub, busy_mul, busy_div, busy_eq, busy_slt;
    wire        done_addsub, done_mul, done_div, done_eq, done_slt;
    wire        inv_addsub, inv_mul, inv_div, inv_eq, inv_slt;
    wire        overflow_addsub, overflow_mul, overflow_div, overflow_eq, overflow_slt;
    wire        underflow_addsub, underflow_mul, underflow_div, underflow_eq, underflow_slt;
    wire        inexact_addsub, inexact_mul, inexact_div, inexact_eq, inexact_slt;
    wire        div_zero_div;

    // Decodificação do Start (Demultiplexador)
    wire start_addsub = (op == 3'b000 || op == 3'b001) ? start : 1'b0;
    wire start_mul    = (op == 3'b010) ? start : 1'b0;
    wire start_div    = (op == 3'b011) ? start : 1'b0;
    wire start_eq     = (op == 3'b100) ? start : 1'b0;
    wire start_slt    = (op == 3'b101) ? start : 1'b0;

    //Adição e Subtração
    add_sub mod_add_sub (
        .clock(clock), .reset(reset), .start(start_addsub),
        .a(a), .b(b), .op(op[0]),
        .c(c_addsub), .busy(busy_addsub), .done(done_addsub),
        .f_inv_op(inv_addsub), .f_div_zero(), .f_overflow(overflow_addsub), 
        .f_underflow(underflow_addsub), .f_inexact(inexact_addsub)
    );

    // Instância: Divisão
    div mod_div (
        .clock(clock), .reset(reset), .start(start_div),
        .a(a), .b(b), .c(c_div), .busy(busy_div), .done(done_div),
        .f_inv_op(inv_div), .f_div_zero(div_zero_div), .f_overflow(overflow_div), 
        .f_underflow(underflow_div), .f_inexact(inexact_div)
    );

    // Instância: Igualdade
    eq mod_eq (
        .a(a), .b(b), .c(c_eq), .busy(busy_eq), .done(done_eq),
        .f_inv_op(inv_eq), .f_overflow(overflow_eq), .f_underflow(underflow_eq), .f_inexact(inexact_eq)
    );

    // Instância: SLT (Less Than)
    slt mod_slt (
        .a(a), .b(b), .c(c_slt), .busy(busy_slt), .done(done_slt),
        .f_inv_op(inv_slt), .f_overflow(overflow_slt), .f_underflow(underflow_slt), .f_inexact(inexact_slt)
    );

    // Placeholder para Multiplicação (conectar aqui quando o MUL estiver pronto)
    assign c_mul = 32'd0; assign busy_mul = 0; assign done_mul = 0;

    // --- Multiplexação de Saída baseada no OP ---
    assign c           = (op == 3'b011) ? c_div :
                         (op == 3'b100) ? c_eq  :
                         (op == 3'b101) ? c_slt :
                         (op == 3'b010) ? c_mul : c_addsub;

    assign busy        = (op == 3'b011) ? busy_div :
                         (op == 3'b100) ? busy_eq  :
                         (op == 3'b101) ? busy_slt :
                         (op == 3'b010) ? busy_mul : busy_addsub;

    assign done        = (op == 3'b011) ? done_div :
                         (op == 3'b100) ? done_eq  :
                         (op == 3'b101) ? done_slt :
                         (op == 3'b010) ? done_mul : done_addsub;

    // --- Multiplexação de Flags ---
    assign f_inv_op    = (op == 3'b011) ? inv_div :
                         (op == 3'b100) ? inv_eq  :
                         (op == 3'b101) ? inv_slt :
                         (op == 3'b010) ? inv_mul : inv_addsub;

    assign f_div_zero  = (op == 3'b011) ? div_zero_div : 1'b0;

    assign f_overflow  = (op == 3'b011) ? overflow_div :
                         (op == 3'b010) ? overflow_mul : overflow_addsub;

    assign f_underflow = (op == 3'b011) ? underflow_div :
                         (op == 3'b010) ? underflow_mul : underflow_addsub;

    assign f_inexact   = (op == 3'b011) ? inexact_div :
                         (op == 3'b010) ? inexact_mul : inexact_addsub;

endmodule

`timescale 1ns/1ps

module tb_fpu;

    reg clock, reset, start;
    reg [31:0] a, b;
    reg [2:0] op;

    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    // Instanciação da FPU integrada
    fpu DUT (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op),
        .c(c), .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    // Geração de Clock
    always #5 clock = ~clock;

    // Task para simplificar as chamadas de teste
    task run_fpu_test;
        input [31:0] val_a, val_b;
        input [2:0]  val_op;
        input [8*20:1] op_name;
        begin
            @(posedge clock);
            a = val_a; b = val_b; op = val_op; start = 1;
            @(posedge clock); start = 0;
            
            wait(done);
            @(posedge clock);
            #1; // Delay para estabilização dos sinais
            $display("[%s] A:%h, B:%h => Result:%h | Flags(IZVUI): %b%b%b%b%b", 
                     op_name, val_a, val_b, c, f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
        end
    endtask

    initial begin
        // Inicialização
        clock = 0; reset = 1; start = 0; a = 0; b = 0; op = 0;
        #20 reset = 0;

        $display("\n===========================================================");
        $display("       INICIANDO TESTES DE INTEGRACAO DA FPU");
        $display("===========================================================\n");

        // --- TESTES DE SOMA (OP 000) ---
        $display("--- OPERACAO: ADD (000) ---");
        run_fpu_test(32'h40000000, 32'h40000000, 3'b000, "2.0 + 2.0");
        run_fpu_test(32'h7F7FFFFF, 32'h7F7FFFFF, 3'b000, "Overflow Test");

        // --- TESTES DE SUBTRACAO (OP 001) ---
        $display("\n--- OPERACAO: SUB (001) ---");
        run_fpu_test(32'h40800000, 32'h40000000, 3'b001, "4.0 - 2.0");
        run_fpu_test(32'h00800000, 32'h00400000, 3'b001, "Subnormal Res");

        // --- TESTES DE DIVISAO (OP 011) ---
        $display("\n--- OPERACAO: DIV (011) ---");
        run_fpu_test(32'h41400000, 32'h40400000, 3'b011, "12.0 / 3.0");
        run_fpu_test(32'h40A00000, 32'h00000000, 3'b011, "Div by Zero");

        // --- TESTES DE IGUALDADE (OP 100) ---
        $display("\n--- OPERACAO: EQ  (100) ---");
        run_fpu_test(32'h3F800000, 32'h3F800000, 3'b100, "1.0 == 1.0");
        run_fpu_test(32'h00000000, 32'h80000000, 3'b100, "+0.0 == -0.0");
        run_fpu_test(32'h7FC00000, 32'h7FC00000, 3'b100, "NaN == NaN");

        // --- TESTES DE MENOR QUE (OP 101) ---
        $display("\n--- OPERACAO: SLT (101) ---");
        run_fpu_test(32'h40000000, 32'h40800000, 3'b101, "2.0 < 4.0");
        run_fpu_test(32'hC0000000, 32'h3F800000, 3'b101, "-2.0 < 1.0");
        run_fpu_test(32'h40000000, 32'h40000000, 3'b101, "2.0 < 2.0");

        $display("\n===========================================================");
        $display("                FIM DOS TESTES DA FPU");
        $display("===========================================================\n");

        #50 $finish;
    end

endmodule

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

module slt (
    input  wire [31:0] a, b,
    output wire [31:0] c,
    output wire        busy, done,
    output wire        f_inv_op, f_overflow, f_underflow, f_inexact
);
    // Extração de componentes
    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [30:0] mag_a = a[30:0];
    wire [30:0] mag_b = b[30:0];

    // Exceções
    wire a_is_nan = (&a[30:23]) & (|a[22:0]);
    wire b_is_nan = (&b[30:23]) & (|b[22:0]);
    wire both_zero = ~(|mag_a) & ~(|mag_b); // +0 == -0 no IEEE 754

    // Comparação de magnitude (MagA - MagB) usando seu subtrator
    wire [30:0] mag_diff;
    wire mag_borrow; // cout do subtrator indica se MagA < MagB
    
    // Se MagA - MagB der "carry out" 0 no subtrator de complemento de 2, 
    // significa que MagB > MagA.
    n_bit_subtractor #(31) comp_mag (
        .a(mag_a), .b(mag_b),
        .sum(mag_diff), .cout(mag_borrow)
    );

    // Lógica de Decisão (Less Than)
    // 1. Se sinais diferentes: True se A é negativo e B é positivo.
    // 2. Se ambos positivos: True se MagA < MagB (mag_borrow é 0).
    // 3. Se ambos negativos: True se MagA > MagB (mag_borrow é 1).
    
    wire less_diff_signs = sign_a & ~sign_b;
    wire less_both_pos   = ~sign_a & ~sign_b & ~mag_borrow;
    wire less_both_neg   = sign_a & sign_b & (mag_borrow & |mag_diff); 

    wire is_less = ~both_zero & ~a_is_nan & ~b_is_nan & 
                   (less_diff_signs | less_both_pos | less_both_neg);

    // Saída no padrão IEEE 754 (1.0 para True, 0.0 para False)
    assign c = is_less ? 32'h3F800000 : 32'h00000000;
    
    assign busy = 1'b0;
    assign done = 1'b1;
    assign f_inv_op = a_is_nan | b_is_nan;
    assign {f_overflow, f_underflow, f_inexact} = 3'b000;

endmodule

module div (
    input  wire        clock,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] c,
    output wire        busy,
    output wire        done,
    output wire        f_inv_op,
    output wire        f_div_zero,
    output wire        f_overflow,
    output wire        f_underflow,
    output wire        f_inexact
);

    wire cmd_load_ab, cmd_start_div, cmd_div_step, cmd_round, cmd_except;
    wire exception_detected, div_done;

    div_uc UC (
        .clock(clock), .reset(reset), .start(start),
        .exception_detected(exception_detected), .div_done(div_done),
        .cmd_load_ab(cmd_load_ab), .cmd_start_div(cmd_start_div),
        .cmd_div_step(cmd_div_step), .cmd_round(cmd_round), .cmd_except(cmd_except),
        .busy(busy), .done(done)
    );

    div_fd FD (
        .clock(clock), .reset(reset),
        .a(a), .b(b),
        .cmd_load_ab(cmd_load_ab), .cmd_start_div(cmd_start_div),
        .cmd_div_step(cmd_div_step), .cmd_round(cmd_round), .cmd_except(cmd_except),
        .exception_detected(exception_detected), .div_done(div_done),
        .c(c), .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

endmodule

module div_uc (
    input  wire clock,
    input  wire reset,
    input  wire start,
    input  wire exception_detected,
    input  wire div_done,
    
    output reg  cmd_load_ab,
    output reg  cmd_start_div,
    output reg  cmd_div_step,
    output reg  cmd_round,
    output reg  cmd_except,
    output reg  busy,
    output reg  done
);

    localparam ST_IDLE  = 3'd0,
               ST_EVAL  = 3'd1,
               ST_DIV   = 3'd2,
               ST_ROUND = 3'd3,
               ST_DONE  = 3'd4;

    reg [2:0] state, next_state;

    // Apenas registradores de estado no always (boas práticas)
    always @(posedge clock or posedge reset) begin
        if (reset) state <= ST_IDLE;
        else       state <= next_state;
    end

    always @(*) begin
        // Valores padrão
        next_state    = state;
        cmd_load_ab   = 1'b0;
        cmd_start_div = 1'b0;
        cmd_div_step  = 1'b0;
        cmd_round     = 1'b0;
        cmd_except    = 1'b0;
        busy          = 1'b1;
        done          = 1'b0;

        case (state)
            ST_IDLE: begin
                busy = 1'b0;
                if (start) begin
                    cmd_load_ab = 1'b1;
                    next_state = ST_EVAL;
                end
            end
            ST_EVAL: begin
                if (exception_detected) begin
                    cmd_except = 1'b1;
                    next_state = ST_DONE;
                end else begin
                    cmd_start_div = 1'b1;
                    next_state = ST_DIV;
                end
            end
            ST_DIV: begin
                if (div_done) begin
                    next_state = ST_ROUND;
                end else begin
                    cmd_div_step = 1'b1;
                end
            end
            ST_ROUND: begin
                cmd_round = 1'b1;
                next_state = ST_DONE;
            end
            ST_DONE: begin
                done = 1'b1;
                busy = 1'b0;
                next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end
endmodule

module div_fd (
    input  wire        clock,
    input  wire        reset,
    input  wire [31:0] a,
    input  wire [31:0] b,
    
    // Comandos da Unidade de Controle
    input  wire        cmd_load_ab,
    input  wire        cmd_start_div,
    input  wire        cmd_div_step,
    input  wire        cmd_round,
    input  wire        cmd_except,
    
    // Status para a Unidade de Controle
    output wire        exception_detected,
    output wire        div_done,
    
    // Saídas
    output wire [31:0] c,
    output wire        f_inv_op,
    output wire        f_div_zero,
    output wire        f_overflow,
    output wire        f_underflow,
    output wire        f_inexact
);

    // ==========================================
    // Registradores de Estado
    // ==========================================
    reg [31:0] reg_A, reg_B_in;
    reg [25:0] reg_R;     
    reg [26:0] reg_Q;     
    reg [25:0] reg_B;     
    reg [11:0] reg_Exp;   
    reg        reg_Sign;
    reg [5:0]  reg_Count; 

    reg [31:0] c_reg;
    reg        f_inv_op_reg, f_div_zero_reg, f_overflow_reg, f_underflow_reg, f_inexact_reg;

    assign c           = c_reg;
    assign f_inv_op    = f_inv_op_reg;
    assign f_div_zero  = f_div_zero_reg;
    assign f_overflow  = f_overflow_reg;
    assign f_underflow = f_underflow_reg;
    assign f_inexact   = f_inexact_reg;

    // ==========================================
    // 1. Extração e Detecção de Exceções
    // ==========================================
    wire        sign_a = reg_A[31];
    wire [7:0]  exp_a  = reg_A[30:23];
    wire [22:0] frac_a = reg_A[22:0];

    wire        sign_b = reg_B_in[31];
    wire [7:0]  exp_b  = reg_B_in[30:23];
    wire [22:0] frac_b = reg_B_in[22:0];

    wire hidden_a = (|exp_a);
    wire hidden_b = (|exp_b);
    
    wire [23:0] mant_a = {hidden_a, frac_a};
    wire [23:0] mant_b = {hidden_b, frac_b};

    wire a_is_zero = ~(|exp_a) & ~(|frac_a);
    wire b_is_zero = ~(|exp_b) & ~(|frac_b);
    wire a_is_inf  = (&exp_a)  & ~(|frac_a);
    wire b_is_inf  = (&exp_b)  & ~(|frac_b);
    wire a_is_nan  = (&exp_a)  &  (|frac_a);
    wire b_is_nan  = (&exp_b)  &  (|frac_b);

    assign exception_detected = a_is_zero | b_is_zero | a_is_inf | b_is_inf | a_is_nan | b_is_nan;

    // ==========================================
    // 2. Pré-Normalização com Barrel Shifter
    // ==========================================
    // Substitui o "mant << lz" por instâncias estruturais
    
    function [4:0] count_leading_zeros;
        input [23:0] mantissa;
        integer i;
        begin
            count_leading_zeros = 5'd24;
            for (i = 0; i <= 23; i = i + 1) begin
                if (mantissa[i]) begin
                    count_leading_zeros = 5'd23 - i[4:0];
                end
            end
        end
    endfunction

    wire [4:0] lz_a = count_leading_zeros(mant_a);
    wire [4:0] lz_b = count_leading_zeros(mant_b);

    wire [23:0] norm_mant_a, norm_mant_b;

    // Instância para Normalizar Dividendo (A)
    barrel_shifter #(.WIDTH(24), .SHAMT_WIDTH(5)) bsh_a (
        .in(mant_a),
        .shamt(lz_a),
        .dir(1'b1), // Left Shift
        .out(norm_mant_a),
        .sticky()
    );

    // Instância para Normalizar Divisor (B)
    barrel_shifter #(.WIDTH(24), .SHAMT_WIDTH(5)) bsh_b (
        .in(mant_b),
        .shamt(lz_b),
        .dir(1'b1), // Left Shift
        .out(norm_mant_b),
        .sticky()
    );

    // ==========================================
    // 3. Cálculo do Expoente Inicial
    // ==========================================
    wire [11:0] eff_exp_a = hidden_a ? {4'b0, exp_a} : 12'd1;
    wire [11:0] eff_exp_b = hidden_b ? {4'b0, exp_b} : 12'd1;

    wire [11:0] adj_exp_a, adj_exp_b;
    n_bit_adder #(.N(12)) add_adj_a (.a(eff_exp_a), .b(~{7'b0, lz_a}), .cin(1'b1), .sum(adj_exp_a), .cout());
    n_bit_adder #(.N(12)) add_adj_b (.a(eff_exp_b), .b(~{7'b0, lz_b}), .cin(1'b1), .sum(adj_exp_b), .cout());

    wire [11:0] exp_diff;
    n_bit_adder #(.N(12)) sub_exp (.a(adj_exp_a), .b(~adj_exp_b), .cin(1'b1), .sum(exp_diff), .cout());
    
    wire [11:0] exp_initial;
    n_bit_adder #(.N(12)) add_bias (.a(exp_diff), .b(12'd127), .cin(1'b0), .sum(exp_initial), .cout());

    // ==========================================
    // 4. Aritmética do Loop (Shift-Subtract)
    // ==========================================
    assign div_done = (reg_Count == 6'd0);

    wire [25:0] sub_res;
    wire        sub_cout; 
    
    n_bit_adder #(.N(26)) div_sub (
        .a(reg_R), .b(~reg_B), .cin(1'b1), .sum(sub_res), .cout(sub_cout)
    );

    wire        do_sub = sub_cout; 
    wire [25:0] next_R = do_sub ? {sub_res[24:0], 1'b0} : {reg_R[24:0], 1'b0};
    wire [26:0] next_Q = {reg_Q[25:0], do_sub};

   // ==========================================
    // 5. Normalização Pós-Divisão e Arredondamento
    // ==========================================
    wire        is_norm_1 = reg_Q[26]; 
    wire [23:0] mant_pre_round = is_norm_1 ? reg_Q[26:3] : reg_Q[25:2];
    
    wire guard_bit  = is_norm_1 ? reg_Q[2] : reg_Q[1];
    wire round_bit  = is_norm_1 ? reg_Q[1] : reg_Q[0];
    wire sticky_bit = is_norm_1 ? (reg_Q[0] | (|reg_R)) : (|reg_R);

    wire round_up = guard_bit & (round_bit | sticky_bit | mant_pre_round[0]);

    wire [23:0] mant_rounded;
    wire        round_cout;
    
    n_bit_adder #(.N(24)) adder_round (
        .a(mant_pre_round), .b(24'd0), .cin(round_up), .sum(mant_rounded), .cout(round_cout)
    );

    wire [11:0] exp_adj_norm = is_norm_1 ? 12'd0 : 12'hFFF; 
    wire [11:0] exp_adj_rnd  = round_cout ? 12'd1 : 12'd0;
    
    wire [11:0] exp_final_1, exp_final;
    n_bit_adder #(.N(12)) exp_add_1 (.a(reg_Exp), .b(exp_adj_norm), .cin(1'b0), .sum(exp_final_1), .cout());
    n_bit_adder #(.N(12)) exp_add_2 (.a(exp_final_1), .b(exp_adj_rnd), .cin(1'b0), .sum(exp_final), .cout());

    // ==========================================
    // 6. Bloco Sequencial
    // ==========================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            reg_A <= 0; reg_B_in <= 0; reg_R <= 0; reg_Q <= 0; reg_B <= 0;
            reg_Exp <= 0; reg_Sign <= 0; reg_Count <= 0; c_reg <= 0;
            f_inv_op_reg <= 0; f_div_zero_reg <= 0; f_overflow_reg <= 0; 
            f_underflow_reg <= 0; f_inexact_reg <= 0;
        end else begin
            if (cmd_load_ab) begin
                reg_A <= a;
                reg_B_in <= b;
                f_inv_op_reg <= 0; f_div_zero_reg <= 0; f_overflow_reg <= 0; 
                f_underflow_reg <= 0; f_inexact_reg <= 0;
            end
            
            if (cmd_except) begin
                if (a_is_nan | b_is_nan | (a_is_zero & b_is_zero) | (a_is_inf & b_is_inf)) begin
                    c_reg <= {1'b0, 8'hFF, 23'h7FFFFF}; 
                    f_inv_op_reg <= 1'b1;
                end else if (b_is_zero & ~a_is_zero) begin
                    c_reg <= {sign_a ^ sign_b, 8'hFF, 23'h0}; 
                    f_div_zero_reg <= 1'b1;
                end else if (a_is_inf & ~b_is_inf) begin
                    c_reg <= {sign_a ^ sign_b, 8'hFF, 23'h0}; 
                end else if (a_is_zero & ~b_is_zero) begin
                    c_reg <= {sign_a ^ sign_b, 8'h00, 23'h0}; 
                end else if (b_is_inf & ~a_is_inf) begin
                    c_reg <= {sign_a ^ sign_b, 8'h00, 23'h0}; 
                end
            end
            
            if (cmd_start_div) begin
                reg_Sign  <= sign_a ^ sign_b;
                reg_Exp   <= exp_initial;
                reg_R     <= {2'b0, norm_mant_a};
                reg_B     <= {2'b0, norm_mant_b};
                reg_Q     <= 27'd0;
                reg_Count <= 6'd27; 
            end
            
            if (cmd_div_step) begin
                reg_R     <= next_R;
                reg_Q     <= next_Q;
                reg_Count <= reg_Count - 6'd1;
            end
            
            if (cmd_round) begin
                if ($signed(exp_final) >= 255) begin
                    c_reg <= {reg_Sign, 8'hFF, 23'h0};
                    f_overflow_reg <= 1'b1;
                    f_inexact_reg  <= 1'b1;
                end else if ($signed(exp_final) <= 0) begin
                    c_reg <= {reg_Sign, 8'h00, 23'h0};
                    f_underflow_reg <= 1'b1;
                    f_inexact_reg   <= 1'b1;
                end else begin
                    c_reg <= {reg_Sign, exp_final[7:0], (round_cout ? 23'd0 : mant_rounded[22:0])};
                    f_inexact_reg <= guard_bit | round_bit | sticky_bit;
                end
            end
        end
    end
endmodule

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