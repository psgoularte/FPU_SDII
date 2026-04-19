`timescale 1ns/1ps

module eq_tb;

    reg [31:0] a, b;

    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_overflow, f_underflow, f_inexact;

    // DUT
    eq uut (
        .a(a),
        .b(b),
        .c(c),
        .busy(busy),
        .done(done),
        .f_inv_op(f_inv_op),
        .f_overflow(f_overflow),
        .f_underflow(f_underflow),
        .f_inexact(f_inexact)
    );

    // =========================
    // TASK DE TESTE
    // =========================
    task run_test;
        input [31:0] a_in;
        input [31:0] b_in;
        input [31:0] expected_c;
        input exp_inv;

        reg pass;
        begin
            #1; // pequena propagação

            a = a_in;
            b = b_in;

            #1;

            pass = 1;

            if (c !== expected_c) pass = 0;
            if (f_inv_op !== exp_inv) pass = 0;

            $display("======================================");
            $display("A=%h B=%h", a, b);
            $display("RESULT=%h EXPECTED=%h", c, expected_c);

            if (pass)
                $display("✅ PASS");
            else begin
                $display("❌ FAIL");
                $display("FLAGS: inv=%b/%b", f_inv_op, exp_inv);
            end
        end
    endtask

    // =========================
    // CONSTANTES IEEE
    // =========================
    localparam TRUE  = 32'h3F800000; // 1.0 (true): 0 01111111 00000000000000000000000
    localparam FALSE = 32'h00000000; // 0.0 (false): 0 00000000 00000000000000000000000

    // =========================
    // TESTES
    // =========================
    initial begin

        // =========================
        // IGUAIS NORMAIS
        // =========================
        run_test(32'h3F800000, 32'h3F800000, TRUE, 0); // 1 == 1
        run_test(32'h40000000, 32'h40000000, TRUE, 0); // 2 == 2

        // =========================
        // DIFERENTES
        // =========================
        run_test(32'h3F800000, 32'h40000000, FALSE, 0); // 1 != 2

        // =========================
        // ZERO E -ZERO
        // =========================
        run_test(32'h00000000, 32'h80000000, TRUE, 0); // +0 == -0

        // =========================
        // DOIS ZEROS
        // =========================
        run_test(32'h00000000, 32'h00000000, TRUE, 0);

        // =========================
        // INFINITO
        // =========================
        run_test(32'h7F800000, 32'h7F800000, TRUE, 0); // inf == inf
        run_test(32'hFF800000, 32'hFF800000, TRUE, 0); // -inf == -inf

        // =========================
        // INFINITO DIFERENTE
        // =========================
        run_test(32'h7F800000, 32'hFF800000, FALSE, 0);

        // =========================
        // NaN (SEMPRE FALSE + FLAG)
        // =========================
        run_test(32'h7FC00001, 32'h3F800000, FALSE, 1);
        run_test(32'h3F800000, 32'h7FC00001, FALSE, 1);
        run_test(32'h7FC00001, 32'h7FC00002, FALSE, 1);

        // =========================
        // DESNORMALIZADOS
        // =========================
        run_test(32'h00000001, 32'h00000001, TRUE, 0);
        run_test(32'h00000001, 32'h00000002, FALSE, 0);

        $display("==== FIM DOS TESTES ====");
        $stop;
    end

endmodule