module lfsr_noise #(
    parameter [23:0] SEED = 24'h5A_C3_E7
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [15:0]        update_div_samples,
    input  wire [8:0]         noise_amp_q8,
    output reg  signed [23:0] noise_out
);

    localparam [23:0] SAFE_SEED =
        (SEED == 24'd0) ? 24'h00_00_01 : SEED;

    reg [23:0] lfsr_state;
    reg [15:0] sample_count;

    wire feedback;
    reg signed [23:0] noise_fullscale;
    reg signed [33:0] scaled_product;
    reg signed [23:0] scaled_noise;

    assign feedback = lfsr_state[23] ^ lfsr_state[22] ^
                      lfsr_state[21] ^ lfsr_state[16];

    always @(*) begin
        noise_fullscale = $signed(lfsr_state);
        scaled_product = noise_fullscale * $signed({1'b0, noise_amp_q8});
        scaled_noise = scaled_product >>> 8;
    end

    // update_div_samples quy dinh so mau audio giua hai lan cap nhat LFSR.
    // Gia tri 1 nghia la cap nhat noise tai moi sample_en.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state  <= SAFE_SEED;
            sample_count <= 16'd0;
            noise_out   <= 24'sd0;
        end
        else if (sample_en) begin
            noise_out <= scaled_noise;

            if (update_div_samples <= 16'd1) begin
                lfsr_state   <= {lfsr_state[22:0], feedback};
                sample_count <= 16'd0;
            end
            else if (sample_count >= update_div_samples - 16'd1) begin
                lfsr_state   <= {lfsr_state[22:0], feedback};
                sample_count <= 16'd0;
            end
            else begin
                sample_count <= sample_count + 16'd1;
            end
        end
    end

endmodule
