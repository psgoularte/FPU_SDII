module div(
    input clock, reset, start,
    input [31:0] a, b,
    output [31:0] c,
    output busy, done,
    output f_inv_op, f_div_zero, f_overflow, f_underflow, f_inexact
);

    // SINAIS INTERNOS (UC <-> FD)

    // controle
    wire load, prep, shift, sub, restore, set_q1, set_q0;
    wire count_en, grs_en, normalize, round, write_result;

    // status
    wire a_neg, count_done, grs_done, norm_done;

    // UNIDADE DE CONTROLE (UC)

    div_uc uc (
        .clock(clock),
        .reset(reset),
        .start(start),

        .a_neg(a_neg),
        .count_done(count_done),
        .grs_done(grs_done),
        .norm_done(norm_done),

        .load(load),
        .prep(prep),
        .shift(shift),
        .sub(sub),
        .restore(restore),
        .set_q1(set_q1),
        .set_q0(set_q0),
        .count_en(count_en),
        .grs_en(grs_en),
        .normalize(normalize),
        .round(round),
        .write_result(write_result),

        .done(done),
        .busy(busy)
    );

    // FLUXO DE DADOS (FD)

    div_fd fd (
        .clock(clock),
        .reset(reset),

        .a(a),
        .b(b),
        .c(c),

        // controle vindo da UC
        .load(load),
        .prep(prep),
        .shift(shift),
        .sub(sub),
        .restore(restore),
        .set_q1(set_q1),
        .set_q0(set_q0),
        .count_en(count_en),
        .grs_en(grs_en),
        .normalize(normalize),
        .round(round),
        .write_result(write_result),

        // status para UC
        .a_neg(a_neg),
        .count_done(count_done),
        .grs_done(grs_done),
        .norm_done(norm_done),

        // flags IEEE
        .f_inv_op(f_inv_op),
        .f_div_zero(f_div_zero),
        .f_overflow(f_overflow),
        .f_underflow(f_underflow),
        .f_inexact(f_inexact)
    );

endmodule