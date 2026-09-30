module triangle_gen (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [31:0]        phase_inc,
    input  wire [8:0]         amp_q8,
    output reg  signed [23:0] wave_out
);

    reg [31:0] phase_acc;
    reg [23:0] tri_unsigned;
    reg signed [24:0] tri_centered;
    reg signed [23:0] tri_fullscale;
    reg signed [33:0] scaled_product;
    reg signed [23:0] sample_value;

    always @(*) begin
        if (phase_acc[31])
            tri_unsigned = ~phase_acc[30:7];
        else
            tri_unsigned = phase_acc[30:7];

        tri_centered  = $signed({1'b0, tri_unsigned}) - 25'sd8388608;
        tri_fullscale = tri_centered[23:0];
        scaled_product = tri_fullscale * $signed({1'b0, amp_q8});
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
