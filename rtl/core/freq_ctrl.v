module freq_ctrl #(
    parameter [31:0] PHASE_INC_DEFAULT = 32'd8_388_608,
    parameter [31:0] PHASE_INC_STEP    = 32'd8_388_608,
    parameter [31:0] PHASE_INC_MIN     = 32'd8_388_608,
    parameter [31:0] PHASE_INC_MAX     = 32'd134_217_728,
    parameter integer DEBOUNCE_CNT     = 1_000_000
)(
	input wire clk,
	input wire rst,
	input wire key_freq_up,
	input wire key_freq_down,
	output reg [31:0] phase_inc
);
    wire pulse_up, pulse_down;

    button_pulse #(
        .DEBOUNCE_CNT(DEBOUNCE_CNT)
    ) u_up (
        .clk(clk), .rst(rst), .key_in(key_freq_up), .pulse_out(pulse_up)
    );

    button_pulse #(
        .DEBOUNCE_CNT(DEBOUNCE_CNT)
    ) u_down (
        .clk(clk), .rst(rst), .key_in(key_freq_down), .pulse_out(pulse_down)
    );

    always @(posedge clk) begin
        if (rst) begin
            phase_inc <= PHASE_INC_DEFAULT;
        end else if (pulse_up) begin
            if (phase_inc >= PHASE_INC_MAX - PHASE_INC_STEP)
                phase_inc <= PHASE_INC_MAX;
            else
                phase_inc <= phase_inc + PHASE_INC_STEP;
        end else if (pulse_down) begin
            if (phase_inc <= PHASE_INC_MIN + PHASE_INC_STEP)
                phase_inc <= PHASE_INC_MIN;
            else
                phase_inc <= phase_inc - PHASE_INC_STEP;
        end
    end
endmodule
