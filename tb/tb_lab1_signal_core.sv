`timescale 1ns/1ps

module tb_lab1_signal_core;

    localparam integer SIM_DEBOUNCE = 4;
    localparam [31:0] WAVE_1KHZ = 32'd89_478_485;
    localparam [31:0] WAVE_2KHZ = 32'd178_956_970;
    localparam [31:0] ECG_60BPM = 32'd89_478;
    localparam [31:0] ECG_75BPM = 32'd111_848;

    reg clk;
    reg rst_n;
    reg sample_en;
    reg [2:0] wave_sel;
    reg ctrl_mode;
    reg key_down;
    reg key_up;
    reg [1:0] duty_sel;
    reg noise_enable;
    reg [8:0] noise_amp_q8;
    reg [15:0] noise_update_div_samples;

    wire signed [23:0] clean_wave;
    wire signed [23:0] mixed_wave;
    wire signed [23:0] sine_wave;
    wire signed [23:0] square_wave;
    wire signed [23:0] triangle_wave;
    wire signed [23:0] sawtooth_wave;
    wire signed [23:0] ecg_wave;
    wire signed [23:0] noise_wave;

    integer pass_count;
    integer fail_count;
    integer i;
    integer diff_count;
    reg signed [23:0] hold_sine;
    reg signed [23:0] hold_square;
    reg signed [23:0] hold_triangle;
    reg signed [23:0] hold_saw;
    reg signed [23:0] hold_noise;

    lab1_signal_core #(
        .DEBOUNCE_CNT(SIM_DEBOUNCE)
    ) dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .wave_sel(wave_sel), .ctrl_mode(ctrl_mode),
        .key_down(key_down), .key_up(key_up),
        .duty_sel(duty_sel), .noise_enable(noise_enable),
        .noise_amp_q8(noise_amp_q8),
        .noise_update_div_samples(noise_update_div_samples),
        .clean_wave(clean_wave), .mixed_wave(mixed_wave),
        .sine_wave(sine_wave), .square_wave(square_wave),
        .triangle_wave(triangle_wave), .sawtooth_wave(sawtooth_wave),
        .ecg_wave(ecg_wave), .noise_wave(noise_wave)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    task pulse_sample;
        begin
            @(negedge clk); sample_en = 1'b1;
            @(negedge clk); sample_en = 1'b0;
            #1;
        end
    endtask

    task press_up;
        begin
            key_up = 1'b0;
            repeat (SIM_DEBOUNCE + 8) @(negedge clk);
            key_up = 1'b1;
            repeat (SIM_DEBOUNCE + 8) @(negedge clk);
        end
    endtask

    task press_down;
        begin
            key_down = 1'b0;
            repeat (SIM_DEBOUNCE + 8) @(negedge clk);
            key_down = 1'b1;
            repeat (SIM_DEBOUNCE + 8) @(negedge clk);
        end
    endtask

    task check;
        input cond;
        input [8*100-1:0] name;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", name);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        sample_en = 0;
        wave_sel = 3'b000;
        ctrl_mode = 1'b0;
        key_down = 1'b1;
        key_up = 1'b1;
        duty_sel = 2'b01;
        noise_enable = 0;
        noise_amp_q8 = 9'd32;
        noise_update_div_samples = 16'd1;

        repeat (5) @(posedge clk);
        check((sine_wave===0)&&(square_wave===0)&&(triangle_wave===0)&&(sawtooth_wave===0)&&(ecg_wave===0)&&(noise_wave===0),
              "Reset dua tat ca ngo ra waveform ve 0");
        rst_n = 1;
        repeat (4) @(posedge clk);

        check(dut.wave_phase_inc===WAVE_1KHZ,
              "Tan so song thuong mac dinh la 1 kHz");
        check(dut.ecg_phase_inc===ECG_60BPM,
              "ECG mac dinh la 60 BPM");
        check((dut.wave_amp_ctrl===8'd128)&&(dut.ecg_amp_ctrl===8'd128),
              "Bien do TV1 mac dinh la 128");

        // Frequency mode, Square dang duoc chon: KEY2 tang tan so song thuong.
        wave_sel = 3'b001;
        ctrl_mode = 1'b0;
        press_up;
        check(dut.wave_phase_inc===WAVE_2KHZ,
              "KEY UP tang tan so song thuong tu 1 kHz len 2 kHz");
        check(dut.ecg_phase_inc===ECG_60BPM,
              "Tang tan so song thuong khong lam doi BPM ECG");

        // Frequency mode, ECG dang duoc chon: KEY2 tang BPM, khong doi tan so song thuong.
        wave_sel = 3'b100;
        press_up;
        check(dut.ecg_phase_inc===ECG_75BPM,
              "KEY UP tang ECG tu 60 BPM len 75 BPM");
        check(dut.wave_phase_inc===WAVE_2KHZ,
              "Tang BPM ECG khong lam doi tan so song thuong");

        // Amplitude mode: KEY1/KEY2 tac dong dong thoi len TV1 Sine va ECG.
        ctrl_mode = 1'b1;
        press_up;
        check((dut.wave_amp_ctrl===8'd144)&&(dut.ecg_amp_ctrl===8'd144),
              "KEY UP tang bien do chung them 16");
        press_down;
        check((dut.wave_amp_ctrl===8'd128)&&(dut.ecg_amp_ctrl===8'd128),
              "KEY DOWN giam bien do chung ve 128");

        // Mot sample_tick chung cap nhat tat ca bo tao song.
        pulse_sample;
        hold_sine = sine_wave;
        hold_square = square_wave;
        hold_triangle = triangle_wave;
        hold_saw = sawtooth_wave;
        hold_noise = noise_wave;

        repeat (25) @(posedge clk);
        check(sine_wave===hold_sine,"Sine giu nguyen giua hai sample_tick");
        check(square_wave===hold_square,"Square giu nguyen giua hai sample_tick");
        check(triangle_wave===hold_triangle,"Triangle giu nguyen giua hai sample_tick");
        check(sawtooth_wave===hold_saw,"Sawtooth giu nguyen giua hai sample_tick");
        check(noise_wave===hold_noise,"Noise giu nguyen giua hai sample_tick");

        // Kiem tra bo chon waveform.
        wave_sel = 3'b001; #1;
        check(clean_wave===square_wave,"MUX chon dung Square");
        wave_sel = 3'b010; #1;
        check(clean_wave===triangle_wave,"MUX chon dung Triangle");
        wave_sel = 3'b011; #1;
        check(clean_wave===sawtooth_wave,"MUX chon dung Sawtooth");
        wave_sel = 3'b000; #1;
        check(clean_wave===sine_wave,"MUX chon dung Sine");
        wave_sel = 3'b100; #1;
        check(clean_wave===ecg_wave,"MUX chon dung ECG");

        // Kiem tra anh xa SW[9:8] -> duty song vuong.
        duty_sel = 2'b00; #1;
        check(dut.duty_q8==9'd64,  "duty_sel=00 -> duty 25% (64/256)");
        duty_sel = 2'b01; #1;
        check(dut.duty_q8==9'd128, "duty_sel=01 -> duty 50% (128/256)");
        duty_sel = 2'b10; #1;
        check(dut.duty_q8==9'd192, "duty_sel=10 -> duty 75% (192/256)");
        duty_sel = 2'b11; #1;
        check(dut.duty_q8==9'd230, "duty_sel=11 -> duty 90% (230/256), khong con 100% (DC)");
        duty_sel = 2'b01; #1;

        // Kiem tra tat va chen noise.
        wave_sel = 3'b001;
        noise_enable = 0; #1;
        check(mixed_wave===clean_wave,"Tat noise thi mixed_wave bang clean_wave");

        noise_enable = 1;
        diff_count = 0;
        for (i=0; i<16; i=i+1) begin
            pulse_sample;
            #1;
            if (mixed_wave !== clean_wave)
                diff_count = diff_count + 1;
        end
        check(diff_count>0,"Bat noise lam mixed_wave thay doi");

        noise_amp_q8 = 9'd0;
        pulse_sample; #1;
        check(mixed_wave===clean_wave,"Bien do noise bang 0 thi tra ve waveform goc");

        $display("TONG KET SIGNAL CORE: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_lab1_signal_core FAIL");
    end

endmodule
