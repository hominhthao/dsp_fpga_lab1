`timescale 1ns/1ps

module tb_square_gen;
    reg clk;
    reg rst_n;
    reg sample_en;
    reg [31:0] phase_inc;
    reg [8:0] amp_q8;
    reg [8:0] duty_q8;
    wire signed [23:0] wave_out;

    integer pass_count;
    integer fail_count;
    integer i;
    integer sample_index;
    integer rise1;
    integer rise2;
    reg signed [23:0] prev;
    reg signed [23:0] hold_value;

    square_gen dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .phase_inc(phase_inc), .amp_q8(amp_q8), .duty_q8(duty_q8),
        .wave_out(wave_out)
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

    task check;
        input cond;
        input [8*110-1:0] name;
        begin
            if (cond) begin pass_count = pass_count + 1; $display("[PASS] %0s", name); end
            else begin fail_count = fail_count + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    //--- Khai bao cho phan ca bien ---
    localparam [31:0] INC_1KHZ  = 32'd89_478_485;
    localparam [31:0] INC_10KHZ = 32'd894_784_850;

    // Muc ly thuyet: (0x7FFFFF * amp) >>> 8
    function automatic signed [23:0] level_of;
        input [8:0] amp;
        reg signed [33:0] p;
        begin
            p = $signed(34'sd8388607) * $signed({25'd0, amp});
            level_of = p >>> 8;
        end
    endfunction

    // Ket qua do
    integer n_hi, n_lo, n_other, n_rise;
    integer run_len, run_min, run_max, n_runs;

    // Chay N mau, dem mau cao/thap, canh len, do rong xung cao (bo xung dau/cuoi)
    task automatic measure;
        input integer n;
        input signed [23:0] lvl;
        integer k;
        reg prev_hi, cur_hi, started;
        begin
            n_hi = 0; n_lo = 0; n_other = 0; n_rise = 0;
            run_len = 0; run_min = 1_000_000; run_max = 0; n_runs = 0;
            started = 1'b0;
            pulse_sample;
            prev_hi = (wave_out == lvl);
            for (k = 0; k < n; k = k + 1) begin
                pulse_sample;
                cur_hi = (wave_out == lvl);
                if (wave_out == lvl)       n_hi = n_hi + 1;
                else if (wave_out == -lvl) n_lo = n_lo + 1;
                else                       n_other = n_other + 1;

                if (cur_hi && !prev_hi) begin
                    n_rise = n_rise + 1;
                    started = 1'b1;
                    run_len = 1;
                end
                else if (cur_hi && started)
                    run_len = run_len + 1;
                else if (!cur_hi && prev_hi && started) begin
                    if (run_len < run_min) run_min = run_len;
                    if (run_len > run_max) run_max = run_len;
                    n_runs = n_runs + 1;
                end
                prev_hi = cur_hi;
            end
        end
    endtask

    task restart;
        begin
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask

    integer d;
    reg [8:0] duty_tab [0:2];
    integer   exp_hi   [0:2];
    integer   exp_run  [0:2];
    reg signed [23:0] lvl;
    reg signed [23:0] hold;

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0; sample_en = 0;
        phase_inc = 32'd89_478_485; // 1 kHz voi tan so lay mau 48 kHz
        amp_q8 = 9'd256;
        duty_q8 = 9'd128;
        repeat (4) @(posedge clk);
        check(wave_out === 24'sd0, "Reset dua ngo ra ve 0");
        rst_n = 1;

        pulse_sample;
        check(wave_out > 24'sd8_000_000, "Muc duong cua song vuong dat bien do 100%");

        hold_value = wave_out;
        repeat (20) @(posedge clk);
        check(wave_out === hold_value, "Ngo ra giu nguyen khi sample_en bang 0");

        // Do chu ky bang hai canh len lien tiep.
        prev = wave_out;
        rise1 = -1; rise2 = -1; sample_index = 0;
        for (i = 0; i < 140; i = i + 1) begin
            pulse_sample;
            sample_index = sample_index + 1;
            if ((prev < 0) && (wave_out > 0)) begin
                if (rise1 < 0) rise1 = sample_index;
                else if (rise2 < 0) rise2 = sample_index;
            end
            prev = wave_out;
        end
        check((rise1 > 0) && (rise2 > rise1), "Phat hien duoc hai canh len");
        check(((rise2-rise1) >= 47) && ((rise2-rise1) <= 49), "Chu ky 1 kHz xap xi 48 mau audio");

        // Kiem tra bien do 50%.
        amp_q8 = 9'd128;
        pulse_sample;
        check((wave_out <= 24'sd4_200_000) && (wave_out >= -24'sd4_200_000), "Bien do 50% xap xi mot nua bien do toi da");


        //=============================================================
        // CA BIEN (edge case) - bo sung
        //=============================================================
        $display("----- CA BIEN (edge case) -----");
        // Khoi tao cho phan ca bien (phan truoc da doi amp/duty)
        phase_inc = INC_1KHZ; amp_q8 = 9'd256; duty_q8 = 9'd128;
        duty_tab[0] = 9'd64;  exp_hi[0] = 120; exp_run[0] = 12;
        duty_tab[1] = 9'd128; exp_hi[1] = 240; exp_run[1] = 24;
        duty_tab[2] = 9'd192; exp_hi[2] = 360; exp_run[2] = 36;
        //-------------------------------------------------------------
        // 1. Duty 25/50/75% o 1 kHz, 480 mau = 10 chu ky
        //-------------------------------------------------------------
        lvl = level_of(9'd256);
        for (d = 0; d < 3; d = d + 1) begin
            duty_q8 = duty_tab[d];
            restart;
            measure(480, lvl);
            $display("[DO ] duty_q8=%0d: cao=%0d thap=%0d khac=%0d | canh len=%0d | do rong xung=%0d..%0d mau (ky vong %0d)",
                     duty_q8, n_hi, n_lo, n_other, n_rise, run_min, run_max, exp_run[d]);
            check((n_other == 0) && (n_hi >= exp_hi[d]-2) && (n_hi <= exp_hi[d]+2),
                  (d == 0) ? "Bien 1a: Duty 25% -> 25% so mau o muc cao" :
                  (d == 1) ? "Bien 1b: Duty 50% -> 50% so mau o muc cao" :
                             "Bien 1c: Duty 75% -> 75% so mau o muc cao");
            check((n_runs >= 8) && (run_min >= exp_run[d]-1) && (run_max <= exp_run[d]+1),
                  (d == 0) ? "Bien 2a: Do rong xung 25% = 12 mau (1 kHz)" :
                  (d == 1) ? "Bien 2b: Do rong xung 50% = 24 mau (1 kHz)" :
                             "Bien 2c: Do rong xung 75% = 36 mau (1 kHz)");
        end

        //-------------------------------------------------------------
        // 1b. Do phan giai duty: phase_inc = 2^24 -> moi mau tang 1 dia chi
        //     (256 mau/chu ky) -> do rong xung phai dung duty_q8 mau.
        //-------------------------------------------------------------
        phase_inc = 32'd16_777_216;
        duty_q8 = 9'd64; restart; measure(768, lvl);
        $display("[DO ] phase_inc=2^24, duty_q8=64: do rong xung=%0d..%0d mau (ky vong 64)", run_min, run_max);
        check((n_runs >= 2) && (run_min == 64) && (run_max == 64),
              "Bien 2d: Duty chinh xac tung mau: duty_q8=64 -> dung 64/256 mau");
        duty_q8 = 9'd192; restart; measure(768, lvl);
        check((n_runs >= 2) && (run_min == 192) && (run_max == 192),
              "Bien 2e: Duty chinh xac tung mau: duty_q8=192 -> dung 192/256 mau");
        phase_inc = INC_1KHZ;

        //-------------------------------------------------------------
        // 2. Duty 100% (256) va duty 0: khong co canh
        //-------------------------------------------------------------
        duty_q8 = 9'd256; restart; measure(480, lvl);
        check((n_hi == 480) && (n_rise == 0), "Bien 3: Duty 100% -> luon o muc cao (DC)");
        duty_q8 = 9'd0; restart; measure(480, lvl);
        check((n_lo == 480) && (n_rise == 0), "Bien 4: Duty 0 -> luon o muc thap");

        //-------------------------------------------------------------
        // 3. Muc bit-exact theo bien do
        //-------------------------------------------------------------
        duty_q8 = 9'd128;
        amp_q8 = 9'd256; restart; measure(96, level_of(9'd256));
        check((n_other == 0) && (n_hi > 0) && (n_lo > 0),
              "Bien 5: amp=256 -> muc +/-8388607 (full-scale) bit-exact");
        amp_q8 = 9'd255; restart; measure(96, level_of(9'd255));
        $display("[DO ] amp=255 -> muc ly thuyet = +/-%0d", level_of(9'd255));
        check((n_other == 0) && (n_hi > 0) && (n_lo > 0),
              "Bien 6: amp=255 -> muc +/-8355839 bit-exact");
        amp_q8 = 9'd128; restart; measure(96, level_of(9'd128));
        check((n_other == 0) && (n_hi > 0) && (n_lo > 0),
              "Bien 7: amp=128 -> muc +/-4194303 bit-exact");
        amp_q8 = 9'd0; restart; measure(96, 24'sd0);
        check(n_hi == 96, "Bien 8: amp=0 -> ngo ra = 0 moi mau");

        //-------------------------------------------------------------
        // 4. 10 kHz: 480 mau = 100 chu ky
        //-------------------------------------------------------------
        amp_q8 = 9'd256; phase_inc = INC_10KHZ;
        lvl = level_of(9'd256);
        duty_q8 = 9'd128; restart; measure(480, lvl);
        $display("[DO ] 10 kHz duty 50%%: cao=%0d/480 canh len=%0d (ky vong 240, 100)", n_hi, n_rise);
        check((n_other == 0) && (n_rise >= 99) && (n_rise <= 101),
              "Bien 9: 10 kHz -> 100 canh len trong 480 mau (4.8 mau/chu ky)");
        check((n_hi >= 230) && (n_hi <= 250),
              "Bien 10: 10 kHz duty 50% -> trung binh ~50% mau o muc cao");
        duty_q8 = 9'd64; restart; measure(480, lvl);
        $display("[DO ] 10 kHz duty 25%%: cao=%0d/480 (ky vong ~120)", n_hi);
        check((n_hi >= 110) && (n_hi <= 130),
              "Bien 11: 10 kHz duty 25% -> trung binh ~25% mau o muc cao");
        $display("[INFO] 10 kHz chi co 4.8 mau/chu ky: do rong xung bi luong tu hoa (1 hoac 2 mau).");

        //-------------------------------------------------------------
        // 5. Doi tham so giua chung
        //-------------------------------------------------------------
        phase_inc = INC_1KHZ; duty_q8 = 9'd256; amp_q8 = 9'd256; restart;
        pulse_sample; pulse_sample;
        amp_q8 = 9'd128; pulse_sample;
        check(wave_out == level_of(9'd128), "Bien 12: Doi bien do -> ap dung ngay mau ke tiep");
        duty_q8 = 9'd0; pulse_sample;
        check(wave_out == -level_of(9'd128), "Bien 13: Doi duty -> ap dung ngay mau ke tiep");

        hold = wave_out;
        repeat (30) @(posedge clk);
        check(wave_out === hold, "Bien 14: Khong co sample_en -> ngo ra giu nguyen");


        $display("TONG KET SQUARE: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_square_gen FAIL");
    end
endmodule
