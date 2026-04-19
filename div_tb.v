`timescale 1ns/1ps

module div_tb;

    reg clock;
    reg reset;
    reg start;
    reg [31:0] a, b;

    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    // DUT
    div uut (
        .clock(clock),
        .reset(reset),
        .start(start),
        .a(a),
        .b(b),
        .c(c),
        .busy(busy),
        .done(done),
        .f_inv_op(f_inv_op),
        .f_div_zero(f_div_zero),
        .f_overflow(f_overflow),
        .f_underflow(f_underflow),
        .f_inexact(f_inexact)
    );

    // clock
    always #5 clock = ~clock;

    // =========================
    // TASK DE TESTE COM CHECK
    // =========================
    task run_test;
        input [31:0] a_in;
        input [31:0] b_in;
        input [31:0] expected_c;
        input exp_inv, exp_div0, exp_ovf, exp_unf, exp_inex;

        reg pass;
        begin
            @(posedge clock);
            a <= a_in;
            b <= b_in;
            start <= 1;

            @(posedge clock);
            start <= 0;

            wait(done == 1);
            @(posedge clock);

            pass = 1;

            if (c !== expected_c) pass = 0;
            if (f_inv_op   !== exp_inv) pass = 0;
            if (f_div_zero !== exp_div0) pass = 0;
            if (f_overflow !== exp_ovf) pass = 0;
            if (f_underflow!== exp_unf) pass = 0;
            if (f_inexact  !== exp_inex) pass = 0;

            $display("======================================");
            $display("A=%h B=%h", a, b);
            $display("RESULT=%h EXPECTED=%h", c, expected_c);

            if (pass)
                $display("✅ PASS");
            else begin
                $display("❌ FAIL");
                $display("FLAGS: inv=%b/%b div0=%b/%b ovf=%b/%b unf=%b/%b inex=%b/%b",
                    f_inv_op, exp_inv,
                    f_div_zero, exp_div0,
                    f_overflow, exp_ovf,
                    f_underflow, exp_unf,
                    f_inexact, exp_inex
                );
            end
        end
    endtask

    // =========================
    // TESTES
    // =========================
    initial begin
        clock = 0;
        reset = 1;
        start = 0;
        a = 0;
        b = 0;

        #20;
        reset = 0;

        // =========================
        // NORMAL
        // =========================
        run_test(32'h40D00000, 32'h3FA00000, 32'h40A00000, 0,0,0,0,0); // 6.5 / 1.25 = 5.2
        run_test(32'h3F800000, 32'h40000000, 32'h3F000000, 0,0,0,0,0); // 1/2 = 0.5

        // =========================
        // INEXACT
        // =========================
        run_test(32'h3F800000, 32'h40400000, 32'h3EAAAAAB, 0,0,0,0,1); // 1/3

        // =========================
        // DIV BY ZERO
        // =========================
        run_test(32'h40800000, 32'h00000000, 32'h7F800000, 0,1,0,0,0);

        // =========================
        // 0/0 → NaN
        // =========================
        run_test(32'h00000000, 32'h00000000, 32'h7FC00000, 1,0,0,0,0);

        // =========================
        // INF
        // =========================
        run_test(32'h7F800000, 32'h3F800000, 32'h7F800000, 0,0,0,0,0);
        run_test(32'h3F800000, 32'h7F800000, 32'h00000000, 0,0,0,1,0);

        // =========================
        // INF/INF → NaN
        // =========================
        run_test(32'h7F800000, 32'h7F800000, 32'h7FC00000, 1,0,0,0,0);

        // =========================
        // NaN
        // =========================
        run_test(32'h7FC00001, 32'h3F800000, 32'h7FC00000, 1,0,0,0,0);

        // =========================
        // UNDERFLOW
        // =========================
        run_test(32'h00800000, 32'h7F7FFFFF, 32'h00000000, 0,0,0,1,1);

        // =========================
        // DESNORMAL
        // =========================
        run_test(32'h00000001, 32'h3F800000, 32'h00000001, 0,0,0,1,1);

        // =========================
        // SINAL
        // =========================
        run_test(32'hC0800000, 32'h40000000, 32'hC0000000, 0,0,0,0,0);

        // =========================
        // OVERFLOW
        // =========================
        run_test(32'h7F7FFFFF, 32'h00800000, 32'h7F800000, 0,0,1,0,1);

        $display("==== FIM DOS TESTES ====");
        $stop;
    end

endmodule