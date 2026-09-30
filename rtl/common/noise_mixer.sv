module noise_mixer (
    input  wire signed [23:0] wave_in,
    input  wire signed [23:0] noise_in,
    input  wire               noise_enable,
    output reg  signed [23:0] mixed_out
);

    localparam signed [24:0] MAX_24 = 25'sd8388607;
    localparam signed [24:0] MIN_24 = -25'sd8388608;

    wire signed [24:0] sum_ext;

    assign sum_ext = $signed({wave_in[23], wave_in}) +
                     $signed({noise_in[23], noise_in});

    // Cong waveform voi noise va gioi han ngo ra trong mien signed 24-bit.
    always @(*) begin
        if (!noise_enable)
            mixed_out = wave_in;
        else if (sum_ext > MAX_24)
            mixed_out = 24'sh7FFFFF;
        else if (sum_ext < MIN_24)
            mixed_out = 24'sh800000;
        else
            mixed_out = sum_ext[23:0];
    end

endmodule
