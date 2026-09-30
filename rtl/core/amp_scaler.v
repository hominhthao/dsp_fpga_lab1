module amp_scaler (
    input  wire signed [23:0] sine_in,     // từ sine_gen.sine_data
    input  wire        [7:0]  amp_ctrl,    // 0-255
    output wire signed [23:0] sine_out
);
    // Nhân 24-bit x 8-bit = 32-bit, dùng DSP block của Cyclone V
    wire signed [31:0] mult_result;
    assign mult_result = sine_in * $signed({1'b0, amp_ctrl}); // 9-bit signed để tránh sai dấu

    // amp_ctrl max = 255 ≈ 2^8, nên chia lại cho 2^8 để chuẩn hóa về full-scale khi amp_ctrl=255
    assign sine_out = mult_result[31:8];
endmodule