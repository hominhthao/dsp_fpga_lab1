`timescale 1ns/1ps

//=============================================================================
// tb_lab1_top.sv
//
// Testbench tich hop toan he thong (lab1_top) - kiem tra tu SW/KEY den chan
// I2S ra CODEC, bao gom duong CDC giua CLOCK_50 va clock audio 12.288 MHz.
//
// Moi truong gia lap:
//   - audio_pll_sim.v thay cho altera_pll (clock audio lech pha, bat dong bo).
//   - Slave I2C tra ACK (gia lap WM8731) de he thong cau hinh xong.
//   - Bo thu I2S lay mau tren canh len BCLK (nhu codec that).
//   - Rut ngan thoi gian chong doi phim bang defparam (chi trong mo phong).
//
// Kiem tra:
//   1) Khoi dong: PLL lock, cau hinh codec xong, LEDR[9:8] = 11.
//   2) CDC: chuoi mau I2S khop BIT-EXACT voi mo hinh sine tham chieu
//      (khong mat mau, khong lap mau qua duong CLOCK_50 -> clock audio),
//      so sample_tick = so frame I2S; kenh trai = kenh phai.
//   3) KEY UP (che do tan so) -> 2 kHz tren ngo ra I2S.
//   4) SW chon Square + duty 25% -> ti le muc cao va muc bit-exact.
//   5) SW bat noise 50% -> ngo ra co nhieu, khong tran.
//   6) KEY[3] doi toc do noise 1 -> 2 -> 4 -> 8 -> 1.
//   7) SW[4] = 1 + KEY UP -> bien do tang (muc vuong 144/256).
//   8) SW chon ECG / ma khong hop le -> MUX dung, ngo ra = 0.
//   9) KEY[0] reset giua chung -> cau hinh lai codec, am thanh chay lai tu dau.
//=============================================================================

module tb_lab1_top;

    localparam integer SIM_DEBOUNCE = 16;
    localparam [31:0] INC_1KHZ = 32'd89_478_485;
    localparam [31:0] INC_2KHZ = 32'd178_956_970;

    reg        CLOCK_50;
    reg  [3:0] KEY;
    reg  [9:0] SW;
    wire [9:0] LEDR;
    wire AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_DACDAT;
    wire FPGA_I2C_SCLK;
    wire FPGA_I2C_SDAT;

    pullup (FPGA_I2C_SDAT);

    lab1_top dut (
        .CLOCK_50      (CLOCK_50),
        .KEY           (KEY),
        .SW            (SW),
        .LEDR          (LEDR),
        .AUD_XCK       (AUD_XCK),
        .AUD_BCLK      (AUD_BCLK),
        .AUD_DACLRCK   (AUD_DACLRCK),
        .AUD_DACDAT    (AUD_DACDAT),
        .FPGA_I2C_SCLK (FPGA_I2C_SCLK),
        .FPGA_I2C_SDAT (FPGA_I2C_SDAT)
    );

    // Rut ngan debounce 20 ms -> 16 chu ky (chi trong mo phong)
    defparam dut.u_signal_core.DEBOUNCE_CNT     = SIM_DEBOUNCE;
    defparam dut.u_key_noise_rate.STABLE_CYCLES = SIM_DEBOUNCE;

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    //=========================================================================
    // Slave I2C toi gian: tra ACK sau moi byte
    //=========================================================================
    reg     i2c_ack;
    integer i2c_bits;
    reg     i2c_in_frame;
    assign FPGA_I2C_SDAT = i2c_ack ? 1'b0 : 1'bz;

    initial begin i2c_ack = 1'b0; i2c_bits = 0; i2c_in_frame = 1'b0; end

    always @(negedge FPGA_I2C_SDAT)
        if (FPGA_I2C_SCLK === 1'b1 && !i2c_ack) begin i2c_in_frame = 1'b1; i2c_bits = 0; end
    always @(posedge FPGA_I2C_SDAT)
        if (FPGA_I2C_SCLK === 1'b1 && !i2c_ack) i2c_in_frame = 1'b0;
    always @(posedge FPGA_I2C_SCLK)
        if (i2c_in_frame && i2c_bits < 8) i2c_bits = i2c_bits + 1;
    always @(negedge FPGA_I2C_SCLK)
        if (i2c_in_frame) begin
            if (i2c_bits == 8)      begin i2c_ack <= #100 1'b1; i2c_bits = 9; end
            else if (i2c_bits == 9) begin i2c_ack <= #100 1'b0; i2c_bits = 0; end
        end

    //=========================================================================
    // Bo thu I2S: luu tung word kenh trai / phai
    //=========================================================================
    localparam integer MAXW = 4096;
    reg signed [23:0] rx_l [0:MAXW-1];
    reg signed [23:0] rx_r [0:MAXW-1];
    integer nl, nr;
    reg     lr_prev, rx_started, rx_ch;
    integer bit_pos;
    reg [23:0] rx_word;

    initial begin nl = 0; nr = 0; lr_prev = 1'b1; rx_started = 1'b0; bit_pos = 0; end

    always @(posedge AUD_BCLK) begin
        if (AUD_DACLRCK !== lr_prev) begin
            if (rx_started) begin
                if (rx_ch == 1'b0) begin if (nl < MAXW) rx_l[nl] = rx_word; nl = nl + 1; end
                else               begin if (nr < MAXW) rx_r[nr] = rx_word; nr = nr + 1; end
            end
            rx_started = 1'b1;
            rx_ch      = AUD_DACLRCK;
            bit_pos    = 0;
            rx_word    = 24'd0;
        end
        else if (rx_started) begin
            bit_pos = bit_pos + 1;
            if (bit_pos >= 1 && bit_pos <= 24)
                rx_word = {rx_word[22:0], AUD_DACDAT};
        end
        lr_prev = AUD_DACLRCK;
    end

    // Dem sample_tick (mien CLOCK_50) de so voi so frame I2S
    integer n_tick;
    initial n_tick = 0;
    always @(posedge CLOCK_50) if (dut.sample_tick) n_tick = n_tick + 1;

    //=========================================================================
    // Mo hinh tham chieu: sine = (LUT[phase[31:24]] * amp) >>> 8
    //=========================================================================
    reg signed [23:0] sine_lut [0:255];
    initial $readmemh("sine_lut.hex", sine_lut);

    function automatic signed [23:0] sine_ref;
        input integer n;           // chi so mau ke tu reset
        input [31:0]  inc;
        input [7:0]   amp;
        reg [31:0] ph;
        reg signed [31:0] p;
        begin
            ph = n * inc;
            p  = sine_lut[ph[31:24]] * $signed({1'b0, amp});
            sine_ref = p[31:8];
        end
    endfunction

    function automatic signed [23:0] sq_level;
        input [7:0] amp;
        reg signed [33:0] p;
        begin
            p = $signed(34'sd8388607) * $signed({26'd0, amp});
            sq_level = p >>> 8;
        end
    endfunction

    //=========================================================================
    // Tien ich
    //=========================================================================
    integer pass_count, fail_count;

    task check;
        input cond;
        input [8*110-1:0] name;
        begin
            if (cond) begin pass_count = pass_count + 1; $display("[PASS] %0s", name); end
            else      begin fail_count = fail_count + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task wait_frames;
        input integer n;
        integer target;
        begin
            target = nr + n;
            wait (nr >= target);
        end
    endtask

    task press;     // nhan va nha 1 phim (active-low)
        input integer k;
        begin
            KEY[k] = 1'b0;
            repeat (SIM_DEBOUNCE + 20) @(posedge CLOCK_50);
            KEY[k] = 1'b1;
            repeat (SIM_DEBOUNCE + 20) @(posedge CLOCK_50);
        end
    endtask

    task wait_system_ready;
        input integer timeout_us;
        integer t;
        begin
            t = 0;
            while (!dut.system_ready && t < timeout_us) begin #1000; t = t + 1; end
        end
    endtask

    // So khop chuoi mau I2S voi sine tham chieu, bat dau tu mau khac 0 dau tien
    // (mau tham chieu n = 1). Tra ve so mau sai.
    integer first_nz, n_bad, n_chk;
    task automatic match_sine;
        input integer from_idx;
        input integer count;
        input [31:0]  inc;
        input [7:0]   amp;
        integer k;
        begin
            first_nz = -1; n_bad = 0; n_chk = 0;
            for (k = from_idx; k < nl && first_nz < 0; k = k + 1)
                if (rx_l[k] != 0) first_nz = k;
            if (first_nz >= 0) begin
                for (k = 0; k < count && (first_nz + k) < nl && (first_nz + k) < nr; k = k + 1) begin
                    n_chk = n_chk + 1;
                    if (rx_l[first_nz + k] !== sine_ref(k + 1, inc, amp)) begin
                        if (n_bad < 5)
                            $display("[!] frame %0d: I2S=%0d ref(n=%0d)=%0d",
                                     first_nz + k, rx_l[first_nz + k], k + 1, sine_ref(k + 1, inc, amp));
                        n_bad = n_bad + 1;
                    end
                end
            end
        end
    endtask

    integer k0, k, i, n_lr_bad, zc, n_hi, n_lo, n_oth, n_diff, tick0, fr0, max_abs;
    reg signed [23:0] lvl;

    //=========================================================================
    // Kich ban
    //=========================================================================
    initial begin
        pass_count = 0; fail_count = 0;
        KEY = 4'b1110;           // KEY[0] = 0: dang reset
        SW  = 10'b00_0_00_0_0_000; // Sine, noise off, freq mode, duty 25%

        $display("=====================================================");
        $display(" INTEGRATION TESTBENCH: lab1_top (SW/KEY -> CDC -> I2S)");
        $display("=====================================================");

        repeat (20) @(posedge CLOCK_50);
        KEY[0] = 1'b1;

        //-------------------------------------------------------------
        // 1. Khoi dong
        //-------------------------------------------------------------
        wait_system_ready(10_000);
        $display("[OUT] t=%0.3f ms: LEDR[9]=%0b (PLL) LEDR[8]=%0b (codec) system_ready=%0b",
                 $realtime/1.0e6, LEDR[9], LEDR[8], dut.system_ready);
        check((LEDR[9] === 1'b1) && (LEDR[8] === 1'b1) && (dut.system_ready === 1'b1),
              "Case 1: Khoi dong: PLL lock, codec cau hinh xong (LEDR[9:8]=11)");

        //-------------------------------------------------------------
        // 2. CDC + bit-exact: sine 1 kHz, amp 128
        //-------------------------------------------------------------
        k0 = nl; tick0 = n_tick; fr0 = nr;
        wait_frames(160);
        match_sine(k0, 140, INC_1KHZ, 8'd128);
        $display("[DO ] Sine 1 kHz: so %0d mau I2S voi mo hinh, sai %0d (bat dau frame %0d)",
                 n_chk, n_bad, first_nz);
        check((n_chk >= 140) && (n_bad == 0),
              "Case 2: Chuoi mau I2S khop bit-exact sine tham chieu (khong mat/lap mau qua CDC)");

        $display("[DO ] sample_tick=%0d | frame I2S=%0d trong cung khoang thoi gian",
                 n_tick - tick0, nr - fr0);
        check(((n_tick - tick0) - (nr - fr0) <= 1) && ((nr - fr0) - (n_tick - tick0) <= 1),
              "Case 3: So sample_tick (CLOCK_50) = so frame I2S (clock audio)");

        n_lr_bad = 0;
        for (k = 0; k < nr && k < nl; k = k + 1)
            if (rx_l[k] !== rx_r[k]) n_lr_bad = n_lr_bad + 1;
        check(n_lr_bad == 0, "Case 4: Kenh trai = kenh phai o moi frame");

        //-------------------------------------------------------------
        // 3. KEY[2] UP (SW[4]=0) -> 2 kHz
        //-------------------------------------------------------------
        press(2);
        check(dut.u_signal_core.wave_phase_inc === INC_2KHZ,
              "Case 5: KEY UP -> phase_inc = 2 kHz");
        wait_frames(4);
        k0 = nl; wait_frames(240);
        zc = 0;
        for (k = k0 + 1; k < k0 + 240; k = k + 1)
            if (rx_l[k-1] < 0 && rx_l[k] >= 0) zc = zc + 1;
        // 2 kHz = 24 mau/chu ky -> 240 frame = 10 chu ky (1 kHz se chi co 5)
        $display("[DO ] 2 kHz: %0d lan qua 0 di len trong 240 frame (ky vong 10; 1 kHz se la 5)", zc);
        check((zc >= 9) && (zc <= 11), "Case 6: Ngo ra I2S la sine 2 kHz (24 mau/chu ky)");

        //-------------------------------------------------------------
        // 4. SW -> Square, duty 25% (SW[9:8]=00)
        //-------------------------------------------------------------
        SW[2:0] = 3'b001;
        wait_frames(6);
        lvl = sq_level(8'd128);
        k0 = nl; wait_frames(240);
        n_hi = 0; n_lo = 0; n_oth = 0;
        for (k = k0; k < k0 + 240; k = k + 1)
            if (rx_l[k] == lvl) n_hi = n_hi + 1;
            else if (rx_l[k] == -lvl) n_lo = n_lo + 1;
            else n_oth = n_oth + 1;
        $display("[DO ] Square 2 kHz duty 25%%: cao=%0d thap=%0d khac=%0d (ky vong 60/180/0), muc=+/-%0d",
                 n_hi, n_lo, n_oth, lvl);
        check((n_oth == 0) && (n_hi >= 58) && (n_hi <= 62),
              "Case 7: SW chon Square duty 25% -> dung ti le va muc bit-exact tren I2S");

        SW[9:8] = 2'b10;   // 75%
        wait_frames(6);
        k0 = nl; wait_frames(240);
        n_hi = 0;
        for (k = k0; k < k0 + 240; k = k + 1) if (rx_l[k] == lvl) n_hi = n_hi + 1;
        $display("[DO ] Square duty 75%%: cao=%0d/240 (ky vong 180)", n_hi);
        check((n_hi >= 178) && (n_hi <= 182), "Case 8: SW[9:8] doi duty 25% -> 75% dung");

        //-------------------------------------------------------------
        // 5. Noise 50% (SW[3]=1, SW[6:5]=11)
        //-------------------------------------------------------------
        SW[3] = 1'b1; SW[6:5] = 2'b11;
        wait_frames(6);
        k0 = nl; wait_frames(240);
        n_diff = 0; max_abs = 0;
        for (k = k0; k < k0 + 240; k = k + 1) begin
            if (rx_l[k] != lvl && rx_l[k] != -lvl) n_diff = n_diff + 1;
            if (rx_l[k] > max_abs) max_abs = rx_l[k];
            if (-rx_l[k] > max_abs) max_abs = -rx_l[k];
        end
        $display("[DO ] Noise 50%%: %0d/240 mau bi nhieu, |max|=%0d", n_diff, max_abs);
        check(n_diff >= 230, "Case 9: Bat noise 50% -> gan nhu moi mau I2S bi cong nhieu");
        check(max_abs <= 8_388_608, "Case 10: Tin hieu + nhieu khong tran 24 bit");

        //-------------------------------------------------------------
        // 6. KEY[3]: toc do noise 1 -> 2 -> 4 -> 8 -> 1
        //-------------------------------------------------------------
        check(dut.noise_update_div_samples == 1, "Case 11a: Toc do noise mac dinh = 1 mau");
        press(3);
        check(dut.noise_update_div_samples == 2, "Case 11b: KEY[3] -> 2 mau");
        press(3); press(3);
        check(dut.noise_update_div_samples == 8, "Case 11c: KEY[3] x2 -> 8 mau");
        press(3);
        check(dut.noise_update_div_samples == 1, "Case 11d: KEY[3] -> quay ve 1 mau");

        //-------------------------------------------------------------
        // 7. Che do bien do: SW[4]=1, KEY UP -> 144
        //-------------------------------------------------------------
        SW[3] = 1'b0;
        SW[4] = 1'b1;
        press(2);
        check((dut.u_signal_core.wave_amp_ctrl == 8'd144) &&
              (dut.u_signal_core.wave_phase_inc === INC_2KHZ),
              "Case 12: SW[4]=1 + KEY UP -> bien do 144, tan so giu nguyen");
        wait_frames(6);
        lvl = sq_level(8'd144);
        k0 = nl; wait_frames(96);
        n_oth = 0;
        for (k = k0; k < k0 + 96; k = k + 1)
            if (rx_l[k] != lvl && rx_l[k] != -lvl) n_oth = n_oth + 1;
        $display("[DO ] Bien do 144: muc ky vong +/-%0d, mau khac muc = %0d", lvl, n_oth);
        check(n_oth == 0, "Case 13: Muc vuong tren I2S = +/-(0x7FFFFF*144>>8)");

        //-------------------------------------------------------------
        // 8. ECG va ma waveform khong hop le
        //-------------------------------------------------------------
        SW[2:0] = 3'b100;
        wait_frames(4);
        check(dut.clean_wave === dut.ecg_wave, "Case 14: SW=100 -> MUX chon ECG");
        SW[2:0] = 3'b111;
        wait_frames(6);
        k0 = nl; wait_frames(20);
        n_oth = 0;
        for (k = k0; k < k0 + 20; k = k + 1) if (rx_l[k] != 0) n_oth = n_oth + 1;
        check(n_oth == 0, "Case 15: SW=111 (khong hop le) -> ngo ra = 0");

        //-------------------------------------------------------------
        // 9. KEY[0] reset giua chung
        //-------------------------------------------------------------
        SW = 10'b00_0_00_0_0_000;
        KEY[0] = 1'b0;
        repeat (50) @(posedge CLOCK_50);
        check((LEDR[8] === 1'b0) && (dut.system_ready === 1'b0),
              "Case 16: KEY[0] = 0 -> he thong ve reset (LEDR[8] tat)");
        KEY[0] = 1'b1;
        wait_system_ready(10_000);
        check(LEDR[8] === 1'b1, "Case 17: Nha KEY[0] -> codec duoc cau hinh lai");
        check((dut.u_signal_core.wave_phase_inc === INC_1KHZ) &&
              (dut.u_signal_core.wave_amp_ctrl == 8'd128),
              "Case 18: Sau reset tham so ve mac dinh (1 kHz, bien do 128)");
        k0 = nl;
        wait_frames(100);
        match_sine(k0, 80, INC_1KHZ, 8'd128);
        $display("[DO ] Sau reset: so %0d mau, sai %0d", n_chk, n_bad);
        check((n_chk >= 80) && (n_bad == 0),
              "Case 19: Sau reset, sine chay lai tu pha 0, bit-exact");

        $display("=====================================================");
        $display("TONG KET LAB1_TOP: PASS=%0d | FAIL=%0d", pass_count, fail_count);
        $display("=====================================================");
        if (fail_count == 0) $finish;
        else $fatal(1, "tb_lab1_top FAIL");
    end

    // Chan thoi gian mo phong
    initial begin
        #60_000_000;
        $display("[FAIL] Qua thoi gian mo phong 60 ms");
        $fatal(1, "tb_lab1_top TIMEOUT");
    end

endmodule
