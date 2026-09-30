module lab1_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,

    output wire        AUD_XCK,
    output wire        AUD_BCLK,
    output wire        AUD_DACLRCK,
    output wire        AUD_DACDAT,

    output wire        FPGA_I2C_SCLK,
    inout  wire        FPGA_I2C_SDAT
);

    wire rst_n;
    wire clk_audio;
    wire pll_locked;
    wire pll_locked_sys;
    wire codec_done;
    wire codec_error;
    wire system_ready;

    wire sample_req_toggle;
    wire sample_tick;

    wire [9:0] sw_sync;

    wire signed [23:0] clean_wave;
    wire signed [23:0] mixed_wave;
    wire signed [23:0] sine_wave;
    wire signed [23:0] square_wave;
    wire signed [23:0] triangle_wave;
    wire signed [23:0] sawtooth_wave;
    wire signed [23:0] ecg_wave;
    wire signed [23:0] noise_wave;

    reg signed [23:0] audio_sample_hold;
    reg capture_pending;

    reg [8:0] noise_amp_q8;
    reg [15:0] noise_update_div_samples;

    wire key_noise_rate;
    wire unused_debounced_3;
    wire unused_rise_3;

    // KEY[0] la reset active-low.
    assign rst_n = KEY[0];

    audio_pll u_audio_pll (
        .refclk      (CLOCK_50),
        .rst         (~rst_n),
        .clk_12m288  (clk_audio),
        .locked      (pll_locked)
    );

    assign AUD_XCK = clk_audio;

    // Dong bo tin hieu PLL lock vao mien CLOCK_50.
    sync_bus_2ff #(
        .WIDTH       (1),
        .RESET_VALUE (1'b0)
    ) u_pll_lock_sync (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .async_in (pll_locked),
        .sync_out (pll_locked_sys)
    );

    wm8731_config u_codec_cfg (
        .clk          (CLOCK_50),
        .rst_n        (rst_n & pll_locked_sys),
        .i2c_scl      (FPGA_I2C_SCLK),
        .i2c_sda      (FPGA_I2C_SDAT),
        .config_done  (codec_done),
        .config_error (codec_error)
    );

    assign system_ready = rst_n & pll_locked_sys & codec_done & ~codec_error;

    wm8731_i2s_tx u_i2s (
        .clk_audio         (clk_audio),
        .rst_n             (rst_n & pll_locked),
        .sample_async      (audio_sample_hold),
        .aud_bclk          (AUD_BCLK),
        .aud_daclrck       (AUD_DACLRCK),
        .aud_dacdat        (AUD_DACDAT),
        .sample_req_toggle (sample_req_toggle)
    );

    // Chuyen toggle tu mien clock audio thanh xung mot chu ky CLOCK_50.
    // sample_tick la moc cap nhat chung cho cac waveform va noise.
    toggle_sync_pulse u_sample_sync (
        .clk          (CLOCK_50),
        .rst_n        (rst_n & pll_locked_sys),
        .toggle_async (sample_req_toggle),
        .pulse_out    (sample_tick)
    );

    // Dong bo cac switch vao CLOCK_50 de giam nguy co metastability.
    sync_bus_2ff #(
        .WIDTH       (10),
        .RESET_VALUE (10'd0)
    ) u_sw_sync (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .async_in (SW),
        .sync_out (sw_sync)
    );

    // SW[6:5] chon bien do noise: 0%, 12.5%, 25% hoac 50%.
    always @(*) begin
        case (sw_sync[6:5])
            2'b00: noise_amp_q8 = 9'd0;
            2'b01: noise_amp_q8 = 9'd32;
            2'b10: noise_amp_q8 = 9'd64;
            default: noise_amp_q8 = 9'd128;
        endcase
    end

    // KEY[3] doi toc do cap nhat noise. KEY active-low.
    debounce #(
        .STABLE_CYCLES (1_000_000),
        .INITIAL_STATE (1'b1)
    ) u_key_noise_rate (
        .clk           (CLOCK_50),
        .rst_n         (rst_n),
        .noisy_in      (KEY[3]),
        .debounced_out (unused_debounced_3),
        .rise_pulse    (unused_rise_3),
        .fall_pulse    (key_noise_rate)
    );

    // Moi lan bam KEY[3]: 1 -> 2 -> 4 -> 8 -> 1 mau audio.
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n)
            noise_update_div_samples <= 16'd1;
        else if (key_noise_rate) begin
            case (noise_update_div_samples)
                16'd1: noise_update_div_samples <= 16'd2;
                16'd2: noise_update_div_samples <= 16'd4;
                16'd4: noise_update_div_samples <= 16'd8;
                default: noise_update_div_samples <= 16'd1;
            endcase
        end
    end

    // SW[4]=0: KEY[1]/KEY[2] dieu khien Frequency/BPM DOWN/UP.
    // SW[4]=1: KEY[1]/KEY[2] dieu khien Amplitude DOWN/UP.
    lab1_signal_core u_signal_core (
        .clk                      (CLOCK_50),
        .rst_n                    (system_ready),
        .sample_en                (sample_tick),
        .wave_sel                 (sw_sync[2:0]),
        .ctrl_mode                (sw_sync[4]),
        .key_down                 (KEY[1]),
        .key_up                   (KEY[2]),
        .duty_sel                 (sw_sync[9:8]),
        .noise_enable             (sw_sync[3]),
        .noise_amp_q8             (noise_amp_q8),
        .noise_update_div_samples (noise_update_div_samples),
        .clean_wave               (clean_wave),
        .mixed_wave               (mixed_wave),
        .sine_wave                (sine_wave),
        .square_wave              (square_wave),
        .triangle_wave            (triangle_wave),
        .sawtooth_wave            (sawtooth_wave),
        .ecg_wave                 (ecg_wave),
        .noise_wave               (noise_wave)
    );

    // Cac generator cap nhat ngo ra tai sample_tick.
    // Cho mixed_wave on dinh them mot chu ky CLOCK_50 truoc khi chot.
    // Mau audio duoc giu on dinh cho den khi CODEC yeu cau mau moi.
    always @(posedge CLOCK_50 or negedge system_ready) begin
        if (!system_ready) begin
            audio_sample_hold <= 24'sd0;
            capture_pending   <= 1'b0;
        end
        else begin
            if (sample_tick)
                capture_pending <= 1'b1;

            if (capture_pending) begin
                audio_sample_hold <= mixed_wave;
                capture_pending   <= 1'b0;
            end
        end
    end

    // LED hien thi control dang chon va trang thai CODEC/PLL.
    assign LEDR[2:0] = sw_sync[2:0];
    assign LEDR[3]   = sw_sync[3];
    assign LEDR[4]   = sw_sync[4];
    assign LEDR[6:5] = sw_sync[6:5];
    assign LEDR[7]   = sw_sync[7];
    assign LEDR[8]   = codec_done & ~codec_error;
    assign LEDR[9]   = pll_locked_sys;

endmodule
