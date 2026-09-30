module wm8731_i2s_tx (
    input  wire               clk_audio,
    input  wire               rst_n,
    input  wire signed [23:0] sample_async,
    output wire               aud_bclk,
    output wire               aud_daclrck,
    output reg                aud_dacdat,
    output reg                sample_req_toggle
);

    // Clock audio la 12.288 MHz.
    // BCLK bang clk_audio chia 4, tuong duong 3.072 MHz.
    // Moi frame stereo co 64 BCLK, suy ra tan so lay mau 48 kHz.
    reg [1:0] bclk_div;
    reg [5:0] slot_pos;
    reg       channel;
    reg signed [23:0] frame_sample;

    assign aud_bclk    = bclk_div[1];
    assign aud_daclrck = channel;

    always @(posedge clk_audio or negedge rst_n) begin
        if (!rst_n) begin
            bclk_div          <= 2'd0;
            slot_pos          <= 6'd31;
            channel           <= 1'b1;
            frame_sample      <= 24'sd0;
            aud_dacdat        <= 1'b0;
            sample_req_toggle <= 1'b0;
        end
        else begin
            bclk_div <= bclk_div + 2'd1;

            // Cap nhat du lieu noi tiep tai canh xuong cua BCLK.
            // CODEC lay du lieu tai canh len cua BCLK.
            if (bclk_div == 2'b11) begin
                if (slot_pos == 6'd31) begin
                    slot_pos   <= 6'd0;
                    channel    <= ~channel;
                    aud_dacdat <= 1'b0; // I2S tre 1 bit sau canh LRCLK

                    // Bat dau kenh trai cung la bat dau mot frame stereo moi.
                    if (channel == 1'b1) begin
                        frame_sample      <= sample_async;
                        sample_req_toggle <= ~sample_req_toggle;
                    end
                end
                else begin
                    if (slot_pos <= 6'd23)
                        aud_dacdat <= frame_sample[23 - slot_pos];
                    else
                        aud_dacdat <= 1'b0;

                    slot_pos <= slot_pos + 6'd1;
                end
            end
        end
    end

endmodule
