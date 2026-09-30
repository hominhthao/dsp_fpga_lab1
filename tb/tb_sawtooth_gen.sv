`timescale 1ns/1ps

module tb_sawtooth_gen;
    reg clk;
    reg rst_n;
    reg sample_en;
    reg [31:0] phase_inc;
    reg [8:0] amp_q8;
    wire signed [23:0] wave_out;
    integer pass_count, fail_count, i, wraps;
    reg signed [23:0] prev;
    reg signed [23:0] hold_value;

    sawtooth_gen dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .phase_inc(phase_inc), .amp_q8(amp_q8), .wave_out(wave_out)
    );

    initial clk=0;
    always #10 clk=~clk;

    task pulse_sample;
        begin
            @(negedge clk); sample_en=1;
            @(negedge clk); sample_en=0;
            #1;
        end
    endtask

    task check;
        input cond; input [8*110-1:0] name;
        begin
            if(cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s",name); end
        end
    endtask

    //--- Khai bao cho phan ca bien ---
    localparam [31:0] INC_1KHZ  = 32'd89_478_485;
    localparam [31:0] INC_10KHZ = 32'd894_784_850;
    localparam integer FS       = 8_388_607;

    task restart;
        begin
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            pulse_sample;   // mau dau = gia tri tai pha 0
        end
    endtask

    integer s_min, s_max, s_drops, s_step_ok;
    real    s_mean;
    reg signed [23:0] hs;

    // Do N mau: min/max, so buoc tang deu, so lan roi, trung binh
    task automatic measure_saw;
        input integer n;
        input integer step_lo, step_hi;
        integer k, ds, prev_s;
        real sum_s;
        begin
            s_min = FS; s_max = -FS-1; s_drops = 0; s_step_ok = 0;
            sum_s = 0.0; prev_s = wave_out;
            for (k = 0; k < n; k = k + 1) begin
                pulse_sample;
                ds = wave_out - prev_s;
                if (wave_out < s_min) s_min = wave_out;
                if (wave_out > s_max) s_max = wave_out;
                if (ds >= step_lo && ds <= step_hi) s_step_ok = s_step_ok + 1;
                if (ds < 0) s_drops = s_drops + 1;
                sum_s = sum_s + wave_out;
                prev_s = wave_out;
            end
            s_mean = sum_s / n;
        end
    endtask

    initial begin
        pass_count=0; fail_count=0; rst_n=0; sample_en=0;
        phase_inc=32'd89_478_485; amp_q8=9'd256;
        repeat(4) @(posedge clk); rst_n=1;
        pulse_sample;
        hold_value=wave_out;
        repeat(20) @(posedge clk);
        check(wave_out===hold_value,"Song rang cua giu nguyen giua hai sample_tick");

        prev=wave_out; wraps=0;
        for(i=0;i<120;i=i+1) begin
            pulse_sample;
            if(wave_out < prev) wraps=wraps+1;
            prev=wave_out;
        end
        check((wraps>=2)&&(wraps<=3),"Song rang cua 1 kHz wrap dung trong 120 mau");

        //=============================================================
        // CA BIEN (edge case) - bo sung
        //=============================================================
        $display("----- CA BIEN (edge case) -----");
        // Quy uoc pha
        phase_inc = INC_1KHZ; amp_q8 = 9'd256; restart;
        $display("[DO ] Pha 0: SAW=%0d (ky vong -8388608)", wave_out);
        check(wave_out == -FS - 1, "Bien 0: Tai pha 0, song rang cua bat dau tu day (-full-scale)");

        // 1 kHz, 100%: buoc ly thuyet = 89478485/2^8 = 349525.3
        restart;
        measure_saw(480, 349_524, 349_527);
        $display("[DO ] SAW 1 kHz: min=%0d max=%0d | buoc deu=%0d/480 | lan roi=%0d | trung binh=%0.0f",
                 s_min, s_max, s_step_ok, s_drops, s_mean);
        check((s_max >= FS - 349_527) && (s_min <= -FS + 349_527),
              "Bien 1: Dat gan +/-full-scale (sai khac < 1 buoc)");
        check(s_step_ok >= 468,
              "Bien 2: Tang deu: moi buoc = phase_inc/2^8 (tru luc roi)");
        check((s_drops >= 9) && (s_drops <= 10),
              "Bien 3: Roi dung 1 lan moi chu ky (10 lan / 480 mau)");
        // Rang cua lay mau N diem/chu ky luon lech DC dung nua buoc: 349525/2 = 174763
        check((s_mean <= 174_764.0) && (s_mean >= -174_764.0),
              "Bien 4: Trung binh <= nua buoc (lech DC do lay mau, ~2% FS)");
        $display("[INFO] SAW lech DC %0.0f = nua buoc lay mau; ngo ra ghep AC nen khong anh huong.", s_mean);

        // Bien do 50%
        amp_q8 = 9'd128; restart;
        measure_saw(480, 174_762, 174_764);
        $display("[DO ] amp=128: SAW %0d..%0d", s_min, s_max);
        check((s_max <= FS/2 + 1) && (s_max >= FS/2 - 174_764) &&
              (s_min >= -FS/2 - 1) && (s_min <= -FS/2 + 174_764) && (s_step_ok >= 468),
              "Bien 5: amp=128 -> dinh ~ +/-50% FS, buoc giam mot nua, van deu");

        // Bien do 0
        amp_q8 = 9'd0; restart;
        measure_saw(96, 0, 0);
        check((s_min == 0) && (s_max == 0), "Bien 6: amp=0 -> ngo ra = 0 moi mau");

        // 10 kHz
        amp_q8 = 9'd256; phase_inc = INC_10KHZ; restart;
        measure_saw(480, 3_495_252, 3_495_254);
        $display("[DO ] 10 kHz: lan roi=%0d", s_drops);
        check((s_drops >= 99) && (s_drops <= 101), "Bien 7: 10 kHz -> 100 lan roi / 480 mau");

        // phase_inc = 0
        phase_inc = 32'd0; restart;
        hs = wave_out;
        measure_saw(48, 0, 0);
        check((s_min == hs) && (s_max == hs), "Bien 8: phase_inc=0 -> song dung yen");

        $display("TONG KET SAWTOOTH: PASS=%0d FAIL=%0d",pass_count,fail_count);
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_sawtooth_gen FAIL");
    end
endmodule
