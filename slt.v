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

`timescale 1ns/1ps

module tb_slt;

    reg  [31:0] a, b;
    wire [31:0] c;
    wire busy, done, f_inv_op;

    // Instanciação do módulo SLT estrutural
    slt DUT (
        .a(a), .b(b), .c(c),
        .busy(busy), .done(done),
        .f_inv_op(f_inv_op),
        .f_overflow(), .f_underflow(), .f_inexact()
    );

    // Task corrigida: nome consistente 'run_slt_test'
    task run_slt_test;
        input [31:0] val_a, val_b;
        input [8*25:1] name;
        begin
            a = val_a;
            b = val_b;
            #10; // Tempo para a lógica dos subtratores estabilizar
            
            $display("[%s] A:%h < B:%h => Result:%h | Inv:%b", 
                     name, val_a, val_b, c, f_inv_op);
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("   TESTE ESTRUTURAL SLT (SET ON LESS THAN) IEEE 754");
        $display("==========================================================\n");

        $display("--- 1. NUMEROS POSITIVOS (MAGNITUDE DIRETA) ---");
        run_slt_test(32'h40000000, 32'h40800000, " 2.0 <  4.0 (True)      ");
        run_slt_test(32'h40800000, 32'h40000000, " 4.0 <  2.0 (False)     ");
        run_slt_test(32'h3F800000, 32'h3F800000, " 1.0 <  1.0 (False)     ");

        $display("\n--- 2. SINAIS OPOSTOS ---");
        run_slt_test(32'hC0000000, 32'h40000000, "-2.0 <  2.0 (True)      ");
        run_slt_test(32'h40000000, 32'hC0000000, " 2.0 < -2.0 (False)     ");

        $display("\n--- 3. NUMEROS NEGATIVOS (MAGNITUDE INVERSA) ---");
        // Em negativos, quem tem maior magnitude (valor absoluto) é o menor número
        run_slt_test(32'hC0A00000, 32'hC0000000, "-5.0 < -2.0 (True)      ");
        run_slt_test(32'hC0000000, 32'hC0A00000, "-2.0 < -5.0 (False)     ");

        $display("\n--- 4. REGRA DO ZERO (+0 vs -0) ---");
        run_slt_test(32'h80000000, 32'h00000000, "-0.0 < +0.0 (False)     ");
        run_slt_test(32'h00000000, 32'h80000000, "+0.0 < -0.0 (False)     ");

        $display("\n--- 5. INFINITOS E FRONTEIRAS ---");
        run_slt_test(32'hFF800000, 32'h7F800000, "-Inf < +Inf (True)      ");
        run_slt_test(32'hFF800000, 32'hC1200000, "-Inf < -10.0 (True)     ");
        run_slt_test(32'h7F800000, 32'h7F7FFFFF, "+Inf < MaxNorm (False)  ");

        $display("\n--- 6. CASOS DE NaN (Sempre False) ---");
        run_slt_test(32'h7FC00000, 32'h40000000, " NaN < 2.0  (False)     ");
        run_slt_test(32'h40000000, 32'h7FC00000, " 2.0 < NaN  (False)     ");

        $display("\n==========================================================");
        $display("                   FIM DOS TESTES SLT");
        $display("==========================================================\n");

        #50 $finish;
    end

endmodule