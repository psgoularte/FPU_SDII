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

module tb_div_exhaustive;

    reg clock;
    reg reset;
    reg start;
    reg [31:0] a;
    reg [31:0] b;

    wire [31:0] c;
    wire busy;
    wire done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    // Instanciação do Divisor
    div DUT (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .c(c),
        .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    // Geração do Clock (100MHz)
    always #5 clock = ~clock;

    // Task de Teste Automatizada
    task test_division;
        input [31:0] test_a;
        input [31:0] test_b;
        input [8*35:1] test_name; // 35 caracteres para evitar cortes
        begin
            @(posedge clock);
            a = test_a;
            b = test_b;
            start = 1;
            @(posedge clock);
            start = 0;
            
            // Aguarda conclusão (timeout de segurança pode ser adicionado em projetos reais)
            wait(done == 1'b1);
            @(posedge clock);
            
            $display("[%s] A:%h / B:%h => C:%h", test_name, test_a, test_b, c);
            $display("    -> Flags: Inv:%b | DivZ:%b | OVF:%b | UNF:%b | Inx:%b", 
                     f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
        end
    endtask

    initial begin
        // Configuração Inicial
        clock = 0; reset = 1; start = 0; a = 0; b = 0;
        
        #20 reset = 0;
        
        $display("\n===========================================================");
        $display("INICIANDO BATERIA EXAUSTIVA DE TESTES - DIVISAO IEEE 754");
        $display("===========================================================\n");

        $display("--- 1. MATEMATICA BASICA E COMBINACAO DE SINAIS ---");
        // Valores exatos sem dízima
        test_division(32'h41400000, 32'h40400000, " 12.0 /  3.0 =  4.0                ");
        test_division(32'hC1400000, 32'h40400000, "-12.0 /  3.0 = -4.0                ");
        test_division(32'h41400000, 32'hC0400000, " 12.0 / -3.0 = -4.0                ");
        test_division(32'hC1400000, 32'hC0400000, "-12.0 / -3.0 =  4.0                ");
        test_division(32'h3F800000, 32'h40000000, "  1.0 /  2.0 =  0.5                ");
        
        $display("\n--- 2. FRACIONARIOS E ARREDONDAMENTO (INEXATOS) ---");
        // Valores que forçam o uso do Guard, Round e Sticky bits
        test_division(32'h3F800000, 32'h40400000, " 1.0 / 3.0 (Dizima - Arred. Baixo) ");
        test_division(32'h40000000, 32'h40400000, " 2.0 / 3.0 (Dizima - Arred. Cima)  ");
        test_division(32'h40490FDB, 32'h402DF854, " Pi  / e   (Irracionais)           ");

        $display("\n--- 3. FRONTEIRAS NORMAIS (LIMITES DO EXPOENTE) ---");
        test_division(32'h7F7FFFFF, 32'h40000000, " Max Normal / 2.0                  ");
        test_division(32'h00800000, 32'h3F000000, " Min Normal / 0.5                  ");
        test_division(32'h7F7FFFFF, 32'h3F7FFFFF, " Max Normal / ~1.0                 ");

        $display("\n--- 4. OVERFLOW E UNDERFLOW NUMERICO ---");
        test_division(32'h7F7FFFFF, 32'h3E800000, " Max Normal / 0.25      (Overflow) ");
        test_division(32'hC1200000, 32'h00000001, "-10.0 / Min Denorm      (-Overflow)");
        test_division(32'h00800000, 32'h41000000, " Min Normal / 8.0       (Underflow)");
        test_division(32'h00800000, 32'hC1000000, " Min Normal / -8.0      (-Underflow)");

        $display("\n--- 5. TESTES COM SUBNORMAIS (DENORMALIZADOS) ---");
        test_division(32'h00400000, 32'h40000000, " Denorm Medio / 2.0     (Underflow)");
        test_division(32'h00000001, 32'h40000000, " Min Denorm / 2.0       (Flush 2 0)");
        test_division(32'h3F800000, 32'h00400000, " 1.0 / Denorm Medio     (Overflow) ");
        test_division(32'h007FFFFF, 32'h007FFFFF, " Max Denorm / Max Denorm (Exato)   ");
        test_division(32'h00400000, 32'h00000001, " Denorm Medio/Min Denorm (Overflow)");

        $display("\n--- 6. OPERACOES COM ZEROS (+0 E -0) ---");
        // A regra do sinal no Zero e no Infinito é crucial no IEEE 754
        test_division(32'h00000000, 32'h40000000, " +0.0 /  2.0 = +0.0                ");
        test_division(32'h80000000, 32'h40000000, " -0.0 /  2.0 = -0.0                ");
        test_division(32'h40A00000, 32'h00000000, "  5.0 / +0.0 = +Inf                ");
        test_division(32'h40A00000, 32'h80000000, "  5.0 / -0.0 = -Inf                ");
        test_division(32'hC0A00000, 32'h00000000, " -5.0 / +0.0 = -Inf                ");
        test_division(32'hC0A00000, 32'h80000000, " -5.0 / -0.0 = +Inf                ");

        $display("\n--- 7. OPERACOES COM INFINITOS (+Inf E -Inf) ---");
        test_division(32'h7F800000, 32'h40000000, " +Inf /  2.0 = +Inf                ");
        test_division(32'hFF800000, 32'h40000000, " -Inf /  2.0 = -Inf                ");
        test_division(32'h7F800000, 32'hC0000000, " +Inf / -2.0 = -Inf                ");
        test_division(32'h40000000, 32'h7F800000, "  2.0 / +Inf = +0.0                ");
        test_division(32'hC0000000, 32'h7F800000, " -2.0 / +Inf = -0.0                ");
        test_division(32'h40000000, 32'hFF800000, "  2.0 / -Inf = -0.0                ");

        $display("\n--- 8. OPERACOES INVALIDAS (GERACAO DE NaN) ---");
        test_division(32'h00000000, 32'h00000000, " +0.0 / +0.0            (NaN)      ");
        test_division(32'h80000000, 32'h00000000, " -0.0 / +0.0            (NaN)      ");
        test_division(32'h7F800000, 32'h7F800000, " +Inf / +Inf            (NaN)      ");
        test_division(32'hFF800000, 32'h7F800000, " -Inf / +Inf            (NaN)      ");
        
        $display("\n--- 9. PROPAGACAO DE NaN (Entrada = NaN) ---");
        // Se qualquer entrada for NaN, a saída deve ser NaN e levantar Inv_Op
        test_division(32'h7FC00000, 32'h40000000, "  NaN /  2.0            (NaN)      ");
        test_division(32'h40000000, 32'h7FC00000, "  2.0 /  NaN            (NaN)      ");
        test_division(32'h7FC00000, 32'h00000000, "  NaN /  0.0            (NaN)      ");
        test_division(32'h7F800000, 32'h7FC00000, " +Inf /  NaN            (NaN)      ");
        test_division(32'h7FC00000, 32'h7FC00000, "  NaN /  NaN            (NaN)      ");

        $display("\n===========================================================");
        $display("FIM DA SIMULACAO");
        $display("===========================================================\n");

        #50 $finish;
    end

endmodule