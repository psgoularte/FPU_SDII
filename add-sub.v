module fpu (
    input  wire        clock, reset, start,
    input  wire [31:0] a, b,
    input  wire [2:0]  op,
    output reg  [31:0] c,
    output reg         busy, done,
    output reg         f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

localparam ST_IDLE   = 2'd0;
localparam ST_CALC   = 2'd1;
localparam ST_FINISH = 2'd2;

reg [1:0]  state;
reg [31:0] a_r, b_r;
reg [2:0]  op_r;

// ADD/SUB 
reg [31:0] addsub_result;
reg        addsub_inv_op, addsub_overflow, addsub_underflow, addsub_inexact;

reg        sign_a, sign_b, sign_b_eff, sign_res, sign_big, sign_small, same_sign;
reg [7:0]  exp_a_raw, exp_b_raw, exp_a_eff, exp_b_eff, exp_big, exp_small, exp_res;
reg [22:0] frac_a, frac_b;
reg        is_zero_a, is_zero_b, is_inf_a, is_inf_b, is_nan_a, is_nan_b, is_snan_a, is_snan_b;
reg [26:0] mant_a, mant_b, mant_big, mant_small, mant_small_shifted, mant_norm;
reg [27:0] mant_sum;
reg [24:0] rounded_main;
reg [7:0]  out_exp;
reg [22:0] out_frac;
reg        sticky_acc, round_inc;
reg [4:0]  lz_count;
reg        lz_found;
integer    shift_amt, i;

always @(*) begin
    addsub_result    = 32'h00000000;
    addsub_inv_op    = 1'b0;
    addsub_overflow  = 1'b0;
    addsub_underflow = 1'b0;
    addsub_inexact   = 1'b0;

    sign_a = 1'b0; sign_b = 1'b0; sign_b_eff = 1'b0; sign_res = 1'b0;
    sign_big = 1'b0; sign_small = 1'b0; same_sign = 1'b0;
    exp_a_raw = 8'd0; exp_b_raw = 8'd0; exp_a_eff = 8'd0; exp_b_eff = 8'd0;
    exp_big = 8'd0; exp_small = 8'd0; exp_res = 8'd0;
    frac_a = 23'd0; frac_b = 23'd0;
    is_zero_a = 1'b0; is_zero_b = 1'b0; is_inf_a = 1'b0; is_inf_b = 1'b0;
    is_nan_a = 1'b0; is_nan_b = 1'b0; is_snan_a = 1'b0; is_snan_b = 1'b0;
    mant_a = 27'd0; mant_b = 27'd0; mant_big = 27'd0; mant_small = 27'd0;
    mant_small_shifted = 27'd0; mant_sum = 28'd0; mant_norm = 27'd0;
    rounded_main = 25'd0; out_exp = 8'd0; out_frac = 23'd0;
    sticky_acc = 1'b0; round_inc = 1'b0; shift_amt = 0;
    lz_count = 5'd0; lz_found = 1'b0;

    sign_a     = a_r[31];
    sign_b     = b_r[31];
    sign_b_eff = b_r[31] ^ (op_r == 3'b001);
    exp_a_raw  = a_r[30:23]; exp_b_raw = b_r[30:23];
    frac_a     = a_r[22:0];  frac_b    = b_r[22:0];

    is_zero_a = (exp_a_raw == 8'd0)  && (frac_a == 23'd0);
    is_zero_b = (exp_b_raw == 8'd0)  && (frac_b == 23'd0);
    is_inf_a  = (exp_a_raw == 8'hff) && (frac_a == 23'd0);
    is_inf_b  = (exp_b_raw == 8'hff) && (frac_b == 23'd0);
    is_nan_a  = (exp_a_raw == 8'hff) && (frac_a != 23'd0);
    is_nan_b  = (exp_b_raw == 8'hff) && (frac_b != 23'd0);
    is_snan_a = is_nan_a && (frac_a[22] == 1'b0);
    is_snan_b = is_nan_b && (frac_b[22] == 1'b0);

    exp_a_eff = (exp_a_raw == 8'd0) ? 8'd1 : exp_a_raw;
    exp_b_eff = (exp_b_raw == 8'd0) ? 8'd1 : exp_b_raw;

    mant_a = (exp_a_raw == 8'd0) ? {1'b0, frac_a, 3'b000} : {1'b1, frac_a, 3'b000};
    mant_b = (exp_b_raw == 8'd0) ? {1'b0, frac_b, 3'b000} : {1'b1, frac_b, 3'b000};

    if (is_nan_a || is_nan_b) begin
        addsub_result = 32'h7fc00000;
        addsub_inv_op = is_snan_a || is_snan_b;
    end
    else if (is_inf_a || is_inf_b) begin
        if (is_inf_a && is_inf_b && (sign_a != sign_b_eff)) begin
            addsub_result = 32'h7fc00000;
            addsub_inv_op = 1'b1;
        end
        else if (is_inf_a) addsub_result = {sign_a,     8'hff, 23'd0};
        else               addsub_result = {sign_b_eff, 8'hff, 23'd0};
    end
    else if (is_zero_a && is_zero_b) begin
        addsub_result = (sign_a && sign_b_eff) ? 32'h80000000 : 32'h00000000;
    end
    else if (is_zero_a) addsub_result = {sign_b_eff, b_r[30:0]};
    else if (is_zero_b) addsub_result = a_r;
    else begin
        if ((exp_a_eff > exp_b_eff) || ((exp_a_eff == exp_b_eff) && (mant_a >= mant_b))) begin
            mant_big = mant_a; mant_small = mant_b;
            exp_big = exp_a_eff; exp_small = exp_b_eff;
            sign_big = sign_a; sign_small = sign_b_eff;
        end else begin
            mant_big = mant_b; mant_small = mant_a;
            exp_big = exp_b_eff; exp_small = exp_a_eff;
            sign_big = sign_b_eff; sign_small = sign_a;
        end

        same_sign = (sign_big == sign_small);
        exp_res   = exp_big;
        sign_res  = sign_big;

        mant_small_shifted = mant_small;
        shift_amt  = exp_big - exp_small;
        sticky_acc = 1'b0;

        if (shift_amt >= 27) begin
            sticky_acc         = (mant_small != 27'd0);
            mant_small_shifted = 27'd0;
        end else if (shift_amt > 0) begin
            for (i = 0; i < 26; i = i + 1) begin
                if (i < shift_amt) begin
                    sticky_acc         = sticky_acc | mant_small_shifted[0];
                    mant_small_shifted = mant_small_shifted >> 1;
                end
            end
        end
        mant_small_shifted[0] = mant_small_shifted[0] | sticky_acc;
        if (sticky_acc) addsub_inexact = 1'b1;

        if (same_sign) begin
            mant_sum = {1'b0, mant_big} + {1'b0, mant_small_shifted};
            if (mant_sum[27]) begin
                mant_norm    = mant_sum[27:1];
                mant_norm[0] = mant_norm[0] | mant_sum[0];
                exp_res      = exp_res + 1'b1;
            end else
                mant_norm = mant_sum[26:0];
        end else begin
            mant_sum  = {1'b0, mant_big} - {1'b0, mant_small_shifted};
            mant_norm = mant_sum[26:0];

            if (mant_norm == 27'd0) begin
                addsub_result = 32'h00000000;
            end else begin
                lz_count = 5'd0; lz_found = 1'b0;
                for (i = 26; i >= 0; i = i - 1) begin
                    if (!lz_found) begin
                        if (mant_norm[i] == 1'b1) lz_found = 1'b1;
                        else lz_count = lz_count + 1'b1;
                    end
                end
                if (lz_count >= exp_res) lz_count = exp_res - 5'd1;
                mant_norm = mant_norm << lz_count;
                exp_res   = exp_res - lz_count;
            end
        end

        if (mant_norm != 27'd0) begin
            round_inc    = mant_norm[2] & (mant_norm[1] | mant_norm[0] | mant_norm[3]);
            rounded_main = {1'b0, mant_norm[26:3]} + {{24{1'b0}}, round_inc};

            if (mant_norm[2] | mant_norm[1] | mant_norm[0])
                addsub_inexact = 1'b1;

            if (rounded_main[24]) begin
                rounded_main = rounded_main >> 1;
                exp_res      = exp_res + 1'b1;
            end

            if (exp_res == 8'hff) begin
                addsub_result   = {sign_res, 8'hff, 23'd0};
                addsub_overflow = 1'b1;
                addsub_inexact  = 1'b1;
            end else if ((exp_res == 8'd1) && (rounded_main[23] == 1'b0)) begin
                out_exp  = 8'd0;
                out_frac = rounded_main[22:0];
                if ((exp_res <= 8'd1) && addsub_inexact)
                    addsub_underflow = 1'b1;
                addsub_result = {sign_res, out_exp, out_frac};
            end else begin
                out_exp       = exp_res;
                out_frac      = rounded_main[22:0];
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
        state <= ST_IDLE; a_r <= 32'd0; b_r <= 32'd0; op_r <= 3'd0;
        c <= 32'd0; busy <= 1'b0; done <= 1'b0;
        f_inv_op <= 1'b0; f_div_zero <= 1'b0; f_overflow <= 1'b0;
        f_underflow <= 1'b0; f_inexact <= 1'b0;
    end else begin
        case (state)
            ST_IDLE: begin
                done <= 1'b0; busy <= 1'b0;
                f_inv_op <= 1'b0; f_div_zero <= 1'b0; f_overflow <= 1'b0;
                f_underflow <= 1'b0; f_inexact <= 1'b0;
                if (start) begin
                    a_r <= a; b_r <= b; op_r <= op;
                    busy <= 1'b1; state <= ST_CALC;
                end
            end

            ST_CALC: begin
                case (op_r)
                    3'b000, 3'b001: begin
                        c <= addsub_result; f_inv_op <= addsub_inv_op;
                        f_div_zero <= 1'b0; f_overflow <= addsub_overflow;
                        f_underflow <= addsub_underflow; f_inexact <= addsub_inexact;
                    end
                    3'b010: begin
                        c <= mul_result; f_inv_op <= mul_inv_op;
                        f_div_zero <= 1'b0; f_overflow <= mul_overflow;
                        f_underflow <= mul_underflow; f_inexact <= mul_inexact;
                    end
                    3'b011: begin
                        c <= div_result; f_inv_op <= div_inv_op;
                        f_div_zero <= div_div_zero; f_overflow <= div_overflow;
                        f_underflow <= div_underflow; f_inexact <= div_inexact;
                    end
                    3'b100, 3'b101: begin
                        c <= cmp_result; f_inv_op <= cmp_inv_op;
                        f_div_zero <= 1'b0; f_overflow <= 1'b0;
                        f_underflow <= 1'b0; f_inexact <= 1'b0;
                    end
                    default: begin
                        c <= 32'h7fc00000; f_inv_op <= 1'b1;
                        f_div_zero <= 1'b0; f_overflow <= 1'b0;
                        f_underflow <= 1'b0; f_inexact <= 1'b0;
                    end
                endcase
                state <= ST_FINISH;
            end

            ST_FINISH: begin
                busy <= 1'b0; done <= 1'b1; state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
