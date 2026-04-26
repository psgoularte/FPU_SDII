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