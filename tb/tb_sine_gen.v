`timescale 1ns/1ps
//=============================================================================
// tb_sine_gen.v  --  SELF-CHECKING testbench cho module loi sine_gen
// (khong qua freq_ctrl/amp_ctrl/nut bam - test truc tiep lo DDS + LUT)
//
// Theo dung format cua tb_ecg_gen.sv:
//   [IN ] t=... | input parameters
//   [OUT] t=... | measured output / transition
//   [DO ] period, peak, ...
//   [PASS]/[FAIL] ...
//   TONG KET SINE_GEN: PASS=x | FAIL=y
//
// Phuong phap:
//   - Do chu ky bang diem tran (wraparound) cua thanh ghi phase, giong
//     cach do sawtooth/ECG - chinh xac tuyet doi vi phase_inc la luy thua 2.
//   - Do dinh/day/zero-crossing bang cach doi chieu voi chinh sine_lut.hex
//     (doc lai vao mang tham chieu rieng trong testbench), co tinh dung
//     do tre 1 chu ky cua thanh ghi output (khong dung dung sai, so khop
//     CHINH XAC tung mau vi da tinh dung offset pipeline).
//=============================================================================

module tb_sine_gen;

    //---------------------------------------------------------------
    // Clock 50MHz
    //---------------------------------------------------------------
    reg clk;
    initial clk = 1'b0;
    always #10 clk = ~clk;

    //---------------------------------------------------------------
    // DUT
    //---------------------------------------------------------------
    reg         rst;
    reg         sample_en;
    reg  [31:0] phase_inc;
    wire signed [23:0] sine_data;

    sine_gen DUT (
        .clk       (clk),
        .rst       (rst),
        .sample_en (sample_en),
        .phase_inc (phase_inc),
        .sine_data (sine_data)
    );

    //---------------------------------------------------------------
    // Mo hinh tham chieu: doc lai chinh sine_lut.hex vao mang rieng
    // cua testbench (khong dung chung mang cua DUT) de doi chieu doc lap
    //---------------------------------------------------------------
    reg signed [23:0] ref_lut [0:255];
    initial $readmemh("sine_lut.hex", ref_lut);

    //---------------------------------------------------------------
    // Bo dem PASS / FAIL toan cuc
    //---------------------------------------------------------------
    integer pass_cnt, fail_cnt;
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
    end

    task check(input cond, input [8*64-1:0] label);
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s", label);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s", label);
            end
        end
    endtask

    task do_reset;
        begin
            rst = 1'b1;
            sample_en = 1'b0;
            phase_inc = 32'd0;
            @(posedge clk); @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    //---------------------------------------------------------------
    // Task do chu ky bang wraparound cua thanh ghi phase (sim don vi: clock)
    //---------------------------------------------------------------
    reg [31:0] phase_prev;
    integer wrap1_t, wrap2_t, period_clk;

    task measure_period(input [31:0] p_inc, input [31:0] expected_period,
                         input [8*64-1:0] label);
        begin
            do_reset;
            phase_inc = p_inc;
            sample_en = 1'b1;

            phase_prev = DUT.phase;
            wrap1_t = -1;
            wrap2_t = -1;

            // Cho lan tran (wrap) dau tien: phase[31] giam dot ngot (tu gan max ve gan 0)
            while (wrap1_t < 0) begin
                @(posedge clk);
                if (DUT.phase < phase_prev) wrap1_t = $time;
                phase_prev = DUT.phase;
            end
            // Cho lan tran thu hai
            while (wrap2_t < 0) begin
                @(posedge clk);
                if (DUT.phase < phase_prev) wrap2_t = $time;
                phase_prev = DUT.phase;
            end

            period_clk = (wrap2_t - wrap1_t) / 20; // 20ns/clock -> so clock
            $display("[IN ] t=%0t | phase_inc=%0d", $time, p_inc);
            $display("[OUT] t=%0t | wrap1=%0t wrap2=%0t", $time, wrap1_t, wrap2_t);
            $display("[DO ] period=%0d clock (ky vong %0d)", period_clk, expected_period);
            check(period_clk == expected_period, label);
        end
    endtask

    //---------------------------------------------------------------
    // Bien dung cho cac test hinh dang song
    //---------------------------------------------------------------
    integer i;
    integer max_val, max_idx, min_val, min_idx;
    integer mismatch_cnt;
    reg signed [23:0] expected_sample;

    initial begin
        $display("=====================================================");
        $display(" SELF-CHECK TESTBENCH: sine_gen (loi DDS + LUT)");
        $display("=====================================================");

        //=================================================================
        // CASE 1: Reset behavior
        //=================================================================
        do_reset;
        check((DUT.phase == 32'd0) && (sine_data == 24'sd0),
              "Case 1: Reset -> phase=0, sine_data=0");

        //=================================================================
        // CASE 2-5: Do chu ky qua wraparound voi cac phase_inc khac nhau
        // Cong thuc: period(clock) = 2^32 / phase_inc
        //=================================================================
        measure_period(32'd8_388_608,   32'd512, "Case 2: period @ phase_inc=2^23 (mac dinh)");
        measure_period(32'd16_777_216,  32'd256, "Case 3: period @ phase_inc=2^24");
        measure_period(32'd33_554_432,  32'd128, "Case 4: period @ phase_inc=2^25");
        measure_period(32'd134_217_728, 32'd32,  "Case 5: period @ phase_inc=2^27 (MAX cua freq_ctrl)");

        //=================================================================
        // CASE 6: So khop CHINH XAC tung mau trong 2 chu ky lien tiep
        // (phase_inc=2^24 -> lut_addr tang dung 1 moi mau -> du doan chinh
        //  xac gia tri ke tiep = ref_lut[dia chi hien tai], tre 1 chu ky)
        //=================================================================
        do_reset;
        phase_inc = 32'd16_777_216; // 2^24
        sample_en = 1'b1;
        mismatch_cnt = 0;

        // Sau reset, phase=0 -> lut_addr=0 tai canh clock dau tien
        // sine_data cap nhat SAU 1 chu ky, nen bo qua mau dau (chua on dinh)
        @(posedge clk); // dia chi 0 duoc dung, sine_data se ra o canh ke tiep
        for (i = 0; i < 512; i = i + 1) begin
            expected_sample = ref_lut[i % 256];
            @(posedge clk);
            if (sine_data !== expected_sample) begin
                mismatch_cnt = mismatch_cnt + 1;
                if (mismatch_cnt <= 3)
                    $display("  [!] Mau %0d: DUT=%0d, ref=%0d", i, sine_data, expected_sample);
            end
        end
        $display("[IN ] t=%0t | phase_inc=2^24, quet 512 mau (2 chu ky)", $time);
        $display("[OUT] t=%0t | so mau khong khop = %0d / 512", $time, mismatch_cnt);
        $display("[DO ] so sanh bit-exact voi sine_lut.hex (co tinh tre pipeline)");
        check(mismatch_cnt == 0, "Case 6: bit-exact match 512 mau lien tiep vs sine_lut.hex");

        //=================================================================
        // CASE 7-10: Dinh / day / zero-crossing trong 1 chu ky sach
        //=================================================================
        do_reset;
        phase_inc = 32'd16_777_216; // 2^24
        sample_en = 1'b1;

        // Luu y: khong dung "24'sd8388608" lam gia tri khoi tao vi 8388608
        // VUOT PHAM VI bieu dien duong cua so signed 24-bit (toi da la
        // 8388607), Verilog se tu wrap thanh -8388608 truoc khi phep '-'
        // ap dung, gay loi nguoc dau. Dung hang so integer thuong (32-bit)
        // de tranh loi nay.
        max_val = -8_388_608; max_idx = -1;
        min_val =  8_388_607; min_idx = -1;

        @(posedge clk); // dong bo mau dau
        for (i = 0; i < 256; i = i + 1) begin
            @(posedge clk);
            if ($signed(sine_data) > max_val) begin
                max_val = $signed(sine_data);
                max_idx = i;
            end
            if ($signed(sine_data) < min_val) begin
                min_val = $signed(sine_data);
                min_idx = i;
            end
        end

        $display("[IN ] t=%0t | phase_inc=2^24, quet 1 chu ky (256 mau)", $time);
        $display("[OUT] t=%0t | max=%0d tai mau %0d | min=%0d tai mau %0d",
                   $time, max_val, max_idx, min_val, min_idx);
        $display("[DO ] tham chieu sine_lut.hex: max=8388607 tai index 64, min=-8388607 tai index 192");

        check(max_val == 24'sd8_388_607, "Case 7: dinh song = full-scale 8388607");
        check(max_idx == 64,             "Case 8: vi tri dinh dung index 64 (sau bu tre pipeline)");
        check(min_val == -24'sd8_388_607,"Case 9: day song = -full-scale -8388607");
        check(min_idx == 192,            "Case 10: vi tri day dung index 192");

        //=================================================================
        // CASE 11: phase_inc = 0 -> song dung yen (khong doi sau khi on dinh)
        //=================================================================
        do_reset;
        phase_inc = 32'd0;
        sample_en = 1'b1;
        @(posedge clk);
        @(posedge clk);
        begin : freeze_check
            reg signed [23:0] frozen_val;
            reg frozen_ok;
            frozen_val = sine_data;
            frozen_ok = 1'b1;
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                if (sine_data !== frozen_val) frozen_ok = 1'b0;
            end
            $display("[IN ] t=%0t | phase_inc=0", $time);
            $display("[OUT] t=%0t | sine_data giu nguyen = %0d qua 20 chu ky?", $time, frozen_val);
            $display("[DO ] frozen_ok=%0b", frozen_ok);
            check(frozen_ok, "Case 11: phase_inc=0 -> song dung yen, khong doi gia tri");
        end

        //=================================================================
        // CASE 12: rst duoc bat lai giua chung -> phase/sine_data ve 0 ngay
        //=================================================================
        phase_inc = 32'd16_777_216;
        sample_en = 1'b1;
        repeat (10) @(posedge clk); // cho chay vai mau (chac chan khac 0)
        rst = 1'b1;
        @(posedge clk);
        #1; // cho NBA (non-blocking assignment) trong DUT flush xong truoc
            // khi doc lai DUT.phase/sine_data, tranh doc trung gia tri cu
            // do race-condition giua 2 process cung kich hoat tai 1 canh clock
        $display("[IN ] t=%0t | rst=1 giua luc dang chay", $time);
        $display("[OUT] t=%0t | phase=%0d, sine_data=%0d", $time, DUT.phase, sine_data);
        $display("[DO ] ky vong phase=0, sine_data=0 ngay chu ky ke tiep");
        check((DUT.phase == 32'd0) && (sine_data == 24'sd0),
              "Case 12: rst giua chung -> phase=0, sine_data=0 tuc thi");
        rst = 1'b0;

        //=================================================================
        // TONG KET
        //=================================================================
        $display("=====================================================");
        $display("TONG KET SINE_GEN: PASS=%0d | FAIL=%0d", pass_cnt, fail_cnt);
        $display("=====================================================");

        $finish;
    end

endmodule
