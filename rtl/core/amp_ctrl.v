module amp_ctrl #(
    parameter [7:0] AMP_DEFAULT = 8'd128,
    parameter [7:0] AMP_STEP    = 8'd16,
    parameter integer DEBOUNCE_CNT = 1_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        key_amp_up,
    input  wire        key_amp_down,
    output reg  [7:0]  amp_ctrl 	
);
    wire pulse_up, pulse_down;

    button_pulse #(
        .DEBOUNCE_CNT(DEBOUNCE_CNT)
    ) u_up (
        .clk(clk), .rst(rst), .key_in(key_amp_up), .pulse_out(pulse_up)
    );

    button_pulse #(
        .DEBOUNCE_CNT(DEBOUNCE_CNT)
    ) u_down (
        .clk(clk), .rst(rst), .key_in(key_amp_down), .pulse_out(pulse_down)
    );

    always @(posedge clk) begin
        if (rst) begin
            amp_ctrl <= AMP_DEFAULT;
        end else if (pulse_up) begin
            if (amp_ctrl > 8'd255 - AMP_STEP)
                amp_ctrl <= 8'd255;
            else
                amp_ctrl <= amp_ctrl + AMP_STEP;
        end else if (pulse_down) begin
            if (amp_ctrl < AMP_STEP)
                amp_ctrl <= 8'd0;
            else
                amp_ctrl <= amp_ctrl - AMP_STEP;
        end
    end
endmodule
