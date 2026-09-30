`timescale 1ns/1ps

module tb_lfsr_noise;
    reg clk;
    reg rst_n;
    reg sample_en;
    reg [15:0] update_div_samples;
    reg [8:0] noise_amp_q8;
    wire signed [23:0] noise_out;
    integer pass_count, fail_count;
    reg signed [23:0] a,b,c,d,e,hold_value;

    lfsr_noise dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .update_div_samples(update_div_samples),
        .noise_amp_q8(noise_amp_q8), .noise_out(noise_out)
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
    localparam [23:0] SEED = 24'h5A_C3_E7;
    localparam integer FS  = 8_388_607;


    task restart;
        begin
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask

    // Mo hinh LFSR doc lap (Fibonacci, dich trai, bit moi vao LSB)
    // RTL dich 24 buoc moi lan cap nhat (leap-forward) -> mo hinh cung vay.
    localparam integer LEAP_STEPS = 24;

    function automatic [23:0] lfsr_next;
        input [23:0] s;
        begin
            lfsr_next = {s[22:0], s[23] ^ s[22] ^ s[21] ^ s[16]};
        end
    endfunction

    function automatic signed [23:0] scale;
        input [23:0] s;
        input [8:0]  amp;
        reg signed [33:0] p;
        begin
            p = $signed(s) * $signed({1'b0, amp});
            scale = p >>> 8;
        end
    endfunction

    // Theo doi LFSR khong ve 0
    integer n_zero_state;
    always @(posedge clk)
        if (rst_n && dut.lfsr_state == 24'd0)
            n_zero_state = n_zero_state + 1;

    integer i, k, n_mis, n_err, bound, max_abs, run, run_min, run_max, n_runs, n_change;
    integer ai;
    reg [23:0] ref_s;
    reg signed [23:0] prev;
    real sum, sum_xy, sum_xx, mean, r1;
    reg [8:0] amp_tab [0:2];
    reg [15:0] div_tab [0:3];

    // Do do dai cac doan gia tri khong doi (bo doan dau va cuoi)
    task automatic measure_runs;
        input integer n;
        integer k;
        reg started;
        begin
            run_min = 1_000_000; run_max = 0; n_runs = 0; n_change = 0;
            started = 1'b0; run = 0;
            pulse_sample; prev = noise_out;
            for (k = 0; k < n; k = k + 1) begin
                pulse_sample;
                if (noise_out != prev) begin
                    n_change = n_change + 1;
                    if (started) begin
                        if (run < run_min) run_min = run;
                        if (run > run_max) run_max = run;
                        n_runs = n_runs + 1;
                    end
                    started = 1'b1;
                    run = 1;
                end
                else
                    run = run + 1;
                prev = noise_out;
            end
        end
    endtask

    initial begin
        pass_count=0; fail_count=0; rst_n=0; sample_en=0;
        update_div_samples=16'd4; noise_amp_q8=9'd64;
        repeat(4) @(posedge clk); rst_n=1;

        pulse_sample; a=noise_out;
        hold_value=noise_out;
        repeat(20) @(posedge clk);
        check(noise_out===hold_value,"Noise giu nguyen khi sample_en bang 0");

        pulse_sample; b=noise_out;
        pulse_sample; c=noise_out;
        pulse_sample; d=noise_out;
        pulse_sample; e=noise_out;
        check((a===b)&&(b===c)&&(c===d),"Noise giu nguyen trong 4 mau theo update_div_samples");
        check(e!==d,"Noise thay doi sau 4 khoang mau audio");

        noise_amp_q8=9'd0;
        pulse_sample;
        check(noise_out===24'sd0,"Bien do noise bang 0 thi ngo ra bang 0");

        //=============================================================
        // CA BIEN (edge case) - bo sung
        //=============================================================
        $display("----- CA BIEN (edge case) -----");
        // Khoi tao cho phan ca bien (phan truoc da doi amp/div)
        n_zero_state = 0;
        update_div_samples = 16'd1; noise_amp_q8 = 9'd256;
        amp_tab[0] = 9'd32; amp_tab[1] = 9'd64; amp_tab[2] = 9'd128;
        div_tab[0] = 16'd1; div_tab[1] = 16'd2; div_tab[2] = 16'd4; div_tab[3] = 16'd8;
        //-------------------------------------------------------------
        // 1. Bit-exact voi mo hinh doc lap (amp = 256 va 128)
        //-------------------------------------------------------------
        restart;
        ref_s = SEED; n_mis = 0;
        for (i = 0; i < 4000; i = i + 1) begin
            pulse_sample;
            if (noise_out !== scale(ref_s, 9'd256)) n_mis = n_mis + 1;
            for (k = 0; k < LEAP_STEPS; k = k + 1) ref_s = lfsr_next(ref_s);
        end
        $display("[DO ] 4000 mau, amp=256: sai khac voi mo hinh = %0d", n_mis);
        check(n_mis == 0, "Bien 1: Bit-exact voi mo hinh LFSR x^24+x^23+x^22+x^17+1, 24 buoc/mau");

        noise_amp_q8 = 9'd128; restart;
        ref_s = SEED; n_mis = 0;
        for (i = 0; i < 1000; i = i + 1) begin
            pulse_sample;
            if (noise_out !== scale(ref_s, 9'd128)) n_mis = n_mis + 1;
            for (k = 0; k < LEAP_STEPS; k = k + 1) ref_s = lfsr_next(ref_s);
        end
        check(n_mis == 0, "Bien 2: Bit-exact sau khi nhan bien do amp=128");

        //-------------------------------------------------------------
        // 2. Gioi han bien do va trung binh
        //-------------------------------------------------------------
        for (ai = 0; ai < 3; ai = ai + 1) begin
            noise_amp_q8 = amp_tab[ai]; restart;
            bound = (FS * amp_tab[ai]) / 256 + 1;
            max_abs = 0; n_err = 0; sum = 0.0;
            for (i = 0; i < 4000; i = i + 1) begin
                pulse_sample;
                if (noise_out > bound || noise_out < -bound - 1) n_err = n_err + 1;
                if (noise_out > max_abs)  max_abs = noise_out;
                if (-noise_out > max_abs) max_abs = -noise_out;
                sum = sum + noise_out;
            end
            mean = sum / 4000.0;
            $display("[DO ] amp_q8=%0d: gioi han=+/-%0d | |max|=%0d (%0d%%) | vuot=%0d | trung binh=%0.0f (%0.2f%% gioi han)",
                     amp_tab[ai], bound, max_abs, (max_abs * 100) / bound, n_err, mean, 100.0 * mean / bound);
            check((n_err == 0) && (max_abs >= (bound * 9) / 10),
                  (ai == 0) ? "Bien 3a: Nhieu 12.5% nam trong +/-12.5% FS va dung het dai" :
                  (ai == 1) ? "Bien 3b: Nhieu 25% nam trong +/-25% FS va dung het dai" :
                             "Bien 3c: Nhieu 50% nam trong +/-50% FS va dung het dai");
            check((mean < 0.05 * bound) && (mean > -0.05 * bound),
                  (ai == 0) ? "Bien 4a: Trung binh nhieu ~ 0 (amp 12.5%)" :
                  (ai == 1) ? "Bien 4b: Trung binh nhieu ~ 0 (amp 25%)" :
                             "Bien 4c: Trung binh nhieu ~ 0 (amp 50%)");
        end

        //-------------------------------------------------------------
        // 3. Toc do cap nhat 1/2/4/8 mau
        //-------------------------------------------------------------
        noise_amp_q8 = 9'd128;
        for (ai = 0; ai < 4; ai = ai + 1) begin
            update_div_samples = div_tab[ai]; restart;
            measure_runs(400);
            $display("[DO ] div=%0d: do dai doan giu = %0d..%0d mau (%0d doan)",
                     div_tab[ai], run_min, run_max, n_runs);
            check((n_runs > 0) && (run_min == div_tab[ai]) && (run_max == div_tab[ai]),
                  (ai == 0) ? "Bien 5a: div=1 -> doi gia tri moi mau (noise ~ 24 kHz)" :
                  (ai == 1) ? "Bien 5b: div=2 -> giu dung 2 mau (~12 kHz)" :
                  (ai == 2) ? "Bien 5c: div=4 -> giu dung 4 mau (~6 kHz)" :
                             "Bien 5d: div=8 -> giu dung 8 mau (~3 kHz)");
        end

        update_div_samples = 16'd0; restart;
        measure_runs(100);
        check((run_min == 1) && (run_max == 1), "Bien 6: div=0 -> xu ly nhu div=1 (khong treo)");

        // Doi toc do giua chung: 8 -> 1
        update_div_samples = 16'd8; restart;
        measure_runs(20);
        update_div_samples = 16'd1;
        measure_runs(40);
        check((run_min <= 2) && (run_max <= 2) && (n_change >= 38),
              "Bien 7: Doi div 8 -> 1 giua chung -> ap dung ngay, khong ket");

        //-------------------------------------------------------------
        // 4. Reset tra ve SEED; LFSR khong ve 0
        //-------------------------------------------------------------
        noise_amp_q8 = 9'd256; update_div_samples = 16'd1;
        restart; pulse_sample;
        check(noise_out === scale(SEED, 9'd256), "Bien 8: Sau reset, mau dau = SEED (lap lai duoc)");
        check(n_zero_state == 0, "Bien 9: LFSR khong bao gio ve trang thai 0 (khong ket)");

        //-------------------------------------------------------------
        // 5. Do "trang": tu tuong quan lag-1 (div = 1)
        //-------------------------------------------------------------
        restart;
        pulse_sample; prev = noise_out;
        sum = 0.0; sum_xy = 0.0; sum_xx = 0.0;
        for (i = 0; i < 8000; i = i + 1) begin
            pulse_sample;
            sum_xy = sum_xy + (1.0 * prev) * noise_out;
            sum_xx = sum_xx + (1.0 * noise_out) * noise_out;
            prev = noise_out;
        end
        r1 = sum_xy / sum_xx;
        $display("[DO ] Tu tuong quan lag-1 = %0.3f (nhieu trang ly tuong = 0; dich 1 buoc/mau se la ~ -0.25)", r1);
        check((r1 < 0.05) && (r1 > -0.05),
              "Bien 10: Nhieu gan trang: |tu tuong quan lag-1| < 0.05 (leap-forward 24 buoc)");


        $display("TONG KET LFSR: PASS=%0d FAIL=%0d",pass_count,fail_count);
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_lfsr_noise FAIL");
    end
endmodule
