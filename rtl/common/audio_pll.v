`timescale 1ns/10ps

module audio_pll (
    input  wire refclk,
    input  wire rst,
    output wire clk_12m288,
    output wire locked
);

    wire [0:0] outclk;

    // PLL tao clock audio 12.288 MHz tu CLOCK_50.
    // Clock nay bang 256 lan tan so lay mau 48 kHz va dung lam MCLK cho WM8731.
    altera_pll #(
        .fractional_vco_multiplier ("true"),
        .reference_clock_frequency ("50.0 MHz"),
        .operation_mode             ("direct"),
        .number_of_clocks           (1),
        .output_clock_frequency0    ("12.288000 MHz"),
        .phase_shift0               ("0 ps"),
        .duty_cycle0                (50)
    ) u_pll (
        .rst      (rst),
        .refclk   (refclk),
        .outclk   (outclk),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0)
    );

    assign clk_12m288 = outclk[0];

endmodule
