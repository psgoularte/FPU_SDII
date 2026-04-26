`timescale 1ns/1ps

module tb_fpu;

    reg clock, reset, start;
    reg [31:0] a, b;
    reg [2:0] op;

    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact;

    integer total, passed;

    fpu uut (
        .clock(clock),
        .reset(reset),
        .start(start),
        .a(a),
        .b(b),
        .op(op),
        .c(c),
        .busy(busy),
        .done(done),
        .f_inv_op(f_inv_op),
        .f_div_zero(f_div_zero),
        .f_overflow(f_overflow),
        .f_underflow(f_underflow),
        .f_inexact(f_inexact)
    );

    always #5 clock = ~clock;

    task run_test;
        input [31:0] ta;
        input [31:0] tb;
        input [2:0]  top;
        input [31:0] expected_c;
        input expected_inv;
        input expected_divzero;
        input expected_overflow;
        input expected_underflow;
        input expected_inexact;
        begin
            total = total + 1;

            a = ta;
            b = tb;
            op = top;

            start = 1'b1;
            #10;
            start = 1'b0;

            wait(done);
            #1;

            if (
                c == expected_c &&
                f_inv_op == expected_inv &&
                f_div_zero == expected_divzero &&
                f_overflow == expected_overflow &&
                f_underflow == expected_underflow &&
                f_inexact == expected_inexact
            ) begin
                passed = passed + 1;
                $display("PASS: op=%b a=%h b=%h c=%h flags=%b%b%b%b%b",
                    top, ta, tb, c,
                    f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
            end else begin
                $display("FAIL: op=%b a=%h b=%h", top, ta, tb);
                $display("      got:      c=%h flags=%b%b%b%b%b",
                    c, f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact);
                $display("      expected: c=%h flags=%b%b%b%b%b",
                    expected_c, expected_inv, expected_divzero,
                    expected_overflow, expected_underflow, expected_inexact);
            end

            #10;
        end
    endtask

    initial begin
        total = 0;
        passed = 0;

        clock = 0;
        reset = 1;
        start = 0;
        a = 0;
        b = 0;
        op = 0;

        #20;
        reset = 0;

        // ============================
        // ADD básicos
        // ============================
        run_test(32'h3f800000, 32'h40000000, 3'b000, 32'h40400000, 0,0,0,0,0); // 1 + 2 = 3
        run_test(32'h40b00000, 32'h40100000, 3'b000, 32'h40f80000, 0,0,0,0,0); // 5.5 + 2.25 = 7.75
        run_test(32'h40a00000, 32'hc0800000, 3'b000, 32'h3f800000, 0,0,0,0,0); // 5 + (-4) = 1

        // ============================
        // SUB básicos
        // ============================
        run_test(32'h40e00000, 32'h40400000, 3'b001, 32'h40800000, 0,0,0,0,0); // 7 - 3 = 4
        run_test(32'h40400000, 32'h40e00000, 3'b001, 32'hc0800000, 0,0,0,0,0); // 3 - 7 = -4
        run_test(32'h40a00000, 32'h40a00000, 3'b001, 32'h00000000, 0,0,0,0,0); // 5 - 5 = 0

        // ============================
        // Zeros com sinal
        // ============================
        run_test(32'h00000000, 32'h80000000, 3'b000, 32'h00000000, 0,0,0,0,0); // +0 + -0 = +0
        run_test(32'h80000000, 32'h80000000, 3'b000, 32'h80000000, 0,0,0,0,0); // -0 + -0 = -0
        run_test(32'h00000000, 32'h80000000, 3'b001, 32'h00000000, 0,0,0,0,0); // +0 - -0 = +0

        // ============================
        // Infinitos
        // ============================
        run_test(32'h7f800000, 32'h7f800000, 3'b000, 32'h7f800000, 0,0,0,0,0); // +inf + +inf
        run_test(32'hff800000, 32'hff800000, 3'b000, 32'hff800000, 0,0,0,0,0); // -inf + -inf
        run_test(32'h7f800000, 32'hff800000, 3'b000, 32'h7fc00000, 1,0,0,0,0); // +inf + -inf invalid
        run_test(32'h7f800000, 32'h7f800000, 3'b001, 32'h7fc00000, 1,0,0,0,0); // +inf - +inf invalid
        run_test(32'h7f800000, 32'hff800000, 3'b001, 32'h7f800000, 0,0,0,0,0); // +inf - -inf = +inf

        // ============================
        // NaN
        // ============================
        run_test(32'h7fc00000, 32'h3f800000, 3'b000, 32'h7fc00000, 0,0,0,0,0); // qNaN + 1
        run_test(32'h7f800001, 32'h3f800000, 3'b000, 32'h7fc00000, 1,0,0,0,0); // sNaN + 1

        // ============================
        // Overflow
        // ============================
        run_test(32'h7f7fffff, 32'h7f7fffff, 3'b000, 32'h7f800000, 0,0,1,0,1); // max + max = inf

        // ============================
        // Subnormais
        // ============================
        run_test(32'h00800000, 32'h00800000, 3'b000, 32'h01000000, 0,0,0,0,0); // menor normal + menor normal
        run_test(32'h00000001, 32'h00000001, 3'b000, 32'h00000002, 0,0,0,0,0); // menor subnormal + menor subnormal
        run_test(32'h00000002, 32'h00000001, 3'b001, 32'h00000001, 0,0,0,0,0); // subnormal - subnormal

        // ============================
        // Arredondamento / inexact
        // ============================
        run_test(32'h3f800000, 32'h00000001, 3'b000, 32'h3f800000, 0,0,0,0,1); // 1 + menor subnormal = 1, inexact
        run_test(32'h3f800000, 32'h33800000, 3'b000, 32'h3f800000, 0,0,0,0,1); // empate para par
        run_test(32'h3f800000, 32'h34000000, 3'b000, 32'h3f800001, 0,0,0,0,0); // próximo float após 1
        run_test(32'h3f800001, 32'h3f800000, 3'b001, 32'h34000000, 0,0,0,0,0); // diferença mínima perto de 1

        // ============================
        // Placeholders: devem retornar zero
        // ============================
        run_test(32'h3f800000, 32'h40000000, 3'b010, 32'h00000000, 0,0,0,0,0); // MUL placeholder
        run_test(32'h3f800000, 32'h40000000, 3'b011, 32'h00000000, 0,0,0,0,0); // DIV placeholder
        run_test(32'h3f800000, 32'h3f800000, 3'b100, 32'h00000000, 0,0,0,0,0); // EQ placeholder
        run_test(32'h3f800000, 32'h40000000, 3'b101, 32'h00000000, 0,0,0,0,0); // SLT placeholder

        $display("----------------------------------------");
        $display("RESULTADO FINAL: %0d / %0d testes passaram", passed, total);
        $display("----------------------------------------");

        $finish;
    end

endmodule