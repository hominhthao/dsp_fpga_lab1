`timescale 1ns/1ps

//=============================================================================
// tb_ecg_gen.sv
//
// Self-checking testbench cho ECG:
//   1) ecg_gen      : reset, DDS period, full LUT waveform
//   2) amp_scaler   : bit-exact theo cong thuc RTL
//   3) ecg_gen_top  : KEY freq/amp, step va clamp MIN/MAX
//
// Waveform observation:
//   - Moi waveform case chi chay WAVE_CYCLES chu ky (mac dinh 2).
//   - Moi case co wave_case / wave_cycle / wave_sample de de quan sat.
//   - Dung ref_lut tu ecg_lut.hex de check tung mau cua waveform.
//
// Luu y:
//   - File ecg_lut.hex phai nam cung thu muc simulation.
//   - Cac gia tri PHASE_INC/AMP phai trung voi DUT hien tai.
//=============================================================================

module tb_ecg_gen;

    localparam integer N_LUT = 256;
    localparam real CLK_FREQ_HZ = 50_000_000.0;

    localparam logic [31:0] PHASE_INC_DEFAULT = 32'd8_388_608;
    localparam logic [31:0] PHASE_INC_STEP    = 32'd8_388_608;
    localparam logic [31:0] PHASE_INC_MIN     = 32'd8_388_608;
    localparam logic [31:0] PHASE_INC_MAX     = 32'd134_217_728;

    localparam logic [7:0] AMP_DEFAULT = 8'd128;
    localparam logic [7:0] AMP_STEP    = 8'd16;

    localparam integer WAVE_CYCLES = 2;
    localparam integer SIM_DEBOUNCE = 20;

    integer pass_count, fail_count;

    //=========================================================================
    // Debug markers cho Questa
    //=========================================================================
    integer wave_case;
    integer wave_cycle;
    integer wave_sample;
    logic   wave_active;

    initial begin
        wave_case   = 0;
        wave_cycle  = 0;
        wave_sample = 0;
        wave_active = 0;
    end

    //=========================================================================
    // Reference LUT
    //=========================================================================
    logic signed [23:0] ref_lut [0:N_LUT-1];
    integer ref_max_val;
    integer ref_min_val;
    integer ref_max_idx;

    function automatic integer abs_int(input integer x);
        abs_int = (x < 0) ? -x : x;
    endfunction

    task automatic report_check(
        input bit ok,
        input string name,
        input string pass_reason,
        input string fail_reason
    );
        begin
            if (ok) begin
                pass_count++;
                $display("[PASS] t=%0t | %s", $time, name);
                $display("       %s", pass_reason);
            end else begin
                fail_count++;
                $display("[FAIL] t=%0t | %s", $time, name);
                $display("       %s", fail_reason);
            end
        end
    endtask

    //=========================================================================
    // CLOCK
    //=========================================================================
    logic clk;
    initial clk = 1'b0;
    always #10 clk = ~clk;     // 50 MHz

    initial $timeformat(-6, 3, " us", 12);

    //=========================================================================
    // 1. ecg_gen CORE
    //=========================================================================
    logic               rst_core;
    logic               sample_en_core;
    logic        [31:0] phase_inc_core;
    logic signed [23:0] ecg_data_core;

    ecg_gen u_core (
        .clk       (clk),
        .rst       (rst_core),
        .sample_en (sample_en_core),
        .phase_inc (phase_inc_core),
        .ecg_data  (ecg_data_core)
    );

    assign sample_en_core = 1'b1;

    task automatic reset_core;
        begin
            rst_core = 1'b1;
            repeat (3) @(negedge clk);

            report_check(
                (u_core.phase === 32'd0) &&
                (ecg_data_core === 24'sd0),
                "C01 / ECG core reset",
                "phase=0 va ecg_data=0",
                $sformatf("phase=%0d ecg_data=%0d",
                          u_core.phase, $signed(ecg_data_core))
            );

            rst_core = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic measure_period_cycles(
        output integer period_cycles
    );
        logic [31:0] prev_phase;
        integer count;
        bit found;

        begin
            prev_phase = u_core.phase;

            // Tim lan wrap dau tien.
            @(negedge clk);
            while (!(u_core.phase < prev_phase)) begin
                prev_phase = u_core.phase;
                @(negedge clk);
            end

            count = 0;
            prev_phase = u_core.phase;
            found = 1'b0;

            while (!found) begin
                @(negedge clk);
                count++;

                if (u_core.phase < prev_phase) begin
                    period_cycles = count;
                    found = 1'b1;
                end else begin
                    prev_phase = u_core.phase;
                end
            end
        end
    endtask

    task automatic run_period_case(
        input integer case_no,
        input string  name,
        input logic [31:0] phase_value
    );
        integer period_cycles;
        integer expected_cycles;
        real freq_meas;

        begin
            wave_case = case_no;
            wave_active = 0;
            wave_cycle = 0;
            wave_sample = 0;

            $display("");
            $display("============================================================");
            $display("CASE C%02d: %s", case_no, name);

            phase_inc_core = phase_value;
            reset_core();

            measure_period_cycles(period_cycles);

            expected_cycles = int'((64'd1 << 32) / phase_value);
            freq_meas = CLK_FREQ_HZ / period_cycles;

            $display("[IN ] phase_inc=%0d", phase_value);
            $display("[DO ] period=%0d clock | expected=%0d | f=%.3f Hz",
                     period_cycles, expected_cycles, freq_meas);

            report_check(
                period_cycles == expected_cycles,
                {name, " / DDS period"},
                $sformatf("period=%0d clock", period_cycles),
                $sformatf("period=%0d, expected=%0d",
                          period_cycles, expected_cycles)
            );
        end
    endtask

    //-------------------------------------------------------------------------
    // Waveform check:
    // phase_inc = 2^24 -> phase[31:24] tang 1 LUT address moi sample_en.
    // 1 LUT cycle = 256 sample_en.
    //-------------------------------------------------------------------------
    //-------------------------------------------------------------------------
    // Waveform capture:
    //   - Chi quan sat, khong hard-code so sample/chu ky.
    //   - Mot chu ky duoc xac dinh bang phase wrap.
    //   - Vi vay case co phase_inc khac nhau van luon chi hien 2 chu ky.
    //-------------------------------------------------------------------------
    task automatic run_wave_case(
        input integer case_no,
        input string name,
        input logic [31:0] phase_value,
        input integer cycles_to_capture
    );
        integer cycle_count;
        logic [31:0] prev_phase;
        bit first;
        begin
            wave_case = case_no;
            wave_active = 0;
            wave_cycle = 0;
            wave_sample = 0;

            $display("");
            $display("============================================================");
            $display("WAVE C%02d: %s", case_no, name);
            $display("       capture = %0d phase cycles", cycles_to_capture);

            phase_inc_core = phase_value;
            reset_core();

            // Bat dau tai mot moc phase hien tai va cho den wrap.
            first = 1'b1;
            prev_phase = u_core.phase;
            cycle_count = 0;
            wave_active = 1;

            while (cycle_count < cycles_to_capture) begin
                @(negedge clk);

                if (!first && (u_core.phase < prev_phase)) begin
                    cycle_count++;
                    wave_cycle = cycle_count;
                    wave_sample = 0;
                end

                prev_phase = u_core.phase;
                first = 1'b0;

                // wave_sample chi la marker de nhin tren Questa.
                wave_sample = u_core.phase[31:24];
            end

            wave_active = 0;

            $display("[DO ] captured %0d complete phase cycles", cycle_count);
            $display("[DO ] waveform markers: wave_case=%0d, wave_cycle=0..%0d",
                     wave_case, cycle_count);
        end
    endtask

    //-------------------------------------------------------------------------
    // Full waveform bit-check.
    //
    // Dung phase_inc=2^24 de phase[31:24] tang 1 moi sample_en.
    // TB so ecg_data voi LUT theo address. Cho phep pipeline 1 mau neu
    // output cua ecg_gen dang la thanh ghi.
    //-------------------------------------------------------------------------
    task automatic check_full_lut_waveform;
        integer i;
        integer signed actual_now;
        integer signed actual_prev;
        integer signed expected_now;
        integer signed expected_prev;
        integer addr;
        integer mismatches;
        integer first_bad;
        begin
            wave_case = 6;
            wave_active = 0;

            $display("");
            $display("============================================================");
            $display("CASE C06: Full LUT waveform self-check");

            phase_inc_core = 32'd16_777_216; // 2^24
            reset_core();

            mismatches = 0;
            first_bad = -1;
            actual_prev = 0;

            // Skip dau pipeline sample.
            for (i = 0; i < N_LUT; i++) begin
                wave_sample = i;
                @(negedge clk);

                addr = u_core.phase[31:24];

                // Kiem tra theo address hien tai va address truoc do.
                actual_now = $signed(ecg_data_core);

                if (addr >= 0 && addr < N_LUT) begin
                    expected_now = $signed(ref_lut[addr]);

                    if (actual_now != expected_now) begin
                        // Neu ecg_data bi tre 1 sample, thu so voi
                        // address - 1 truoc khi ket luan FAIL.
                        if (addr > 0)
                            expected_prev = $signed(ref_lut[addr-1]);
                        else
                            expected_prev = $signed(ref_lut[N_LUT-1]);

                        if (actual_now != expected_prev) begin
                            mismatches++;
                            if (first_bad < 0)
                                first_bad = addr;
                        end
                    end
                end

                actual_prev = actual_now;
            end

            $display("[DO ] checked %0d LUT addresses", N_LUT);
            $display("[DO ] waveform mismatches=%0d", mismatches);

            report_check(
                mismatches == 0,
                "C06 / Full ECG LUT waveform",
                "toan bo 256 mau khop LUT (cho phep pipeline 1 sample)",
                $sformatf("mismatches=%0d, first_bad_addr=%0d",
                          mismatches, first_bad)
            );
        end
    endtask

    task automatic check_waveform_shape;
        integer i;
        integer signed max_val;
        integer signed min_val;
        integer max_idx;
        integer signed cur_val;

        begin
            wave_case = 6;
            wave_active = 0;

            $display("");
            $display("============================================================");
            $display("CASE C06: ECG shape / R peak / baseline");

            phase_inc_core = 32'd16_777_216;
            reset_core();

            max_val = -8_388_608;
            min_val =  8_388_607;
            max_idx = 0;

            for (i = 0; i < N_LUT; i++) begin
                @(negedge clk);
                cur_val = $signed(ecg_data_core);

                if (cur_val > max_val) begin
                    max_val = cur_val;
                    max_idx = i;
                end

                if (cur_val < min_val)
                    min_val = cur_val;
            end

            $display("[DO ] observed max=%0d idx=%0d", max_val, max_idx);
            $display("[DO ] observed min=%0d", min_val);
            $display("[REF] LUT max=%0d idx=%0d", ref_max_val, ref_max_idx);
            $display("[REF] LUT min=%0d", ref_min_val);

            report_check(
                abs_int(max_val-ref_max_val) <= 2,
                "C06 / R peak amplitude",
                "R peak gan dung reference LUT",
                $sformatf("max=%0d, ref=%0d", max_val, ref_max_val)
            );

            report_check(
                abs_int(max_idx-ref_max_idx) <= 2,
                "C06 / R peak position",
                "vi tri R peak gan dung reference LUT",
                $sformatf("idx=%0d, ref=%0d", max_idx, ref_max_idx)
            );

            report_check(
                (ref_lut[10]  == 24'sd0) &&
                (ref_lut[80]  == 24'sd0) &&
                (ref_lut[140] == 24'sd0) &&
                (ref_lut[230] == 24'sd0),
                "C06 / baseline reference",
                "cac diem baseline dai dien = 0",
                $sformatf("LUT[10]=%0d LUT[80]=%0d LUT[140]=%0d LUT[230]=%0d",
                          ref_lut[10], ref_lut[80],
                          ref_lut[140], ref_lut[230])
            );
        end
    endtask

    task automatic check_reset_midcycle;
        begin
            wave_case = 7;
            wave_active = 0;

            $display("");
            $display("============================================================");
            $display("CASE C07: Reset giua chu ky");

            phase_inc_core = 32'd16_777_216;
            rst_core = 1'b0;
            repeat (37) @(negedge clk);

            rst_core = 1'b1;
            @(negedge clk);

            report_check(
                (u_core.phase === 32'd0) &&
                (ecg_data_core === 24'sd0),
                "C07 / reset mid-cycle",
                "reset dua phase va output ve 0",
                $sformatf("phase=%0d ecg_data=%0d",
                          u_core.phase, $signed(ecg_data_core))
            );

            rst_core = 1'b0;
        end
    endtask

    //=========================================================================
    // 2. amp_scaler
    //=========================================================================
    logic signed [23:0] as_in;
    logic [7:0] as_amp;
    logic signed [23:0] as_out;

    amp_scaler u_amp_scaler (
        .sine_in  (as_in),
        .amp_ctrl (as_amp),
        .sine_out (as_out)
    );

    function automatic logic signed [23:0] expected_scaler(
        input logic signed [23:0] din,
        input logic [7:0] amp
    );
        logic signed [31:0] mult_result;
        begin
            mult_result = din * $signed({1'b0, amp});
            expected_scaler = mult_result[31:8];
        end
    endfunction

task automatic run_scaler_case(
    input integer              case_no,
    input string               name,
    input logic signed [23:0]  din,
    input logic [7:0]          amp,
    input logic signed [23:0]  expected
);
    begin
        //=========================================================
        // Marker cho Questa waveform
        //=========================================================
        wave_case   = case_no;
        wave_active = 1;
        wave_cycle  = 0;
        wave_sample = 0;

        //=========================================================
        // Đưa input vào amp_scaler
        //=========================================================
        as_in  = din;
        as_amp = amp;

        // Giữ case đủ lâu để quan sát
        #20;

        //=========================================================
        // Hiển thị
        //=========================================================
        $display("");
        $display("============================================================");
        $display("CASE C%02d: amp_scaler / %s", case_no, name);

        $display("[IN ] sine_in=%0d amp_ctrl=%0d",
                 as_in, as_amp);

        $display("[DO ] sine_out=%0d expected=%0d",
                 as_out, expected);

        //=========================================================
        // Self-check
        //=========================================================
        if (as_out === expected) begin

            report_check(
                1,
                $sformatf("C%02d / %s", case_no, name),
                "bit-exact PASS",
                ""
            );

        end
        else begin

            report_check(
                0,
                $sformatf("C%02d / %s", case_no, name),
                "bit-exact FAIL",
                $sformatf(
                    "actual=%0d expected=%0d",
                    as_out,
                    expected
                )
            );

        end

        //=========================================================
        // Kết thúc marker
        //=========================================================
        wave_active = 0;

        #5;
    end
endtask
    //=========================================================================
    // 3. ecg_gen_top
    //=========================================================================
    logic [3:0] KEY;
    logic rst_top;
    logic sample_en_top;
    logic signed [23:0] ecg_data_out_top;

    ecg_gen_top #(
        .DEBOUNCE_CNT(SIM_DEBOUNCE)
    ) DUT (
        .CLOCK_50     (clk),
        .KEY          (KEY),
        .rst_n          (rst_top),
        .sample_en    (sample_en_top),
        .ecg_data_out (ecg_data_out_top)
    );


    assign sample_en_top = 1'b1;

    task automatic reset_top;
        begin
            rst_top = 1'b0;
            KEY = 4'b1111;
            repeat (5) @(negedge clk);
            rst_top = 1'b1;
            repeat (2) @(negedge clk);

            report_check(
                (DUT.u_freq_ctrl.phase_inc === PHASE_INC_DEFAULT) &&
                (DUT.u_amp_ctrl.amp_ctrl === AMP_DEFAULT),
                "TOP / reset default",
                $sformatf("phase_inc=%0d amp=%0d",
                          DUT.u_freq_ctrl.phase_inc,
                          DUT.u_amp_ctrl.amp_ctrl),
                $sformatf("phase_inc=%0d amp=%0d, expected %0d/%0d",
                          DUT.u_freq_ctrl.phase_inc,
                          DUT.u_amp_ctrl.amp_ctrl,
                          PHASE_INC_DEFAULT, AMP_DEFAULT)
            );
        end
    endtask

    task automatic press_key(input integer idx);
        begin
            KEY[idx] = 1'b0;
            repeat (SIM_DEBOUNCE + 5) @(negedge clk);

            KEY[idx] = 1'b1;
            repeat (SIM_DEBOUNCE + 5) @(negedge clk);
        end
    endtask

    task automatic top_wave_capture(
        input integer case_no,
        input string name,
        input integer cycles_to_capture
    );
        integer cycle;
        integer sample;

        begin
            wave_case = case_no;
            wave_active = 1;

            $display("");
            $display("------------------------------------------------------------");
            $display("WAVE C%02d: %s", case_no, name);

            for (cycle = 0; cycle < cycles_to_capture; cycle++) begin
                wave_cycle = cycle;

                for (sample = 0; sample < N_LUT; sample++) begin
                    wave_sample = sample;
                    @(negedge clk);
                end
            end

            wave_active = 0;

            $display("[DO ] captured %0d cycles", cycles_to_capture);
        end
    endtask

    task automatic check_freq_controls;
        logic [31:0] before_val;
        integer i;

        begin
            wave_case = 11;
            reset_top();

            $display("");
            $display("============================================================");
            $display("CASE C11: freq_up / freq_down");

            before_val = DUT.u_freq_ctrl.phase_inc;
            press_key(0);

            report_check(
                DUT.u_freq_ctrl.phase_inc === before_val + PHASE_INC_STEP,
                "C11 / freq_up one step",
                $sformatf("%0d -> %0d", before_val,
                          DUT.u_freq_ctrl.phase_inc),
                $sformatf("actual=%0d expected=%0d",
                          DUT.u_freq_ctrl.phase_inc,
                          before_val + PHASE_INC_STEP)
            );

            before_val = DUT.u_freq_ctrl.phase_inc;
            press_key(1);

            report_check(
                DUT.u_freq_ctrl.phase_inc === before_val - PHASE_INC_STEP,
                "C11 / freq_down one step",
                $sformatf("%0d -> %0d", before_val,
                          DUT.u_freq_ctrl.phase_inc),
                $sformatf("actual=%0d expected=%0d",
                          DUT.u_freq_ctrl.phase_inc,
                          before_val - PHASE_INC_STEP)
            );

            reset_top();

            // Tu default=2^23 den MAX=2^27: can 16 lan freq_up tong cong.
            for (i = 0; i < 16; i++)
                press_key(0);

            report_check(
                DUT.u_freq_ctrl.phase_inc === PHASE_INC_MAX,
                "C11 / freq MAX clamp",
                $sformatf("phase_inc=%0d", DUT.u_freq_ctrl.phase_inc),
                $sformatf("actual=%0d expected MAX=%0d",
                          DUT.u_freq_ctrl.phase_inc, PHASE_INC_MAX)
            );

            press_key(0);

            report_check(
                DUT.u_freq_ctrl.phase_inc === PHASE_INC_MAX,
                "C11 / freq khong wrap tren MAX",
                "van giu MAX",
                $sformatf("actual=%0d", DUT.u_freq_ctrl.phase_inc)
            );
        end
    endtask

    task automatic check_amp_controls;
        integer i;

        begin
            wave_case = 14;

            $display("");
            $display("============================================================");
            $display("CASE C14: amp_up / amp_down / clamp");

            reset_top();

            press_key(2);

            report_check(
                DUT.u_amp_ctrl.amp_ctrl === AMP_DEFAULT + AMP_STEP,
                "C14 / amp_up one step",
                $sformatf("%0d -> %0d", AMP_DEFAULT,
                          DUT.u_amp_ctrl.amp_ctrl),
                $sformatf("actual=%0d expected=%0d",
                          DUT.u_amp_ctrl.amp_ctrl,
                          AMP_DEFAULT + AMP_STEP)
            );

            press_key(3);

            report_check(
                DUT.u_amp_ctrl.amp_ctrl === AMP_DEFAULT,
                "C14 / amp_down one step",
                $sformatf("ve lai %0d", DUT.u_amp_ctrl.amp_ctrl),
                $sformatf("actual=%0d expected=%0d",
                          DUT.u_amp_ctrl.amp_ctrl, AMP_DEFAULT)
            );

            // 128 / 16 = 8 lan ve 0.
            for (i = 0; i < 8; i++)
                press_key(3);

            report_check(
                DUT.u_amp_ctrl.amp_ctrl === 8'd0,
                "C14 / amp MIN clamp",
                "amp_ctrl=0",
                $sformatf("actual=%0d", DUT.u_amp_ctrl.amp_ctrl)
            );

            press_key(3);

            report_check(
                DUT.u_amp_ctrl.amp_ctrl === 8'd0,
                "C14 / amp khong wrap duoi 0",
                "van giu 0",
                $sformatf("actual=%0d", DUT.u_amp_ctrl.amp_ctrl)
            );
        end
    endtask

    //=========================================================================
    // MAIN
    //=========================================================================
    initial begin
        integer i;

        pass_count = 0;
        fail_count = 0;

        rst_core = 1'b0;
        phase_inc_core = PHASE_INC_DEFAULT;
        rst_top = 1'b1;
        KEY = 4'b1111;

        $readmemh("ecg_lut.hex", ref_lut);

        ref_max_val = -8_388_608;
        ref_min_val =  8_388_607;
        ref_max_idx = 0;

        for (i = 0; i < N_LUT; i++) begin
            if (integer'(ref_lut[i]) > ref_max_val) begin
                ref_max_val = integer'(ref_lut[i]);
                ref_max_idx = i;
            end
            if (integer'(ref_lut[i]) < ref_min_val)
                ref_min_val = integer'(ref_lut[i]);
        end

        $display("");
        $display("============================================================");
        $display("ECG SELF-CHECKING TESTBENCH");
        $display("Reference LUT: ecg_lut.hex");
        $display("LUT max=%0d idx=%0d | min=%0d",
                 ref_max_val, ref_max_idx, ref_min_val);
        $display("Waveform capture: %0d cycles/case", WAVE_CYCLES);
        $display("============================================================");

        $dumpfile("tb_ecg_gen.vcd");
        $dumpvars(0, tb_ecg_gen);

        //=====================================================================
        // CORE
        //=====================================================================
        reset_core();

        run_period_case(2, "Frequency default / phase_inc=2^23",
                        PHASE_INC_DEFAULT);

        run_wave_case(3, "ECG waveform / default phase",
                      PHASE_INC_DEFAULT, WAVE_CYCLES);

        run_period_case(4, "Frequency x2 / phase_inc=2^24",
                        32'd16_777_216);

        run_wave_case(4, "ECG waveform / phase_inc=2^24",
                      32'd16_777_216, WAVE_CYCLES);

        run_period_case(5, "Frequency x4 / phase_inc=2^25",
                        32'd33_554_432);

        run_wave_case(5, "ECG waveform / phase_inc=2^25",
                      32'd33_554_432, WAVE_CYCLES);

        check_full_lut_waveform();
        check_waveform_shape();
        check_reset_midcycle();

        //=====================================================================
        // AMP SCALER
        //=====================================================================
	run_scaler_case(8,"C08 / amp=0",8000000,8'd0,0);

	run_scaler_case(9,"C09 / amp=128 (+)",8000000,8'd128,4000000);

	run_scaler_case(9,"C09 / amp=128 (-)",-8000000,8'd128,-4000000);

	run_scaler_case(10,"C10 / amp=255",8000000,8'd255,7968750);

	run_scaler_case(10,"C10 / R peak x amp=200",8220835,8'd200,6422527);

        //=====================================================================
        // TOP CONTROL
        //=====================================================================
        check_freq_controls();

        // Sau freq test, cho quan sat waveform top voi 2 cycle.
        reset_top();
        top_wave_capture(12, "TOP waveform / frequency MAX", WAVE_CYCLES);

        check_amp_controls();

        // Amp=0 -> waveform phang 0, capture 2 cycle de quan sat.
        reset_top();
        for (i = 0; i < 8; i++)
            press_key(3);

        top_wave_capture(15, "TOP waveform / amp=0", WAVE_CYCLES);

        //=====================================================================
        // SUMMARY
        //=====================================================================
        $display("");
        $display("============================================================");
        $display("FINAL SUMMARY: PASS=%0d | FAIL=%0d",
                 pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0) begin
            $display("RESULT: ALL TESTS PASSED");
            $finish;
        end else begin
            $display("RESULT: TESTBENCH FAILED");
            $fatal(1, "tb_ecg_gen FAIL");
        end
    end

endmodule
