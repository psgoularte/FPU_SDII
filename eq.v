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

`timescale 1ns/1ps

module tb_eq;

    reg [31:0] a;
    reg [31:0] b;

    wire [31:0] c;
    wire busy, done, f_inv_op, f_overflow, f_underflow, f_inexact;

    // Instanciação do seu módulo
    eq DUT (
        .a(a), .b(b), .c(c),
        .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_overflow(f_overflow), 
        .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    // Task para automatizar as verificações
    task test_eq;
        input [31:0] val_a;
        input [31:0] val_b;
        input [8*25:1] name;
        begin
            a = val_a;
            b = val_b;
            #10; // Aguarda o tempo de propagação combinacional
            
            $display("[%s] A:%h == B:%h => C:%h | Inv_Op:%b", 
                     name, val_a, val_b, c, f_inv_op);
        end
    endtask

    initial begin
        $display("=======================================================");
        $display("   TESTE DE IGUALDADE (==) IEEE 754 SINGLE PRECISION");
        $display("=======================================================\n");

        $display("--- 1. NUMEROS NORMAIS ---");
        test_eq(32'h40000000, 32'h40000000, "2.0 == 2.0      (True)   ");
        test_eq(32'hC0000000, 32'hC0000000, "-2.0 == -2.0    (True)   ");
        test_eq(32'h40000000, 32'h40400000, "2.0 == 3.0      (False)  ");
        test_eq(32'h40000000, 32'hC0000000, "2.0 == -2.0     (False)  ");

        $display("\n--- 2. REGRA DO ZERO (Crucial) ---");
        test_eq(32'h00000000, 32'h00000000, "+0.0 == +0.0    (True)   ");
        test_eq(32'h80000000, 32'h80000000, "-0.0 == -0.0    (True)   ");
        test_eq(32'h00000000, 32'h80000000, "+0.0 == -0.0    (True)   ");
        test_eq(32'h80000000, 32'h00000000, "-0.0 == +0.0    (True)   ");

        $display("\n--- 3. REGRA DO INFINITO ---");
        test_eq(32'h7F800000, 32'h7F800000, "+Inf == +Inf    (True)   ");
        test_eq(32'hFF800000, 32'hFF800000, "-Inf == -Inf    (True)   ");
        test_eq(32'h7F800000, 32'hFF800000, "+Inf == -Inf    (False)  ");

        $display("\n--- 4. REGRA DO NaN (Sempre False) ---");
        test_eq(32'h7FC00000, 32'h7FC00000, "NaN == NaN      (False)  ");
        test_eq(32'h7FC00000, 32'h40000000, "NaN == 2.0      (False)  ");
        test_eq(32'h7F800000, 32'h7FC00000, "+Inf == NaN     (False)  ");
        
        $display("\n--- 5. NUMEROS SUBNORMAIS ---");
        test_eq(32'h00000001, 32'h00000001, "MinDen == MinDen (True)  ");
        test_eq(32'h00000001, 32'h00000002, "MinDen == Den+1  (False) ");

        $display("\n=======================================================");
        $display("                     FIM DO TESTE");
        $display("=======================================================\n");

        #50 $finish;
    end

endmodule