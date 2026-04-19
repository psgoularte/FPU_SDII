module div_uc (
    input  wire clock, reset, start,

    // status do fluxo de dados
    input  wire a_neg,
    input  wire count_done,
    input  wire grs_done,
    input  wire norm_done,

    // sinais de controle
    output wire load,
    output wire prep,
    output wire shift,
    output wire sub,
    output wire restore,
    output wire set_q1,
    output wire set_q0,
    output wire count_en,
    output wire grs_en,
    output wire normalize,
    output wire round,
    output wire write_result,
    output wire done,
    output wire busy
);

    // estados
    localparam [3:0]
        IDLE      = 4'b0000,
        LOAD      = 4'b0001,
        PREP      = 4'b0010,
        SHIFT     = 4'b0011,
        SUB       = 4'b0100,
        CHECK     = 4'b0101,
        SET1      = 4'b0110,
        RESTORE   = 4'b0111,
        COUNT     = 4'b1000,
        GRS       = 4'b1001,
        NORMALIZE = 4'b1010,
        ROUND     = 4'b1011,
        WRITE     = 4'b1100,
        DONE      = 4'b1101;

    reg [3:0] state, next_state;

    // registrador de estado (sequencial)
    always @(posedge clock or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // lógica de próxima transição
    always @(*) begin
        next_state = state;

        case (state)
            IDLE:
                if (start) next_state = LOAD;

            LOAD:
                next_state = PREP;

            PREP:
                next_state = SHIFT;

            SHIFT:
                next_state = SUB;

            SUB:
                next_state = CHECK;

            CHECK:
                if (a_neg)
                    next_state = RESTORE;
                else
                    next_state = SET1;

            SET1:
                next_state = COUNT;

            RESTORE:
                next_state = COUNT;

            COUNT:
                if (count_done)
                    next_state = GRS;
                else
                    next_state = SHIFT;

            GRS:
                if (grs_done)
                    next_state = NORMALIZE;

            NORMALIZE:
                if (norm_done)
                    next_state = ROUND;

            ROUND:
                next_state = WRITE;

            WRITE:
                next_state = DONE;

            DONE:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    // Saídas
    assign load = ~(|(state ^ LOAD));
    assign prep = ~(|(state ^ PREP));
    assign shift = ~(|(state ^ SHIFT));
    assign sub = ~(|(state ^ SUB));
    assign restore = ~(|(state ^ RESTORE));
    assign set_q1 = ~(|(state ^ SET1));
    assign set_q0 = ~(|(state ^ RESTORE));
    assign count_en = ~(|(state ^ COUNT));
    assign grs_en = ~(|(state ^ GRS));
    assign normalize = ~(|(state ^ NORMALIZE));
    assign round = ~(|(state ^ ROUND));
    assign write_result = ~(|(state ^ WRITE));
    assign done = ~(|(state ^ DONE));

    // busy: ativo em qualquer estado diferente de IDLE e DONE
    assign busy = |(state ^ IDLE) & |(state ^ DONE);

endmodule