module mul (
    input  wire        clock, reset, start,
    input  wire [31:0] a, b,
    output wire [31:0] c,
    output wire        busy, done,
    output wire        f_inv_op, f_overflow, f_underflow, f_inexact
);
    wire cmd_load_ab, cmd_calc, cmd_finish;

    mul_uc UC (
        .clock(clock), .reset(reset), .start(start),
        .cmd_load_ab(cmd_load_ab), .cmd_calc(cmd_calc), .cmd_finish(cmd_finish),
        .busy(busy), .done(done)
    );

    mul_fd FD (
        .clock(clock), .reset(reset),
        .a(a), .b(b),
        .cmd_load_ab(cmd_load_ab), .cmd_calc(cmd_calc), .cmd_finish(cmd_finish),
        .c(c), .f_inv_op(f_inv_op), .f_overflow(f_overflow), 
        .f_underflow(f_underflow), .f_inexact(f_inexact)
    );
endmodule

module mul_uc (
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
                cmd_calc = 1;
                next_state = FINISH;
            end
            FINISH: begin
                cmd_finish = 1;
                done = 1;
                busy = 0;
                next_state = IDLE;
            end
        endcase
    end
endmodule

module mul_fd (
    input  wire        clock, reset,
    input  wire [31:0] a, b,
    input  wire        cmd_load_ab, cmd_calc, cmd_finish,
    
    output reg  [31:0] c,
    output reg         f_inv_op, f_overflow, f_underflow, f_inexact
);

    reg [31:0] reg_A, reg_B;

    // --- 1. Extração e LZC (Leading Zero Counter) ---
    wire sign_a = reg_A[31];
    wire [7:0] exp_a = reg_A[30:23];
    wire [22:0] frac_a = reg_A[22:0];

    wire sign_b = reg_B[31];
    wire [7:0] exp_b = reg_B[30:23];
    wire [22:0] frac_b = reg_B[22:0];

    wire [23:0] m_a_raw = {|exp_a, frac_a};
    wire [23:0] m_b_raw = {|exp_b, frac_b};

    // Função LZC para encontrar o primeiro '1' em subnormais
    function [4:0] lzc24;
        input [23:0] m;
        integer i;
        begin
            lzc24 = 5'd23;
            for (i = 0; i < 24; i = i + 1)
                if (m[i]) lzc24 = 5'd23 - i[4:0];
        end
    endfunction

    wire [4:0] lza = (|exp_a) ? 5'd0 : lzc24(m_a_raw);
    wire [4:0] lzb = (|exp_b) ? 5'd0 : lzc24(m_b_raw);

    // Pré-Normalização via Barrel Shifter (Alinha o '1' no bit 23)
    wire [23:0] m_a_norm, m_b_norm;
    barrel_shifter #(.WIDTH(24), .SHAMT_WIDTH(5)) bsh_a (.in(m_a_raw), .shamt(lza), .dir(1'b1), .out(m_a_norm), .sticky());
    barrel_shifter #(.WIDTH(24), .SHAMT_WIDTH(5)) bsh_b (.in(m_b_raw), .shamt(lzb), .dir(1'b1), .out(m_b_norm), .sticky());

    // --- 2. Multiplicador de Mantissa Estrutural ---
    wire [47:0] partials [0:23];
    wire [47:0] sum_tree [0:23];
    genvar i;
    generate
        for (i = 0; i < 24; i = i + 1) begin : gen_partials
            assign partials[i] = m_b_norm[i] ? ({24'd0, m_a_norm} << i) : 48'd0;
        end
        assign sum_tree[0] = partials[0];
        for (i = 1; i < 24; i = i + 1) begin : gen_sum_tree
            n_bit_adder #(48) add_p (.a(sum_tree[i-1]), .b(partials[i]), .cin(1'b0), .sum(sum_tree[i]), .cout());
        end
    endgenerate
    wire [47:0] raw_product = sum_tree[23];

    // --- 3. Cálculo do Expoente com Ajuste de LZC ---
    wire res_sign = sign_a ^ sign_b;
    wire [9:0] exp_a_adj = {2'b0, (|exp_a ? exp_a : 8'd1)} - {5'd0, lza};
    wire [9:0] exp_b_adj = {2'b0, (|exp_b ? exp_b : 8'd1)} - {5'd0, lzb};
    
    wire [9:0] exp_sum, exp_with_bias;
    n_bit_adder #(10) add_e (.a(exp_a_adj), .b(exp_b_adj), .cin(1'b0), .sum(exp_sum), .cout());
    n_bit_subtractor #(10) sub_b (.a(exp_sum), .b(10'd127), .sum(exp_with_bias), .cout());

    // --- 4. Normalização e Tratamento de Underflow (Denormalização de Saída) ---
    wire norm_shift = raw_product[47];
    wire [9:0] exp_norm;
    n_bit_adder #(10) add_en (.a(exp_with_bias), .b({9'd0, norm_shift}), .cin(1'b0), .sum(exp_norm), .cout());

    // Se exp_norm <= 0, o resultado é subnormal. Precisamos shift right para encaixar no expoente 0.
    wire is_sub_out = $signed(exp_norm) <= 0;
    wire [9:0] sub_shift_amt = 10'd1 - exp_norm; 
    
    // Limitamos o shift para evitar lixo (max 25)
    wire [4:0] final_shamt = is_sub_out ? (sub_shift_amt > 25 ? 5'd26 : sub_shift_amt[4:0]) : {4'd0, norm_shift};
    
    wire [47:0] product_final;
    wire sticky_sh;
    barrel_shifter #(.WIDTH(48), .SHAMT_WIDTH(6)) shifter_final (
        .in(raw_product), .shamt({1'b0, final_shamt}), .dir(1'b0), // Right
        .out(product_final), .sticky(sticky_sh)
    );

    // --- 5. Arredondamento ---
    wire [22:0] f_pre = product_final[45:23];
    wire guard  = product_final[22];
    wire round  = product_final[21];
    wire sticky = |product_final[20:0] | sticky_sh;
    
    wire round_up = guard & (round | sticky | f_pre[0]);
    wire [22:0] f_rounded;
    wire rnd_carry;
    n_bit_adder #(23) addr_r (.a(f_pre), .b(23'd0), .cin(round_up), .sum(f_rounded), .cout(rnd_carry));

    // Expoente final (0 se for subnormal e não arredondou para normal)
    wire [7:0] exp_out = (is_sub_out && !rnd_carry) ? 8'd0 : exp_norm[7:0] + {7'd0, rnd_carry};

    // --- 6. Casos Especiais ---
    wire a_is_nan = (&exp_a) & (|frac_a); wire b_is_nan = (&exp_b) & (|frac_b);
    wire a_is_inf = (&exp_a) & ~(|frac_a); wire b_is_inf = (&exp_b) & ~(|frac_b);
    wire a_is_zero = ~(|exp_a) & ~(|frac_a); wire b_is_zero = ~(|exp_b) & ~(|frac_b);

    always @(posedge clock or posedge reset) begin
        if (reset) begin c <= 0; {f_inv_op, f_overflow, f_underflow, f_inexact} <= 4'b0; end
        else begin
            if (cmd_load_ab) begin reg_A <= a; reg_B <= b; end
            if (cmd_finish) begin
                // Reset inicial das flags para garantir limpeza
                f_inv_op <= 0; f_overflow <= 0; f_underflow <= 0; f_inexact <= 0;

                if (a_is_nan | b_is_nan | (a_is_inf & b_is_zero) | (a_is_zero & b_is_inf)) begin
                    c <= 32'h7FC00000; f_inv_op <= 1;
                end else if (a_is_inf | b_is_inf) begin
                    c <= {res_sign, 8'hFF, 23'd0};
                    // Infinitos puros não disparam overflow se já eram infinitos
                end else if (a_is_zero | b_is_zero || (is_sub_out && final_shamt > 25)) begin
                    c <= {res_sign, 8'h00, 23'd0};
                    if (!(a_is_zero | b_is_zero)) f_underflow <= 1; // Só sinaliza se "encolheu" até zero
                end else if ($signed(exp_norm) >= 255) begin
                    c <= {res_sign, 8'hFF, 23'd0}; 
                    f_overflow <= 1; f_inexact <= 1;
                end else begin
                    // Cálculo normal ou subnormal válido
                    c <= {res_sign, exp_out, f_rounded};
                    f_inexact <= guard | round | sticky;
                    f_underflow <= is_sub_out; 
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

`timescale 1ns/1ps

module tb_mul;

    reg clock, reset, start;
    reg [31:0] a, b;
    
    wire [31:0] c;
    wire busy, done;
    wire f_inv_op, f_overflow, f_underflow, f_inexact;

    // Instanciação do Multiplicador Top-Level
    mul DUT (
        .clock(clock), .reset(reset), .start(start),
        .a(a), .b(b), .c(c),
        .busy(busy), .done(done),
        .f_inv_op(f_inv_op), .f_overflow(f_overflow), 
        .f_underflow(f_underflow), .f_inexact(f_inexact)
    );

    // Geração de Clock (100MHz)
    always #5 clock = ~clock;

    // Task para automatizar os testes
    task run_mul_test;
        input [31:0] val_a, val_b;
        input [8*30:1] name;
        begin
            @(posedge clock);
            a = val_a; b = val_b; start = 1;
            @(posedge clock); start = 0;
            
            wait(done);
            @(posedge clock);
            #1; // Delay para estabilizar saída
            $display("[%s] %h * %h => %h | Flags: O:%b U:%b I:%b Inv:%b", 
                     name, val_a, val_b, c, f_overflow, f_underflow, f_inexact, f_inv_op);
        end
    endtask

    initial begin
        // Inicialização
        clock = 0; reset = 1; start = 0; a = 0; b = 0;
        #20 reset = 0;

        $display("\n===========================================================");
        $display("   BATERIA DE TESTES ROBUSTA - MULTIPLICACAO IEEE 754");
        $display("===========================================================\n");

        $display("--- 1. PRODUTOS BASICOS E SINAIS ---");
        run_mul_test(32'h40000000, 32'h40000000, " 2.0 * 2.0 =  4.0       ");
        run_mul_test(32'hC0000000, 32'h40000000, "-2.0 * 2.0 = -4.0       ");
        run_mul_test(32'hC0000000, 32'hC0800000, "-2.0 * -4.0 =  8.0       ");
        run_mul_test(32'h3F800000, 32'h42280000, " 1.0 * 42.0 = 42.0       ");

        $display("\n--- 2. PRECISAO E ARREDONDAMENTO (MANTISSA 48-BIT) ---");
        // Teste de arredondamento Tie-to-Even
        // 1.5 * 1.5 = 2.25 (0x40100000)
        run_mul_test(32'h3FC00000, 32'h3FC00000, " 1.5 * 1.5 = 2.25       ");
        // Valores que forçam o uso do Sticky Bit no produto de 48 bits
        run_mul_test(32'h3F800001, 32'h3F800001, " (1+eps) * (1+eps) (Inx) ");

        $display("\n--- 3. CASOS DE EXPOENTE EXTREMO (OVER/UNDERFLOW) ---");
        // Max * 2.0 = Overflow
        run_mul_test(32'h7F7FFFFF, 32'h40000000, " Max * 2.0 = Inf (OVF)   ");
        // Min * 0.5 = Underflow
        run_mul_test(32'h00800000, 32'h3F000000, " Min * 0.5 = 0.0 (UNF)   ");
        // Valores muito grandes
        run_mul_test(32'h70000000, 32'h70000000, " Huge * Huge = Inf (OVF) ");

        $display("\n--- 4. REGRAS DO ZERO E INFINITO ---");
        run_test_mul(32'h00000000, 32'h42280000, " 0.0 * 42.0 = 0.0        ");
        run_test_mul(32'h7F800000, 32'h40000000, " Inf * 2.0  = Inf        ");
        run_test_mul(32'h7F800000, 32'h00000000, " Inf * 0.0  = NaN (Inv)  "); // Operação Inválida!

        $display("\n--- 5. NOT A NUMBER (NaN) ---");
        run_test_mul(32'h7FC00000, 32'h40000000, " NaN * 2.0  = NaN        ");
        run_test_mul(32'h7FC00000, 32'h7F800000, " NaN * Inf  = NaN        ");

        $display("\n--- 6. TESTES COM SUBNORMAIS (DENORMALIZADOS) ---");
        // Min Denorm (2^-149) * 2.0 = 2^-148 (Ainda subnormal)
        // 0x00000001 * 0x40000000 = 0x00000002
        run_mul_test(32'h00000001, 32'h40000000, " MinDenorm * 2.0        ");

        // 0.5 * 2^-126 (Min Normal) = 2^-127 (Subnormal)
        // 0x3F000000 * 0x00800000 = 0x00400000
        run_mul_test(32'h3F000000, 32'h00800000, " 0.5 * MinNormal = Sub  ");

        // Subnormal * Subnormal (Underflow extremo -> 0)
        run_mul_test(32'h00000001, 32'h00000001, " Denorm * Denorm = 0    ");

        // Max Denorm * 2.0 = Min Normal (Transição!)
        // 0x007FFFFF * 0x40000000 = 0x00FFFFFE -> (Normalizado) 0x00800000 aprox
        run_mul_test(32'h007FFFFF, 32'h40000000, " MaxDenorm * 2.0 = Norm ");

        $display("\n===========================================================");
        $display("                FIM DOS TESTES DE MULTIPLICACAO");
        $display("===========================================================\n");

        #50 $finish;
    end

    // Alias para evitar erro de digitação caso chame run_test_mul ou run_mul_test
    task run_test_mul;
        input [31:0] val_a, val_b;
        input [8*30:1] name;
        begin
            run_mul_test(val_a, val_b, name);
        end
    endtask

endmodule