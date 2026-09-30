module sawtooth_gen (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [31:0]        phase_inc,
    input  wire [8:0]         amp_q8,
    output reg  signed [23:0] wave_out
);

    reg [31:0] phase_acc;
    reg signed [23:0] saw_fullscale;
    reg signed [33:0] scaled_product;
    reg signed [23:0] sample_value;

    always @(*) begin
        saw_fullscale = $signed(phase_acc[31:8] ^ 24'h800000);
        scaled_product = saw_fullscale * $signed({1'b0, amp_q8});
        sample_value = scaled_product >>> 8;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 32'd0;
            wave_out  <= 24'sd0;
        end
        else if (sample_en) begin
            wave_out  <= sample_value;
            phase_acc <= phase_acc + phase_inc;
        end
    end

endmodule
