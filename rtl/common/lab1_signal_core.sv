module lab1_signal_core #(
    parameter integer DEBOUNCE_CNT = 1_000_000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [2:0]         wave_sel,
    input  wire               ctrl_mode,
    input  wire               key_down,
    input  wire               key_up,
    input  wire [1:0]         duty_sel,
    input  wire               noise_enable,
    input  wire [8:0]         noise_amp_q8,
    input  wire [15:0]        noise_update_div_samples,
    output reg  signed [23:0] clean_wave,
    output wire signed [23:0] mixed_wave,
    output wire signed [23:0] sine_wave,
    output wire signed [23:0] square_wave,
    output wire signed [23:0] triangle_wave,
    output wire signed [23:0] sawtooth_wave,
    output wire signed [23:0] ecg_wave,
    output wire signed [23:0] noise_wave
);

    localparam [31:0] WAVE_PHASE_INC_1KHZ = 32'd89_478_485;
    localparam [31:0] WAVE_PHASE_INC_10KHZ = 32'd894_784_850;

    localparam [31:0] ECG_PHASE_INC_60BPM  = 32'd89_478;
    localparam [31:0] ECG_PHASE_INC_15BPM  = 32'd22_370;
    localparam [31:0] ECG_PHASE_INC_120BPM = 32'd178_958;

    wire [3:0] sine_key;
    wire [3:0] ecg_key;
    wire normal_freq_mode;
    wire ecg_freq_mode;
    wire amp_mode;

    wire [31:0] wave_phase_inc;
    wire [31:0] ecg_phase_inc;
    wire [7:0] wave_amp_ctrl;
    wire [7:0] ecg_amp_ctrl;
    wire [8:0] amp_q8;

    reg [8:0] duty_q8;

    assign normal_freq_mode = (~ctrl_mode) && (wave_sel <= 3'b011);
    assign ecg_freq_mode    = (~ctrl_mode) && (wave_sel == 3'b100);
    assign amp_mode         = ctrl_mode;

    // KEY active-low. Khi mot chuc nang khong duoc chon, dua KEY ao ve 1.
    assign sine_key[0] = normal_freq_mode ? key_up   : 1'b1;
    assign sine_key[1] = normal_freq_mode ? key_down : 1'b1;
    assign sine_key[2] = amp_mode         ? key_up   : 1'b1;
    assign sine_key[3] = amp_mode         ? key_down : 1'b1;

    assign ecg_key[0] = ecg_freq_mode ? key_up   : 1'b1;
    assign ecg_key[1] = ecg_freq_mode ? key_down : 1'b1;
    assign ecg_key[2] = amp_mode      ? key_up   : 1'b1;
    assign ecg_key[3] = amp_mode      ? key_down : 1'b1;

    // TV1 dieu khien tan so song thuong theo buoc 1 kHz, tu 1 kHz den 10 kHz.
    // amp_ctrl cua TV1 duoc dung chung cho Square, Triangle va Sawtooth.
    sine_gen_top #(
        .PHASE_INC_DEFAULT (WAVE_PHASE_INC_1KHZ),
        .PHASE_INC_STEP    (WAVE_PHASE_INC_1KHZ),
        .PHASE_INC_MIN     (WAVE_PHASE_INC_1KHZ),
        .PHASE_INC_MAX     (WAVE_PHASE_INC_10KHZ),
        .DEBOUNCE_CNT      (DEBOUNCE_CNT)
    ) u_sine_top (
        .CLOCK_50      (clk),
        .KEY           (sine_key),
        .rst_n         (rst_n),
        .sample_en     (sample_en),
        .phase_inc_out (wave_phase_inc),
        .amp_ctrl_out  (wave_amp_ctrl),
        .sine_data_out (sine_wave)
    );

    // ECG dung cung kieu dieu khien TV1, nhung tan so duoc doi sang BPM.
    // 60, 75, 90, 105, 120 BPM tuong ung buoc 15 BPM.
    ecg_gen_top #(
        .PHASE_INC_DEFAULT (ECG_PHASE_INC_60BPM),
        .PHASE_INC_STEP    (ECG_PHASE_INC_15BPM),
        .PHASE_INC_MIN     (ECG_PHASE_INC_60BPM),
        .PHASE_INC_MAX     (ECG_PHASE_INC_120BPM),
        .DEBOUNCE_CNT      (DEBOUNCE_CNT)
    ) u_ecg_top (
        .CLOCK_50      (clk),
        .KEY           (ecg_key),
        .rst_n         (rst_n),
        .sample_en     (sample_en),
        .phase_inc_out (ecg_phase_inc),
        .amp_ctrl_out  (ecg_amp_ctrl),
        .ecg_data_out  (ecg_wave)
    );

    assign amp_q8 = {1'b0, wave_amp_ctrl};

    always @(*) begin
        case (duty_sel)
            2'b00: duty_q8 = 9'd64;
            2'b01: duty_q8 = 9'd128;
            2'b10: duty_q8 = 9'd192;
            default: duty_q8 = 9'd256;
        endcase
    end

    square_gen u_square (
        .clk       (clk),
        .rst_n     (rst_n),
        .sample_en (sample_en),
        .phase_inc (wave_phase_inc),
        .amp_q8    (amp_q8),
        .duty_q8   (duty_q8),
        .wave_out  (square_wave)
    );

    triangle_gen u_triangle (
        .clk       (clk),
        .rst_n     (rst_n),
        .sample_en (sample_en),
        .phase_inc (wave_phase_inc),
        .amp_q8    (amp_q8),
        .wave_out  (triangle_wave)
    );

    sawtooth_gen u_sawtooth (
        .clk       (clk),
        .rst_n     (rst_n),
        .sample_en (sample_en),
        .phase_inc (wave_phase_inc),
        .amp_q8    (amp_q8),
        .wave_out  (sawtooth_wave)
    );

    lfsr_noise u_noise (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .sample_en              (sample_en),
        .update_div_samples     (noise_update_div_samples),
        .noise_amp_q8           (noise_amp_q8),
        .noise_out              (noise_wave)
    );

    always @(*) begin
        case (wave_sel)
            3'b000: clean_wave = sine_wave;
            3'b001: clean_wave = square_wave;
            3'b010: clean_wave = triangle_wave;
            3'b011: clean_wave = sawtooth_wave;
            3'b100: clean_wave = ecg_wave;
            default: clean_wave = 24'sd0;
        endcase
    end

    noise_mixer u_mixer (
        .wave_in      (clean_wave),
        .noise_in     (noise_wave),
        .noise_enable (noise_enable),
        .mixed_out    (mixed_wave)
    );

endmodule
