`timescale 1ns/1ps

//=============================================================================
// tb_wm8731_i2s_data.sv
//
// Self-checking testbench kiem tra DU LIEU I2S cua wm8731_i2s_tx.
// Dung mot mo hinh bo thu I2S (gia lap WM8731 o che do slave):
//   - Lay mau LRCK/DACDAT tren canh len BCLK (nhu codec that).
//   - I2S chuan: MSB nam o canh len BCLK thu 2 sau khi LRCK doi muc.
//   - LRCK = 0: kenh trai, LRCK = 1: kenh phai.
// Kiem tra:
//   1) 24 bit nhan duoc khop bit-exact voi mau dua vao (nhieu gia tri bien).
//   2) Kenh trai va kenh phai cung mot mau.
//   3) Bit 25..32 cua moi kenh bang 0 (padding).
//   4) Moi kenh 32 BCLK, fs = 48 kHz, BCLK = 3.072 MHz.
//   5) Setup/hold cua DACDAT/LRCK so voi canh len BCLK.
//   6) Mau chi duoc chot 1 lan moi frame, dung thoi diem yeu cau mau.
//=============================================================================

module tb_wm8731_i2s_data;

    localparam integer N_VEC   = 12;
    localparam real    T_SETUP = 100.0;   // ns, du lon so voi yeu cau cua WM8731
    localparam real    T_HOLD  = 100.0;   // ns

    reg clk_audio;
    reg rst_n;
    reg signed [23:0] sample_async;
    wire aud_bclk;
    wire aud_daclrck;
    wire aud_dacdat;
    wire sample_req_toggle;

    wm8731_i2s_tx dut (
        .clk_audio         (clk_audio),
        .rst_n             (rst_n),
        .sample_async      (sample_async),
        .aud_bclk          (aud_bclk),
        .aud_daclrck       (aud_daclrck),
        .aud_dacdat        (aud_dacdat),
        .sample_req_toggle (sample_req_toggle)
    );

    // 12.288 MHz (chu ky 81.38 ns)
    initial clk_audio = 1'b0;
    always #40.690 clk_audio = ~clk_audio;

    //=========================================================================
    // Vector thu: cac gia tri bien cua so co dau 24-bit
    //=========================================================================
    reg [23:0] vec [0:N_VEC-1];
    initial begin
        vec[0]  = 24'h000000;   // 0
        vec[1]  = 24'h400000;   // +0.5 full-scale
        vec[2]  = 24'hC00000;   // -0.5 full-scale
        vec[3]  = 24'h7FFFFF;   // +max
        vec[4]  = 24'h800000;   // -max
        vec[5]  = 24'h000001;   // +1 LSB (kiem tra bit cuoi)
        vec[6]  = 24'hFFFFFF;   // -1 LSB
        vec[7]  = 24'hA5A5A5;   // xen ke bit
        vec[8]  = 24'h5A5A5A;
        vec[9]  = 24'h123456;
        vec[10] = 24'h800001;
        vec[11] = 24'h7FFFFE;
    end

    //=========================================================================
    // Nguon mau: giong top.v, cap nhat mau moi ~100 ns sau yeu cau mau.
    // Mau DUT chot tai canh yeu cau = gia tri sample_async luc do.
    //=========================================================================
    reg  [23:0] exp_q [0:63];
    integer     exp_wr, exp_rd;
    integer     vec_idx;
    integer     n_req;
    reg         last_req;

    always @(sample_req_toggle) begin
        if (rst_n) begin
            exp_q[exp_wr] = sample_async;   // gia tri vua duoc DUT chot
            exp_wr  = exp_wr + 1;
            n_req   = n_req + 1;
            #100;
            sample_async = vec[vec_idx % N_VEC];
            vec_idx = vec_idx + 1;
        end
    end

    //=========================================================================
    // Mo hinh bo thu I2S
    //=========================================================================
    reg         lr_prev;
    integer     bit_pos;        // 0 = bit tre sau LRCK, 1..24 = du lieu, >24 = padding
    reg  [23:0] rx_word;
    reg         rx_pad_nonzero;
    reg         rx_ch;          // kenh cua word dang nhan
    reg         rx_started;
    integer     bclk_per_ch;

    reg  [23:0] left_word;
    reg         have_left;

    integer     n_words_ok_l, n_words_ok_r, n_words_bad;
    integer     n_pad_bad, n_len_bad;
    integer     n_frames;

    realtime    t_data_change, t_lr_change, t_bclk_rise;
    integer     n_setup_bad, n_hold_bad;

    realtime    t_lr_fall_prev, lr_period_min, lr_period_max;
    realtime    t_bclk_rise_prev, bclk_period_min, bclk_period_max;

    task automatic finish_word;
        reg [23:0] expw;
        begin
            if (rx_started) begin
                if (bclk_per_ch != 32)
                    n_len_bad = n_len_bad + 1;
                if (rx_pad_nonzero)
                    n_pad_bad = n_pad_bad + 1;

                if (exp_rd < exp_wr) begin
                    expw = exp_q[exp_rd];
                    if (rx_ch == 1'b0) begin
                        // kenh trai
                        if (rx_word == expw) n_words_ok_l = n_words_ok_l + 1;
                        else begin
                            n_words_bad = n_words_bad + 1;
                            $display("[!] Kenh TRAI sai: nhan %06h, ky vong %06h", rx_word, expw);
                        end
                    end
                    else begin
                        // kenh phai: cung mau voi kenh trai, xong frame
                        if (rx_word == expw) n_words_ok_r = n_words_ok_r + 1;
                        else begin
                            n_words_bad = n_words_bad + 1;
                            $display("[!] Kenh PHAI sai: nhan %06h, ky vong %06h", rx_word, expw);
                        end
                        exp_rd   = exp_rd + 1;
                        n_frames = n_frames + 1;
                    end
                end
            end
        end
    endtask

    always @(posedge aud_bclk) begin
        if (rst_n) begin
            // Chu ky BCLK
            if (t_bclk_rise_prev >= 0.0) begin
                if (($realtime - t_bclk_rise_prev) < bclk_period_min) bclk_period_min = $realtime - t_bclk_rise_prev;
                if (($realtime - t_bclk_rise_prev) > bclk_period_max) bclk_period_max = $realtime - t_bclk_rise_prev;
            end
            t_bclk_rise_prev = $realtime;
            t_bclk_rise      = $realtime;

            // Setup: DACDAT/LRCK phai on dinh truoc canh len
            if (($realtime - t_data_change) < T_SETUP || ($realtime - t_lr_change) < T_SETUP)
                n_setup_bad = n_setup_bad + 1;

            if (aud_daclrck !== lr_prev) begin
                // LRCK vua doi: ket thuc word cu, bat dau word moi.
                // Canh len nay la bit tre I2S (bit_pos = 0).
                finish_word;
                rx_started     = 1'b1;
                rx_ch          = aud_daclrck;
                bit_pos        = 0;
                rx_word        = 24'd0;
                rx_pad_nonzero = 1'b0;
                bclk_per_ch    = 1;
            end
            else if (rx_started) begin
                bit_pos     = bit_pos + 1;
                bclk_per_ch = bclk_per_ch + 1;
                if (bit_pos >= 1 && bit_pos <= 24)
                    rx_word = {rx_word[22:0], aud_dacdat};
                else if (aud_dacdat !== 1'b0)
                    rx_pad_nonzero = 1'b1;
            end
            lr_prev = aud_daclrck;
        end
    end

    // Hold: DACDAT/LRCK khong duoc doi ngay sau canh len BCLK
    always @(aud_dacdat) begin
        t_data_change = $realtime;
        if (rst_n && ($realtime - t_bclk_rise) < T_HOLD)
            n_hold_bad = n_hold_bad + 1;
    end

    always @(aud_daclrck) begin
        t_lr_change = $realtime;
        if (rst_n && ($realtime - t_bclk_rise) < T_HOLD)
            n_hold_bad = n_hold_bad + 1;
        if (rst_n && aud_daclrck === 1'b0) begin
            if (t_lr_fall_prev >= 0.0) begin
                if (($realtime - t_lr_fall_prev) < lr_period_min) lr_period_min = $realtime - t_lr_fall_prev;
                if (($realtime - t_lr_fall_prev) > lr_period_max) lr_period_max = $realtime - t_lr_fall_prev;
            end
            t_lr_fall_prev = $realtime;
        end
    end

    //=========================================================================
    // Tien ich
    //=========================================================================
    integer pass_count, fail_count;

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

    //=========================================================================
    // Kich ban
    //=========================================================================
    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 1'b0;
        sample_async = 24'h000000;
        exp_wr = 0; exp_rd = 0; vec_idx = 1; n_req = 0;
        lr_prev = 1'b1; rx_started = 1'b0; bit_pos = 0; bclk_per_ch = 0;
        rx_word = 0; rx_pad_nonzero = 0; rx_ch = 0; have_left = 0;
        n_words_ok_l = 0; n_words_ok_r = 0; n_words_bad = 0;
        n_pad_bad = 0; n_len_bad = 0; n_frames = 0;
        t_data_change = -1.0e9; t_lr_change = -1.0e9; t_bclk_rise = -1.0e9;
        n_setup_bad = 0; n_hold_bad = 0;
        t_lr_fall_prev = -1.0; lr_period_min = 1.0e12; lr_period_max = 0.0;
        t_bclk_rise_prev = -1.0; bclk_period_min = 1.0e12; bclk_period_max = 0.0;

        $display("=====================================================");
        $display(" SELF-CHECK TESTBENCH: wm8731_i2s_tx (du lieu I2S)");
        $display("=====================================================");

        repeat (5) @(posedge clk_audio);
        rst_n = 1'b1;

        // Chay N_VEC + 2 frame (moi frame 20.83 us)
        #((N_VEC + 2) * 20_833.4);

        $display("[OUT] frame=%0d | yeu cau mau=%0d | word trai dung=%0d | word phai dung=%0d | word sai=%0d",
                 n_frames, n_req, n_words_ok_l, n_words_ok_r, n_words_bad);
        $display("[DO ] BCLK: %0.2f..%0.2f ns (ky vong 325.52 ns = 3.072 MHz)",
                 bclk_period_min, bclk_period_max);
        $display("[DO ] LRCK: %0.1f..%0.1f ns (ky vong 20833.3 ns = 48 kHz)",
                 lr_period_min, lr_period_max);

        check(n_frames >= N_VEC, "Case 1: Nhan du so frame I2S");
        check(n_words_bad == 0, "Case 2: 24 bit kenh TRAI va PHAI khop bit-exact voi mau dua vao");
        // Frame cuoi co the moi nhan xong kenh trai khi dung mo phong (+1).
        check((n_words_ok_r == n_frames) &&
              ((n_words_ok_l == n_frames) || (n_words_ok_l == n_frames + 1)),
              "Case 3: Kenh trai va kenh phai phat cung mot mau trong moi frame");
        check(n_pad_bad == 0, "Case 4: Bit 25..32 cua moi kenh bang 0");
        check(n_len_bad == 0, "Case 5: Moi kenh dung 32 BCLK (1 bit tre + 24 bit + 7 bit dem)");
        check((bclk_period_min > 325.0) && (bclk_period_max < 326.1),
              "Case 6: BCLK = clk_audio / 4 = 3.072 MHz");
        check((lr_period_min > 20_830.0) && (lr_period_max < 20_837.0),
              "Case 7: LRCK = 48 kHz (64 BCLK moi frame stereo)");
        check(n_setup_bad == 0, "Case 8: DACDAT/LRCK on dinh >= 100 ns truoc canh len BCLK (setup)");
        check(n_hold_bad == 0, "Case 9: DACDAT/LRCK giu >= 100 ns sau canh len BCLK (hold)");
        check((n_req >= n_frames) && (n_req <= n_frames + 2),
              "Case 10: Moi frame co dung 1 yeu cau mau");

        // Reset giua chung: dau ra ve trang thai reset
        rst_n = 1'b0;
        #200;
        check((aud_dacdat === 1'b0) && (aud_daclrck === 1'b1) && (aud_bclk === 1'b0),
              "Case 11: Reset -> DACDAT=0, LRCK=1, BCLK=0");

        $display("=====================================================");
        $display("TONG KET I2S DATA: PASS=%0d | FAIL=%0d", pass_count, fail_count);
        $display("=====================================================");
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_wm8731_i2s_data FAIL");
    end

endmodule
