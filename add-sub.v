module fpu (
    input  wire        clock, reset, start,
    input  wire [31:0] a, b,
    input  wire [2:0]  op,
    output reg  [31:0] c,
    output reg         busy, done,
    output reg         f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

    // Estados da FSM
    localparam ST_IDLE   = 2'd0;
    localparam ST_CALC   = 2'd1;
    localparam ST_FINISH = 2'd2;

    reg [1:0]  state;
    reg [31:0] a_r, b_r;
    reg [2:0]  op_r;

    // ADD / SUB
    // saídas combinacionais 
    reg [31:0] addsub_result;
    reg        addsub_inv_op, addsub_overflow, addsub_underflow, addsub_inexact;

    reg        sign_a, sign_b, sign_b_eff, sign_res, sign_big, sign_small;
    reg        same_sign;
    reg [7:0]  exp_a_raw, exp_b_raw, exp_a_eff, exp_b_eff;
    reg [7:0]  exp_big, exp_small, exp_res;
    reg [7:0]  exp_before_round;
    reg [22:0] frac_a, frac_b;

    reg is_zero_a, is_zero_b;
    reg is_inf_a,  is_inf_b;
    reg is_nan_a,  is_nan_b;
    reg is_snan_a, is_snan_b;

    // Mantissas: [26:0] = {hidden_bit, frac[22:0], guard, round, sticky}
    reg [26:0] mant_a, mant_b, mant_big;

    // mantissa pequena e sua versão alinhada
    reg [26:0] mant_small;
    reg        sticky_align; 

    // extensão de 28 bits para a soma/subtração sem overflow
    reg [27:0] mant_big_ext, mant_small_ext;

    // resultado após soma/sub e normalização
    reg [26:0] mant_norm_pre, mant_norm;

    // arredondamento
    reg [24:0] rounded_main_pre, rounded_main;
    reg [7:0]  out_exp;
    reg [22:0] out_frac;

    // contador de zeros à esquerda
    reg [4:0]  lz_count, lz_used;
    reg        lz_found;

    // bit de incremento de arredondamento
    reg        round_inc;

    // flag interna: resultado já determinado (casos especiais)
    reg        result_ready;

    integer i;

    // instâncias de módulos auxiliares 

    // diferença de expoentes para alinhamento
    wire [7:0] exp_diff;
    wire       exp_diff_cout;
    n_bit_subtractor #(8) sub_exp_align (
        .a(exp_big), .b(exp_small),
        .s(exp_diff), .cout(exp_diff_cout)
    );

    // deslocamento à direita da mantissa pequena
    wire [26:0] mant_small_shifted;
    wire        align_sticky;
    right_shift_sticky_27 sh_align (
        .in(mant_small), .shamt(exp_diff),
        .out(mant_small_shifted), .sticky(align_sticky)
    );

    // soma de mantissas (28 bits para capturar carry)
    wire [27:0] mant_add_out;
    n_bit_adder #(28) add_mant (
        .a(mant_big_ext), .b(mant_small_ext),
        .cin(1'b0), .s(mant_add_out), .cout()
    );

    // subtração de mantissas
    wire [27:0] mant_sub_out;
    n_bit_subtractor #(28) sub_mant (
        .a(mant_big_ext), .b(mant_small_ext),
        .s(mant_sub_out), .cout()
    );

    // shift right de 1 ao normalizar após carry de soma
    wire [26:0] mant_after_carry;
    wire        carry_shift_sticky;
    right_shift_one_sticky_28_to_27 sh_carry (
        .in(mant_add_out),
        .out(mant_after_carry), .sticky(carry_shift_sticky)
    );

    // exp_res + 1  (usado após carry de soma)
    wire [7:0] exp_plus_one;
    n_bit_adder #(8) add_exp_one (
        .a(exp_big), .b(8'd1),
        .cin(1'b0), .s(exp_plus_one), .cout()
    );

    // normalização à esquerda
    wire [26:0] mant_after_lshift;
    left_shift_27 sh_norm (
        .in(mant_norm_pre), .shamt(lz_used),
        .out(mant_after_lshift)
    );

    // exp_res - lz_used
    wire [7:0] exp_minus_lz;
    n_bit_subtractor #(8) sub_exp_lz (
        .a(exp_big), .b({3'b000, lz_used}),
        .s(exp_minus_lz), .cout()
    );

    // arredondamento
    wire [24:0] rounded_plus_one;
    n_bit_adder #(25) add_round (
        .a(rounded_main_pre), .b({24'd0, round_inc}),
        .cin(1'b0), .s(rounded_plus_one), .cout()
    );

    // shift right de 1 se arredondamento gerar carry no bit 24
    wire [24:0] rounded_after_carry;
    right_shift_one_25 sh_round_carry (
        .in(rounded_plus_one), .out(rounded_after_carry)
    );

    // exp_res + 1 após carry de arredondamento
    wire [7:0] exp_plus_one_round;
        n_bit_adder #(8) add_exp_round_one (
        .a(exp_before_round), .b(8'd1),
        .cin(1'b0), .s(exp_plus_one_round), .cout()
    );

    // Lógica combinacional de add/sub
    always @(*) begin
        addsub_result    = 32'h00000000;
        addsub_inv_op    = 1'b0;
        addsub_overflow  = 1'b0;
        addsub_underflow = 1'b0;
        addsub_inexact   = 1'b0;

        sign_a = 1'b0; sign_b = 1'b0; sign_b_eff = 1'b0;
        sign_res = 1'b0; sign_big = 1'b0; sign_small = 1'b0;
        same_sign = 1'b0;

        exp_a_raw = 8'd0; exp_b_raw = 8'd0;
        exp_a_eff = 8'd0; exp_b_eff = 8'd0;
        exp_big = 8'd0; exp_small = 8'd0; exp_res = 8'd0;
        exp_before_round = 8'd0;

        frac_a = 23'd0; frac_b = 23'd0;

        is_zero_a = 1'b0; is_zero_b = 1'b0;
        is_inf_a  = 1'b0; is_inf_b  = 1'b0;
        is_nan_a  = 1'b0; is_nan_b  = 1'b0;
        is_snan_a = 1'b0; is_snan_b = 1'b0;

        mant_a = 27'd0; mant_b = 27'd0; mant_big = 27'd0; mant_small = 27'd0;
        mant_big_ext = 28'd0; mant_small_ext = 28'd0;
        mant_norm_pre = 27'd0; mant_norm = 27'd0;
        sticky_align = 1'b0;

        rounded_main_pre = 25'd0; rounded_main = 25'd0;
        out_exp = 8'd0; out_frac = 23'd0;

        lz_count = 5'd0; lz_used = 5'd0; lz_found = 1'b0;
        round_inc = 1'b0;
        result_ready = 1'b0;

        // Fase 1: extração dos campos
        sign_a     = a_r[31];
        sign_b     = b_r[31];
        // SUB inverte o sinal efetivo de B
        sign_b_eff = b_r[31] ^ (op_r == 3'b001);

        exp_a_raw  = a_r[30:23];
        exp_b_raw  = b_r[30:23];
        frac_a     = a_r[22:0];
        frac_b     = b_r[22:0];

        // Fase 2: classificação
        is_zero_a = (exp_a_raw == 8'd0)   && (frac_a == 23'd0);
        is_zero_b = (exp_b_raw == 8'd0)   && (frac_b == 23'd0);
        is_inf_a  = (exp_a_raw == 8'hff)  && (frac_a == 23'd0);
        is_inf_b  = (exp_b_raw == 8'hff)  && (frac_b == 23'd0);
        is_nan_a  = (exp_a_raw == 8'hff)  && (frac_a != 23'd0);
        is_nan_b  = (exp_b_raw == 8'hff)  && (frac_b != 23'd0);

        is_snan_a = is_nan_a && (frac_a[22] == 1'b0);
        is_snan_b = is_nan_b && (frac_b[22] == 1'b0);

        // Expoente efetivo: subnormais usam exp=1 para alinhamento
        exp_a_eff = (exp_a_raw == 8'd0) ? 8'd1 : exp_a_raw;
        exp_b_eff = (exp_b_raw == 8'd0) ? 8'd1 : exp_b_raw;

        // Mantissa com hidden bit e 3 bits de guarda (para arredondamento)
        mant_a = (exp_a_raw == 8'd0) ? {1'b0, frac_a, 3'b000}
                                      : {1'b1, frac_a, 3'b000};
        mant_b = (exp_b_raw == 8'd0) ? {1'b0, frac_b, 3'b000}
                                      : {1'b1, frac_b, 3'b000};


        // Fase 3: casos especiais

        // NaN 
        if (is_nan_a || is_nan_b) begin
            addsub_inv_op = is_snan_a || is_snan_b;
            if (is_nan_a)
                addsub_result = {1'b0, 8'hff, 1'b1, a_r[21:0]};
            else
                addsub_result = {1'b0, 8'hff, 1'b1, b_r[21:0]};
            result_ready = 1'b1;
        end

        // Infinito
        else if (is_inf_a || is_inf_b) begin
            if (is_inf_a && is_inf_b && (sign_a != sign_b_eff)) begin
                addsub_result = 32'h7fc00000;
                addsub_inv_op = 1'b1;
            end
            else if (is_inf_a)
                addsub_result = {sign_a,     8'hff, 23'd0};
            else
                addsub_result = {sign_b_eff, 8'hff, 23'd0};
            result_ready = 1'b1;
        end

        // Ambos zero
        else if (is_zero_a && is_zero_b) begin
            addsub_result = (sign_a && sign_b_eff) ? 32'h80000000 : 32'h00000000;
            result_ready  = 1'b1;
        end

        // Um dos operandos é zero
        else if (is_zero_a) begin
            addsub_result = {sign_b_eff, b_r[30:0]};
            result_ready  = 1'b1;
        end
        else if (is_zero_b) begin
            addsub_result = a_r;
            result_ready  = 1'b1;
        end

        // Fase 4: caminho normal (ambos finitos, não zero)
        else begin
            if ((exp_a_eff > exp_b_eff) ||
               ((exp_a_eff == exp_b_eff) && (mant_a >= mant_b))) begin
                mant_big   = mant_a;
                mant_small = mant_b;
                exp_big    = exp_a_eff;
                exp_small  = exp_b_eff;
                sign_big   = sign_a;
                sign_small = sign_b_eff;
            end
            else begin
                mant_big   = mant_b;
                mant_small = mant_a;
                exp_big    = exp_b_eff;
                exp_small  = exp_a_eff;
                sign_big   = sign_b_eff;
                sign_small = sign_a;
            end

            same_sign = (sign_big == sign_small);
            sign_res  = sign_big;
            exp_res   = exp_big;
            exp_before_round = exp_big;

            
            sticky_align = align_sticky;

            mant_big_ext   = {1'b0, mant_big};
            mant_small_ext = {1'b0, mant_small_shifted};

            // Soma ou subtração de mantissas 
            if (same_sign) begin
                // SOMA
                if (mant_add_out[27]) begin
                    mant_norm = mant_after_carry;
                    if (carry_shift_sticky || sticky_align)
                        addsub_inexact = 1'b1;
                    mant_norm[0] = mant_norm[0] | sticky_align;
                    exp_res = exp_plus_one;
                    exp_before_round = exp_plus_one;
                end
                else begin
                    mant_norm = mant_add_out[26:0];
                    exp_before_round = exp_big;
                    mant_norm[0] = mant_norm[0] | sticky_align;
                    if (sticky_align)
                        addsub_inexact = 1'b1;
                end
            end
            else begin
                // SUBTRAÇÃO
                mant_norm_pre = mant_sub_out[26:0];

                if (mant_norm_pre == 27'd0 && !sticky_align) begin
                    // Resultado exatamente zero
                    addsub_result = 32'h00000000;
                    result_ready  = 1'b1;
                end
                else begin
                    mant_norm_pre[0] = mant_norm_pre[0] | sticky_align;
                    if (sticky_align)
                        addsub_inexact = 1'b1;

                    // Conta zeros à esquerda para normalização
                    lz_count = 5'd0;
                    lz_found = 1'b0;
                    for (i = 26; i >= 0; i = i - 1) begin
                        if (!lz_found) begin
                            if (mant_norm_pre[i] == 1'b1)
                                lz_found = 1'b1;
                            else
                                lz_count = lz_count + 1'b1;
                        end
                    end

                   
                    if (exp_res == 8'd0)
                        lz_used = 5'd0;
                    else if ({3'b000, lz_count} >= exp_res)
                        lz_used = exp_res[4:0] - 5'd1;
                    else
                        lz_used = lz_count;

                    mant_norm = mant_after_lshift;
                    exp_res   = exp_minus_lz;
                    exp_before_round = exp_minus_lz;
                end
            end

            // Arredondamento (round-to-nearest-even) 
            if (!result_ready && mant_norm != 27'd0) begin
                exp_res = exp_before_round;
                round_inc = mant_norm[2] &
                            (mant_norm[1] | mant_norm[0] | mant_norm[3]);

                if (mant_norm[2] | mant_norm[1] | mant_norm[0])
                    addsub_inexact = 1'b1;

                rounded_main_pre = {1'b0, mant_norm[26:3]};
                rounded_main     = rounded_plus_one;

                if (rounded_main[24]) begin
                    rounded_main = rounded_after_carry;
                    exp_res      = exp_plus_one_round;
                end

                // Verificação de overflow
                if (exp_res == 8'hff) begin
                    addsub_result   = {sign_res, 8'hff, 23'd0};
                    addsub_overflow = 1'b1;
                    addsub_inexact  = 1'b1;
                end

                // Verificação de subnormal / underflow
                else if ((exp_res == 8'd0) ||
                         ((exp_res == 8'd1) && (rounded_main[23] == 1'b0))) begin
                    out_exp  = 8'd0;
                    out_frac = rounded_main[22:0];
                    if (addsub_inexact)
                        addsub_underflow = 1'b1;
                    addsub_result = {sign_res, out_exp, out_frac};
                end

                // Resultado normal 
                else begin
                    out_exp  = exp_res;
                    out_frac = rounded_main[22:0];
                    addsub_result = {sign_res, out_exp, out_frac};
                end
            end
        end 
    end 

    // MUL 
    wire [31:0] mul_result;
    wire        mul_inv_op, mul_overflow, mul_underflow, mul_inexact;
    assign mul_result    = 32'h00000000;
    assign mul_inv_op    = 1'b0;
    assign mul_overflow  = 1'b0;
    assign mul_underflow = 1'b0;
    assign mul_inexact   = 1'b0;

    // DIV 
    wire [31:0] div_result;
    wire        div_inv_op, div_div_zero, div_overflow, div_underflow, div_inexact;
    assign div_result    = 32'h00000000;
    assign div_inv_op    = 1'b0;
    assign div_div_zero  = 1'b0;
    assign div_overflow  = 1'b0;
    assign div_underflow = 1'b0;
    assign div_inexact   = 1'b0;

    // EQ / SLT 
    wire [31:0] cmp_result;
    wire        cmp_inv_op;
    assign cmp_result = 32'h00000000;
    assign cmp_inv_op = 1'b0;

    // FSM 
    always @(posedge clock) begin
        if (reset) begin
            state   <= ST_IDLE;
            a_r     <= 32'd0;
            b_r     <= 32'd0;
            op_r    <= 3'd0;
            c       <= 32'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
            f_inv_op    <= 1'b0;
            f_div_zero  <= 1'b0;
            f_overflow  <= 1'b0;
            f_underflow <= 1'b0;
            f_inexact   <= 1'b0;
        end
        else begin
            case (state)

                ST_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    f_inv_op    <= 1'b0;
                    f_div_zero  <= 1'b0;
                    f_overflow  <= 1'b0;
                    f_underflow <= 1'b0;
                    f_inexact   <= 1'b0;

                    if (start) begin
                        a_r   <= a;
                        b_r   <= b;
                        op_r  <= op;
                        busy  <= 1'b1;
                        state <= ST_CALC;
                    end
                end

                ST_CALC: begin
                    case (op_r)
                        3'b000, 3'b001: begin
                            c           <= addsub_result;
                            f_inv_op    <= addsub_inv_op;
                            f_div_zero  <= 1'b0;
                            f_overflow  <= addsub_overflow;
                            f_underflow <= addsub_underflow;
                            f_inexact   <= addsub_inexact;
                        end
                        3'b010: begin
                            c           <= mul_result;
                            f_inv_op    <= mul_inv_op;
                            f_div_zero  <= 1'b0;
                            f_overflow  <= mul_overflow;
                            f_underflow <= mul_underflow;
                            f_inexact   <= mul_inexact;
                        end
                        3'b011: begin
                            c           <= div_result;
                            f_inv_op    <= div_inv_op;
                            f_div_zero  <= div_div_zero;
                            f_overflow  <= div_overflow;
                            f_underflow <= div_underflow;
                            f_inexact   <= div_inexact;
                        end
                        3'b100, 3'b101: begin
                            c           <= cmp_result;
                            f_inv_op    <= cmp_inv_op;
                            f_div_zero  <= 1'b0;
                            f_overflow  <= 1'b0;
                            f_underflow <= 1'b0;
                            f_inexact   <= 1'b0;
                        end
                        default: begin
                            c           <= 32'h7fc00000;
                            f_inv_op    <= 1'b1;
                            f_div_zero  <= 1'b0;
                            f_overflow  <= 1'b0;
                            f_underflow <= 1'b0;
                            f_inexact   <= 1'b0;
                        end
                    endcase
                    state <= ST_FINISH;
                end

                ST_FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


// MÓDULOS AUXILIARES

// Full adder de 1 bit
module full_adder (
    input  wire a, b, cin,
    output wire s, cout
);
    assign s    = a ^ b ^ cin;
    assign cout = (a & b) | (cin & (a ^ b));
endmodule

// Somador ripple-carry de N bits
module n_bit_adder #(parameter N = 32) (
    input  wire [N-1:0] a, b,
    input  wire         cin,
    output wire [N-1:0] s,
    output wire         cout
);
    wire [N:0] carry;
    assign carry[0] = cin;
    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : gen_add
            full_adder fa (
                .a(a[k]), .b(b[k]), .cin(carry[k]),
                .s(s[k]), .cout(carry[k+1])
            );
        end
    endgenerate
    assign cout = carry[N];
endmodule

// Subtrator de N bits (complemento de 2)
module n_bit_subtractor #(parameter N = 32) (
    input  wire [N-1:0] a, b,
    output wire [N-1:0] s,
    output wire         cout
);
    n_bit_adder #(N) sub_add (
        .a(a), .b(~b), .cin(1'b1),
        .s(s), .cout(cout)
    );
endmodule

// Shift right com sticky de 27 bits
module right_shift_sticky_27 (
    input  wire [26:0] in,
    input  wire [7:0]  shamt,
    output reg  [26:0] out,
    output reg         sticky
);
    integer j;
    always @(*) begin
        out    = 27'd0;
        sticky = 1'b0;

        if (shamt >= 8'd27) begin
            sticky = |in;
        end
        else begin
            for (j = 0; j < 27; j = j + 1) begin
                if ((j + shamt) < 27)
                    out[j] = in[j + shamt];
                else
                    out[j] = 1'b0;
            end
            for (j = 0; j < 27; j = j + 1) begin
                if (j < shamt)
                    sticky = sticky | in[j];
            end
        end
    end
endmodule

// Shift left de 27 bits
module left_shift_27 (
    input  wire [26:0] in,
    input  wire [4:0]  shamt,
    output reg  [26:0] out
);
    integer j;
    always @(*) begin
        out = 27'd0;
        if (shamt < 5'd27) begin
            for (j = 0; j < 27; j = j + 1) begin
                if (j >= shamt)
                    out[j] = in[j - shamt];
                else
                    out[j] = 1'b0;
            end
        end
    end
endmodule

// Shift right de 1 bit
module right_shift_one_sticky_28_to_27 (
    input  wire [27:0] in,
    output wire [26:0] out,
    output wire        sticky
);
    assign sticky  = in[0];
    assign out[26] = in[27];
    assign out[25] = in[26];
    assign out[24] = in[25];
    assign out[23] = in[24];
    assign out[22] = in[23];
    assign out[21] = in[22];
    assign out[20] = in[21];
    assign out[19] = in[20];
    assign out[18] = in[19];
    assign out[17] = in[18];
    assign out[16] = in[17];
    assign out[15] = in[16];
    assign out[14] = in[15];
    assign out[13] = in[14];
    assign out[12] = in[13];
    assign out[11] = in[12];
    assign out[10] = in[11];
    assign out[9]  = in[10];
    assign out[8]  = in[9];
    assign out[7]  = in[8];
    assign out[6]  = in[7];
    assign out[5]  = in[6];
    assign out[4]  = in[5];
    assign out[3]  = in[4];
    assign out[2]  = in[3];
    assign out[1]  = in[2];

    assign out[0]  = in[1] | in[0];
endmodule

// Shift right de 1 bit em 25 bits
// (usado ao tratar carry de arredondamento)
module right_shift_one_25 (
    input  wire [24:0] in,
    output wire [24:0] out
);
    assign out[24] = 1'b0;
    assign out[23] = in[24];
    assign out[22] = in[23];
    assign out[21] = in[22];
    assign out[20] = in[21];
    assign out[19] = in[20];
    assign out[18] = in[19];
    assign out[17] = in[18];
    assign out[16] = in[17];
    assign out[15] = in[16];
    assign out[14] = in[15];
    assign out[13] = in[14];
    assign out[12] = in[13];
    assign out[11] = in[12];
    assign out[10] = in[11];
    assign out[9]  = in[10];
    assign out[8]  = in[9];
    assign out[7]  = in[8];
    assign out[6]  = in[7];
    assign out[5]  = in[6];
    assign out[4]  = in[5];
    assign out[3]  = in[4];
    assign out[2]  = in[3];
    assign out[1]  = in[2];
    assign out[0]  = in[1];
endmodule
