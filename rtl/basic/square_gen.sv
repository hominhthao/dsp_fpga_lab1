module square_gen (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [31:0]        phase_inc,
    input  wire [8:0]         amp_q8,
    input  wire [8:0]         duty_q8,
    output reg  signed [23:0] wave_out
);

    reg [31:0] phase_acc;
    reg signed [33:0] amp_product;
    reg signed [23:0] amp_level;
    reg signed [23:0] sample_value;
    reg high_level;

    always @(*) begin
        amp_product = $signed(24'sh7FFFFF) * $signed({1'b0, amp_q8});
        amp_level   = amp_product >>> 8;

        if (duty_q8 == 9'd0)
            high_level = 1'b0;
        else if (duty_q8 >= 9'd256)
            high_level = 1'b1;
        else
            high_level = ({1'b0, phase_acc[31:24]} < duty_q8);

        if (high_level)
            sample_value = amp_level;
        else
            sample_value = -amp_level;
    end

    // Phase va ngo ra chi cap nhat tai sample_en.
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
