`timescale 1ns/1ps

module tb_triangle_gen;
    reg clk;
    reg rst_n;
    reg sample_en;
    reg [31:0] phase_inc;
    reg [8:0] amp_q8;
    wire signed [23:0] wave_out;
    integer pass_count, fail_count, i;
    reg signed [23:0] hold_value;
    reg signed [23:0] min_v, max_v;

    triangle_gen dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .phase_inc(phase_inc), .amp_q8(amp_q8), .wave_out(wave_out)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task pulse_sample;
        begin
            @(negedge clk); sample_en = 1;
            @(negedge clk); sample_en = 0;
            #1;
        end
    endtask

    task check;
        input cond; input [8*110-1:0] name;
        begin
            if (cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
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

    integer t_min, t_max, t_turns, t_step_ok, t_zc;
    real    t_mean;
    reg signed [23:0] ht;

    // Do N mau: min/max, so buoc dung do doc, so lan doi chieu, qua 0, trung binh
    task automatic measure_tri;
        input integer n;
        input integer step_lo, step_hi;
        integer k, dt, prev_t, prev_dir, dir;
        real sum_t;
        begin
            t_min = FS; t_max = -FS-1; t_turns = 0; t_step_ok = 0; t_zc = 0;
            sum_t = 0.0; prev_dir = 0; prev_t = wave_out;
            for (k = 0; k < n; k = k + 1) begin
                pulse_sample;
                dt = wave_out - prev_t;
                if (wave_out < t_min) t_min = wave_out;
                if (wave_out > t_max) t_max = wave_out;
                if ((dt >= step_lo && dt <= step_hi) || (-dt >= step_lo && -dt <= step_hi))
                    t_step_ok = t_step_ok + 1;
                dir = (dt > 0) ? 1 : (dt < 0) ? -1 : 0;
                if (dir != 0 && prev_dir != 0 && dir != prev_dir) t_turns = t_turns + 1;
                if (dir != 0) prev_dir = dir;
                if (prev_t < 0 && wave_out >= 0) t_zc = t_zc + 1;
                sum_t = sum_t + wave_out;
                prev_t = wave_out;
            end
            t_mean = sum_t / n;
        end
    endtask

    initial begin
        pass_count=0; fail_count=0; rst_n=0; sample_en=0;
        phase_inc=32'd89_478_485; amp_q8=9'd256;
        repeat(4) @(posedge clk); rst_n=1;
        pulse_sample;
        hold_value=wave_out;
        repeat(20) @(posedge clk);
        check(wave_out===hold_value,"Song tam giac giu nguyen giua hai sample_tick");

        min_v=24'sh7FFFFF; max_v=24'sh800000;
        for(i=0;i<96;i=i+1) begin
            pulse_sample;
            if(wave_out<min_v) min_v=wave_out;
            if(wave_out>max_v) max_v=wave_out;
        end
        check(min_v < -24'sd7_500_000,"Song tam giac dat vung bien do am gan toi da");
        check(max_v >  24'sd7_500_000,"Song tam giac dat vung bien do duong gan toi da");

        amp_q8=9'd128;
        min_v=24'sh7FFFFF; max_v=24'sh800000;
        for(i=0;i<48;i=i+1) begin
            pulse_sample;
            if(wave_out<min_v) min_v=wave_out;
            if(wave_out>max_v) max_v=wave_out;
        end
        check((min_v > -24'sd4_300_000) && (max_v < 24'sd4_300_000),"Song tam giac co bien do 50% dung");

        //=============================================================
        // CA BIEN (edge case) - bo sung
        //=============================================================
        $display("----- CA BIEN (edge case) -----");
        // Quy uoc pha
        phase_inc = INC_1KHZ; amp_q8 = 9'd256; restart;
        $display("[DO ] Pha 0: TRI=%0d (ky vong -8388608)", wave_out);
        check(wave_out == -FS - 1, "Bien 0: Tai pha 0, song tam giac bat dau tu day (-full-scale)");

        // 1 kHz, 100%: 480 mau = 10 chu ky; buoc ly thuyet = 89478485/2^7 = 699050.7
        restart;
        measure_tri(480, 699_049, 699_052);
        $display("[DO ] TRI 1 kHz: min=%0d max=%0d | buoc deu=%0d/480 | doi chieu=%0d | qua 0 len=%0d | trung binh=%0.0f",
                 t_min, t_max, t_step_ok, t_turns, t_zc, t_mean);
        check((t_max >= FS - 699_052) && (t_min <= -FS + 699_052),
              "Bien 1: Dat gan +/-full-scale (sai khac < 1 buoc)");
        check(t_step_ok >= 440,
              "Bien 2: Do doc deu: >= 92% buoc = phase_inc/2^7 (chi lech o dinh/day)");
        check((t_turns >= 19) && (t_turns <= 21),
              "Bien 3: Doi chieu 2 lan moi chu ky (20 lan / 10 chu ky)");
        check((t_zc >= 9) && (t_zc <= 11),
              "Bien 4: Chu ky 48 mau (10 lan qua 0 di len / 480 mau)");
        check((t_mean < 0.01*FS) && (t_mean > -0.01*FS),
              "Bien 5: Doi xung, trung binh ~ 0 (< 1% full-scale)");

        // Bien do 50%
        amp_q8 = 9'd128; restart;
        measure_tri(480, 349_524, 349_526);
        $display("[DO ] amp=128: TRI %0d..%0d", t_min, t_max);
        check((t_max <= FS/2 + 1) && (t_max >= FS/2 - 349_526) &&
              (t_min >= -FS/2 - 1) && (t_min <= -FS/2 + 349_526) && (t_step_ok >= 440),
              "Bien 6: amp=128 -> dinh ~ +/-50% FS, buoc giam mot nua, van deu");

        // Bien do 0
        amp_q8 = 9'd0; restart;
        measure_tri(96, 0, 0);
        check((t_min == 0) && (t_max == 0), "Bien 7: amp=0 -> ngo ra = 0 moi mau");

        // 10 kHz: 480 mau = 100 chu ky
        amp_q8 = 9'd256; phase_inc = INC_10KHZ; restart;
        measure_tri(480, 6_990_506, 6_990_508);
        $display("[DO ] 10 kHz: doi chieu=%0d, max=%0d", t_turns, t_max);
        check((t_turns >= 190) && (t_turns <= 210), "Bien 8: 10 kHz -> ~200 lan doi chieu / 480 mau");
        $display("[INFO] 10 kHz chi co 4.8 mau/chu ky nen dinh khong phai chu ky nao cung trung mau.");

        // phase_inc = 0
        phase_inc = 32'd0; restart;
        ht = wave_out;
        measure_tri(48, 0, 0);
        check((t_min == ht) && (t_max == ht), "Bien 9: phase_inc=0 -> song dung yen");

        $display("TONG KET TRIANGLE: PASS=%0d FAIL=%0d",pass_count,fail_count);
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_triangle_gen FAIL");
    end
endmodule
