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

    // Instância: Adição e Subtração
    add_sub mod_add_sub (
        .clock(clock), .reset(reset), .start(start_addsub),
        .a(a), .b(b), .op(op[0]),
        .c(c_addsub), .busy(busy_addsub), .done(done_addsub),
        .f_inv_op(inv_addsub), .f_div_zero(), .f_overflow(overflow_addsub), 
        .f_underflow(underflow_addsub), .f_inexact(inexact_addsub)
    );

    // Instância: Multiplicação (AGORA CONECTADO)
    mul mod_mul (
        .clock(clock), .reset(reset), .start(start_mul),
        .a(a), .b(b),
        .c(c_mul), .busy(busy_mul), .done(done_mul),
        .f_inv_op(inv_mul), .f_overflow(overflow_mul), 
        .f_underflow(underflow_mul), .f_inexact(inexact_mul)
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

    // Instanciação da FPU
    fpu DUT (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .op(op),
        .c(c), .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_div_zero(f_div_zero),
        .f_overflow(f_overflow), .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    always #5 clock = ~clock;

    // Task Robusta de Teste
    task run_fpu;
        input [31:0] val_a, val_b;
        input [2:0]  val_op;
        input [8*35:1] label;
        begin
            @(posedge clock);
            a = val_a; b = val_b; op = val_op; start = 1;
            @(posedge clock); start = 0;
            
            // Espera o módulo terminar (essencial para MUL e DIV)
            wait(done);
            @(posedge clock);
            #1;
            $display("[%s] A:%h B:%h | Res:%h | Flags(IZVUI):%b%b%b%b%b", 
                     label, val_a, val_b, c, f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
        end
    endtask

    initial begin
        clock = 0; reset = 1; start = 0; a = 0; b = 0; op = 0;
        #20 reset = 0;

        $display("==========================================================================");
        $display("          BATERIA DE TESTES DE ESTRESSE - FPU ESTRUTURAL 32-BIT");
        $display("==========================================================================\n");

        // --- 1. SOMA/SUB: ARREDONDAMENTO E CANCELAMENTO ---
        $display("--- [ADD/SUB] Arredondamento e Cancelamento ---");
        run_fpu(32'h3F800000, 32'h33800000, 3'b000, "1.0 + 2^-24 (Tie-to-Even)"); 
        run_fpu(32'h3F800001, 32'h33800000, 3'b000, "1.000...01 + 2^-24 (Up)");
        run_fpu(32'h3F800000, 32'h3F7FFFFF, 3'b001, "1.0 - (1.0 - eps) (Normalizacao)");
        run_fpu(32'h4B7FFFFF, 32'h3F800000, 3'b000, "Max Mantissa + 1 (Carry Out)");

        // --- 2. MUL: CONTINUIDADE E SUBNORMAIS ---
        $display("\n--- [MUL] Precisao e Subnormais ---");
        run_fpu(32'h3FC00000, 32'h3FC00000, 3'b010, "1.5 * 1.5 (Exato)");
        run_fpu(32'h00000001, 32'h3F800000, 3'b010, "MinDenorm * 1.0 (Identidade)");
        run_fpu(32'h00400000, 32'h3F000000, 3'b010, "Denorm * 0.5 (Underflow p/ Denorm)");
        run_fpu(32'h7F7FFFFF, 32'h7F7FFFFF, 3'b010, "Max * Max (Overflow p/ Inf)");

        // --- 3. DIV: CASOS CRÍTICOS ---
        $display("\n--- [DIV] Casos de Borda ---");
        run_fpu(32'h3F800000, 32'h40400000, 3'b011, "1.0 / 3.0 (Dizima/Inexato)");
        run_fpu(32'h00800000, 32'h40000000, 3'b011, "MinNormal / 2.0 (Norm -> Denorm)");
        run_fpu(32'h40000000, 32'h00000001, 3'b011, "2.0 / MinDenorm (Overflow)");
        run_fpu(32'h7F800000, 32'h7F800000, 3'b011, "Inf / Inf (Invalid Op)");

        // --- 4. COMPARAÇÃO (EQ/SLT) ---
        $display("\n--- [CMP] Logica de Decisao ---");
        run_fpu(32'h80000000, 32'h00000000, 3'b100, "-0.0 == +0.0 (True)");
        run_fpu(32'hBF800000, 32'h3F800000, 3'b101, "-1.0 < 1.0 (True)");
        run_fpu(32'hC0000000, 32'hC0A00000, 3'b101, "-2.0 < -5.0 (False)");
        run_fpu(32'h7FC00000, 32'h7FC00000, 3'b101, "NaN < NaN (False)");

        // --- 5. ZEROS E INFINITOS ---
        $display("\n--- [SPECIAL] Zeros e Infinitos ---");
        run_fpu(32'h7F800000, 32'hC0000000, 3'b011, "Inf / -2.0 = -Inf");
        run_fpu(32'h00000000, 32'h80000000, 3'b010, "+0.0 * -0.0 = -0.0");
        run_fpu(32'h7F800000, 32'h7F800000, 3'b000, "Inf + Inf = Inf");
        run_fpu(32'h7F800000, 32'h7F800000, 3'b001, "Inf - Inf = NaN");

        // --- 6. UNDERFLOW EXTREMO (FLUSH TO ZERO) ---
        $display("\n--- [UNDERFLOW] Limites Inferiores ---");
        run_fpu(32'h00000001, 32'h3E800000, 3'b010, "MinDenorm * 0.25 (To Zero)");
        run_fpu(32'h00000001, 32'h7F000000, 3'b011, "MinDenorm / Huge (To Zero)");

        // --- 7. PROPAGAÇÃO DE NaN ---
        $display("\n--- [NaN] Propagacao ---");
        run_fpu(32'h7FC00000, 32'h40000000, 3'b000, "NaN + 2.0 = NaN");
        run_fpu(32'h40000000, 32'h7FC00000, 3'b010, "2.0 * NaN = NaN");

        // --- 8. SUBTRACTOR TEST (SIGN INVERSION) ---
        $display("\n--- [SUB] Inversao de Sinal ---");
        run_fpu(32'h00000000, 32'h40000000, 3'b001, "0.0 - 2.0 = -2.0");
        run_fpu(32'hC0000000, 32'hC0000000, 3'b001, "-2.0 - (-2.0) = +0.0");

        $display("\n--- [DIV] Testes de Divisao por Zero e Sinais ---");
        // +1.0 / +0.0 = +Inf (Flag DivZ)
        run_fpu(32'h3F800000, 32'h00000000, 3'b011, " 1.0 / +0.0 = +Inf (Z)");
        
        // -1.0 / +0.0 = -Inf (Flag DivZ)
        run_fpu(32'hBF800000, 32'h00000000, 3'b011, "-1.0 / +0.0 = -Inf (Z)");
        
        // +1.0 / -0.0 = -Inf (Flag DivZ)
        run_fpu(32'h3F800000, 32'h80000000, 3'b011, " 1.0 / -0.0 = -Inf (Z)");

        $display("\n--- [NaN] Tipos e Sinais (Bit 22) ---");
        // Operacao Invalida deve gerar um Quiet NaN (7FC00000)
        run_fpu(32'h7F800000, 32'h7F800000, 3'b001, "Inf - Inf = QNaN (7FC)");
        
        // Propagacao de SNaN (Bit 22 em 0) -> Deve resultar em QNaN e Flag Inv
        // A: 7F800001 (SNaN)
        run_fpu(32'h7F800001, 32'h40000000, 3'b000, "SNaN + 2.0 = QNaN (Inv)");

        $display("\n==========================================================================");
        $display("                   SIMULACAO FINALIZADA COM SUCESSO");
        $display("==========================================================================");

        #100 $finish;
    end

endmodule