module debounce #(
    parameter integer STABLE_CYCLES = 1_000_000,
    parameter         INITIAL_STATE = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire noisy_in,
    output reg  debounced_out,
    output reg  rise_pulse,
    output reg  fall_pulse
);

    localparam integer COUNTER_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    reg sync_ff1;
    reg sync_ff2;
    reg [COUNTER_WIDTH-1:0] stable_count;

    // Dong bo 2 tang
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= INITIAL_STATE;
            sync_ff2 <= INITIAL_STATE;
        end
        else begin
            sync_ff1 <= noisy_in;
            sync_ff2 <= sync_ff1;
        end
    end

    // Loc debounce va tao xung canh
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounced_out <= INITIAL_STATE;
            stable_count  <= 0;
            rise_pulse    <= 1'b0;
            fall_pulse    <= 1'b0;
        end
        else begin
            rise_pulse <= 1'b0;
            fall_pulse <= 1'b0;

            if (sync_ff2 == debounced_out) begin
                stable_count <= 0;
            end
            else if (STABLE_CYCLES <= 1) begin
                debounced_out <= sync_ff2;
                stable_count  <= 0;

                if (sync_ff2)
                    rise_pulse <= 1'b1;
                else
                    fall_pulse <= 1'b1;
            end
            else if (stable_count >= STABLE_CYCLES - 1) begin
                debounced_out <= sync_ff2;
                stable_count  <= 0;

                if (sync_ff2)
                    rise_pulse <= 1'b1;
                else
                    fall_pulse <= 1'b1;
            end
            else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end

endmodule
