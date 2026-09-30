module sine_gen_top #(
    parameter [31:0] PHASE_INC_DEFAULT = 32'd8_388_608,
    parameter [31:0] PHASE_INC_STEP    = 32'd8_388_608,
    parameter [31:0] PHASE_INC_MIN     = 32'd8_388_608,
    parameter [31:0] PHASE_INC_MAX     = 32'd134_217_728,
    parameter [7:0]  AMP_DEFAULT       = 8'd128,
    parameter [7:0]  AMP_STEP          = 8'd16,
    parameter integer DEBOUNCE_CNT     = 1_000_000
)(
    input  wire         CLOCK_50,      // clk hệ thống 50MHz, từ pin có sẵn trong qsf
    input  wire  [3:0]  KEY,           // KEY[0]=freq_up, KEY[1]=freq_down,
    input  wire         rst_n,         // KEY[2]=amp_up, KEY[3]=amp_down (active-low)
    input  wire         sample_en,     // xung cho phép cập nhật mẫu, dùng chung với Audio CODEC
    output wire [31:0]  phase_inc_out,
    output wire [7:0]   amp_ctrl_out,
    output wire signed [23:0] sine_data_out
);

    wire [31:0] phase_inc;
    wire [7:0]  amp_ctrl;
    wire signed [23:0] sine_raw;

    freq_ctrl #(
        .PHASE_INC_DEFAULT(PHASE_INC_DEFAULT),
        .PHASE_INC_STEP   (PHASE_INC_STEP),
        .PHASE_INC_MIN    (PHASE_INC_MIN),
        .PHASE_INC_MAX    (PHASE_INC_MAX),
        .DEBOUNCE_CNT     (DEBOUNCE_CNT)
    ) u_freq_ctrl (
        .clk(CLOCK_50), .rst(~rst_n),
        .key_freq_up(KEY[0]), .key_freq_down(KEY[1]),
        .phase_inc(phase_inc)
    );

    amp_ctrl #(
        .AMP_DEFAULT  (AMP_DEFAULT),
        .AMP_STEP     (AMP_STEP),
        .DEBOUNCE_CNT (DEBOUNCE_CNT)
    ) u_amp_ctrl (
        .clk(CLOCK_50), .rst(~rst_n),
        .key_amp_up(KEY[2]), .key_amp_down(KEY[3]),
        .amp_ctrl(amp_ctrl)
    );

    sine_gen u_sine_gen (
        .clk(CLOCK_50),
        .rst(~rst_n),
        .sample_en(sample_en),
        .phase_inc(phase_inc),
        .sine_data(sine_raw)
    );

    amp_scaler u_amp_scaler (
        .sine_in(sine_raw),
        .amp_ctrl(amp_ctrl),
        .sine_out(sine_data_out)
    );

    assign phase_inc_out = phase_inc;
    assign amp_ctrl_out  = amp_ctrl;

endmodule
