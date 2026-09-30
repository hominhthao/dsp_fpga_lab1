`timescale 1ns/1ps

//=============================================================================
// tb_wm8731_config.sv
//
// Self-checking testbench cho wm8731_config + i2c_master_write.
// Dung mot mo hinh slave I2C (gia lap WM8731) de:
//   1) Bat START/STOP, doc tung byte tren canh len SCL, tra ACK.
//   2) Kiem tra dia chi thiet bi 0x34 (0x1A << 1, ghi).
//   3) Kiem tra dung 9 lan ghi thanh ghi, dung thu tu, dung gia tri.
//   4) Kiem tra config_done = 1, config_error = 0 khi codec tra ACK.
//   5) Kiem tra tan so SCL xap xi 100 kHz.
//   6) Kiem tra SDA khong doi khi SCL = 1 (ngoai START/STOP).
//   7) Truong hop codec khong tra ACK (NACK) -> config_error = 1.
//=============================================================================

module tb_wm8731_config;

    localparam integer N_REG = 9;

    reg clk;
    reg rst_n;
    wire scl;
    wire sda;
    wire config_done;
    wire config_error;

    // Bus I2C: SDA open-drain, co dien tro keo len.
    pullup (sda);

    wm8731_config dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .i2c_scl      (scl),
        .i2c_sda      (sda),
        .config_done  (config_done),
        .config_error (config_error)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    //=========================================================================
    // Bang gia tri ky vong (theo wm8731_config.sv va datasheet WM8731)
    //=========================================================================
    reg [6:0] exp_reg  [0:N_REG-1];
    reg [8:0] exp_data [0:N_REG-1];

    initial begin
        exp_reg[0] = 7'h0F; exp_data[0] = 9'h000; // Reset
        exp_reg[1] = 7'h02; exp_data[1] = 9'h079; // Left headphone out
        exp_reg[2] = 7'h03; exp_data[2] = 9'h079; // Right headphone out
        exp_reg[3] = 7'h04; exp_data[3] = 9'h012; // Analogue path: DACSEL, mute mic
        exp_reg[4] = 7'h05; exp_data[4] = 9'h000; // Digital path: DAC unmute
        exp_reg[5] = 7'h06; exp_data[5] = 9'h007; // Power down: tat line-in/mic/ADC
        exp_reg[6] = 7'h07; exp_data[6] = 9'h00A; // I2S, 24-bit, slave
        exp_reg[7] = 7'h08; exp_data[7] = 9'h000; // 48 kHz, 256fs
        exp_reg[8] = 7'h09; exp_data[8] = 9'h001; // Active
    end

    //=========================================================================
    // Mo hinh slave I2C
    //=========================================================================
    reg        slave_ack_en;     // 1: tra ACK, 0: khong tra ACK (NACK)
    reg        slave_drive_low;
    assign sda = slave_drive_low ? 1'b0 : 1'bz;

    integer    bit_cnt;          // so bit da nhan trong byte hien tai
    integer    byte_cnt;         // so byte trong giao dich hien tai
    reg  [7:0] shift_reg;
    reg  [7:0] rx_bytes [0:3];
    reg        in_frame;

    // Ket qua cac giao dich
    integer    n_trans;
    integer    n_bad_len;
    reg  [7:0] trans_b0 [0:15];
    reg  [7:0] trans_b1 [0:15];
    reg  [7:0] trans_b2 [0:15];

    // Kiem tra quy tac: SDA chi doi khi SCL = 0
    integer    n_sda_violation;
    integer    n_sda_same_edge;  // SDA doi dung cung thoi diem SCL xuong
    realtime   t_scl_fall;
    realtime   t_sda_change;

    // Do tan so SCL
    realtime   t_scl_rise_prev;
    realtime   scl_period_min;
    realtime   scl_period_max;
    integer    n_scl_period;

    initial begin
        slave_drive_low = 1'b0;
        in_frame        = 1'b0;
        bit_cnt         = 0;
        byte_cnt        = 0;
        n_trans         = 0;
        n_bad_len       = 0;
        n_sda_violation = 0;
        n_sda_same_edge = 0;
        t_scl_fall      = -1.0;
        t_sda_change    = -1.0;
        t_scl_rise_prev = -1.0;
        scl_period_min  = 1.0e12;
        scl_period_max  = 0.0;
        n_scl_period    = 0;
    end

    // START / STOP: SDA doi khi SCL dang o muc 1.
    always @(sda) begin
        if (scl === 1'b1 && $realtime != t_scl_fall) begin
            if (sda === 1'b0) begin
                // START (hoac repeated START)
                in_frame = 1'b1;
                bit_cnt  = 0;
                byte_cnt = 0;
                t_scl_rise_prev = -1.0;   // chi do chu ky SCL ben trong 1 giao dich
            end
            else if (sda === 1'b1) begin
                // STOP
                if (in_frame) begin
                    if (byte_cnt == 3) begin
                        trans_b0[n_trans] = rx_bytes[0];
                        trans_b1[n_trans] = rx_bytes[1];
                        trans_b2[n_trans] = rx_bytes[2];
                        n_trans = n_trans + 1;
                    end
                    else begin
                        n_bad_len = n_bad_len + 1;
                    end
                end
                in_frame = 1'b0;
            end
        end
    end

    // Nhan bit tren canh len SCL, do chu ky SCL.
    always @(posedge scl) begin
        if (t_scl_rise_prev >= 0.0 && in_frame) begin
            if (($realtime - t_scl_rise_prev) < scl_period_min)
                scl_period_min = $realtime - t_scl_rise_prev;
            if (($realtime - t_scl_rise_prev) > scl_period_max)
                scl_period_max = $realtime - t_scl_rise_prev;
            n_scl_period = n_scl_period + 1;
        end
        t_scl_rise_prev = in_frame ? $realtime : -1.0;

        if (in_frame && bit_cnt < 8) begin
            shift_reg = {shift_reg[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
            bit_cnt   = bit_cnt + 1;
        end
    end

    // Tren canh xuong SCL: sau bit thu 8 thi keo SDA xuong de ACK,
    // sau xung ACK (bit thu 9) thi nha SDA.
    always @(negedge scl) begin
        t_scl_fall = $realtime;
        // Dem 1 lan neu SDA da doi truoc do trong cung thoi diem
        // (block nao chay sau thi dem -> khong phu thuoc thu tu su kien cua simulator)
        if (t_sda_change == $realtime && $realtime > 0)
            n_sda_same_edge = n_sda_same_edge + 1;
        if (in_frame) begin
            if (bit_cnt == 8) begin
                if (byte_cnt < 4)
                    rx_bytes[byte_cnt] = shift_reg;
                byte_cnt = byte_cnt + 1;
                bit_cnt  = 9;                 // dang o pha ACK
                slave_drive_low <= #100 slave_ack_en;   // tre 100 ns (hold time)
            end
            else if (bit_cnt == 9) begin
                bit_cnt = 0;
                slave_drive_low <= #100 1'b0;
            end
        end
    end

    // SDA doi trong khi SCL = 1 ma khong phai START/STOP hop le
    // (START chi hop le khi chua o trong frame; STOP chi hop le khi bit_cnt = 0).
    always @(sda) begin
        t_sda_change = $realtime;
        if ($realtime == t_scl_fall && $realtime > 0)
            n_sda_same_edge = n_sda_same_edge + 1;
        else if (scl === 1'b1 && in_frame && bit_cnt != 0 && !slave_drive_low)
            n_sda_violation = n_sda_violation + 1;
    end

    //=========================================================================
    // Tien ich
    //=========================================================================
    integer pass_count, fail_count;
    integer i, n_match;

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

    task automatic wait_config_done;
        input integer timeout_us;
        integer k;
        begin
            k = 0;
            while (!config_done && k < timeout_us) begin
                #1000;
                k = k + 1;
            end
        end
    endtask

    task reset_all;
        begin
            rst_n = 1'b0;
            n_trans = 0;
            n_bad_len = 0;
            n_sda_violation = 0;
            n_sda_same_edge = 0;
            n_scl_period = 0;
            scl_period_min = 1.0e12;
            scl_period_max = 0.0;
            in_frame = 1'b0;
            bit_cnt = 0;
            byte_cnt = 0;
            slave_drive_low = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask

    //=========================================================================
    // Kich ban
    //=========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b0;
        slave_ack_en = 1'b1;

        $display("=====================================================");
        $display(" SELF-CHECK TESTBENCH: wm8731_config + i2c_master_write");
        $display("=====================================================");

        //---------------------------------------------------------------
        // CASE 1: Codec tra ACK binh thuong
        //---------------------------------------------------------------
        reset_all;
        #1;
        check((scl === 1'b1) && (sda === 1'b1) && !config_done && !config_error,
              "Case 1: Sau reset bus I2C o trang thai nghi (SCL=1, SDA=1)");

        wait_config_done(10_000);   // toi da 10 ms
        repeat (10) @(posedge clk);

        $display("[OUT] t=%0.3f ms | so giao dich=%0d | config_done=%0b config_error=%0b",
                 $realtime/1.0e6, n_trans, config_done, config_error);

        check(config_done === 1'b1, "Case 2: config_done = 1 sau khi cau hinh xong");
        check(config_error === 1'b0, "Case 3: config_error = 0 khi codec tra ACK");
        check(n_trans == N_REG, "Case 4: Dung 9 giao dich ghi thanh ghi");
        check(n_bad_len == 0, "Case 5: Moi giao dich dung 3 byte (dia chi + 2 byte du lieu)");

        n_match = 0;
        for (i = 0; i < N_REG && i < n_trans; i = i + 1) begin
            $display("[IN ] ghi #%0d: byte = %02h %02h %02h -> R%02h = %03h (ky vong R%02h = %03h)",
                     i, trans_b0[i], trans_b1[i], trans_b2[i],
                     trans_b1[i][7:1], {trans_b1[i][0], trans_b2[i]},
                     exp_reg[i], exp_data[i]);
            if ((trans_b0[i] == 8'h34) &&
                (trans_b1[i] == {exp_reg[i], exp_data[i][8]}) &&
                (trans_b2[i] == exp_data[i][7:0]))
                n_match = n_match + 1;
        end
        check(n_match == N_REG,
              "Case 6: Dia chi 0x34 va 9 cap thanh ghi/gia tri dung thu tu");

        check((n_trans > 6) && (trans_b1[6][7:1] == 7'h07) &&
              ({trans_b1[6][0], trans_b2[6]} == 9'h00A),
              "Case 7: R07 = 0x00A (I2S, 24-bit, slave)");
        check((n_trans > 7) && (trans_b1[7][7:1] == 7'h08) &&
              ({trans_b1[7][0], trans_b2[7]} == 9'h000),
              "Case 8: R08 = 0x000 (48 kHz, MCLK = 256 fs)");
        check((n_trans > 8) && (trans_b1[8][7:1] == 7'h09) &&
              ({trans_b1[8][0], trans_b2[8]} == 9'h001),
              "Case 9: R09 = 0x001 (active) la lenh cuoi cung");

        $display("[DO ] chu ky SCL: min=%0.1f ns max=%0.1f ns (ky vong 10000 ns = 100 kHz)",
                 scl_period_min, scl_period_max);
        check((n_scl_period > 0) &&
              (scl_period_min >= 9_900.0) && (scl_period_max <= 10_100.0),
              "Case 10: Tan so SCL xap xi 100 kHz");

        check(n_sda_violation == 0,
              "Case 11: SDA khong doi khi SCL = 1 (tru START/STOP)");

        // Thong tin: SDA doi dung cung thoi diem SCL xuong (hold time = 0).
        $display("[INFO] So lan SDA doi cung thoi diem SCL xuong: %0d", n_sda_same_edge);
        if (n_sda_same_edge > 0)
            $display("[INFO] -> hold time SDA = 0 trong RTL; tren board phu thuoc do tre day.");

        //---------------------------------------------------------------
        // CASE 12: Codec khong tra ACK (vi du: day I2C loi, sai dia chi)
        //---------------------------------------------------------------
        slave_ack_en = 1'b0;
        reset_all;
        wait_config_done(10_000);
        repeat (10) @(posedge clk);
        $display("[OUT] NACK: config_done=%0b config_error=%0b", config_done, config_error);
        check(config_error === 1'b1,
              "Case 12: Codec khong ACK -> config_error = 1 (LEDR[8] tat, system_ready = 0)");

        //---------------------------------------------------------------
        // CASE 13: Reset giua luc dang cau hinh
        //---------------------------------------------------------------
        slave_ack_en = 1'b1;
        reset_all;
        #(2_500_000);                 // dang giua cac giao dich
        rst_n = 1'b0;
        #1000;
        check((scl === 1'b1) && (sda === 1'b1) && !config_done,
              "Case 13: Reset giua chung -> bus I2C ve nghi, config_done = 0");
        reset_all;
        wait_config_done(10_000);
        repeat (10) @(posedge clk);
        check(config_done && !config_error && (n_trans == N_REG),
              "Case 14: Sau reset, cau hinh lai tu dau thanh cong (9 giao dich)");

        $display("=====================================================");
        $display("TONG KET WM8731_CONFIG: PASS=%0d | FAIL=%0d", pass_count, fail_count);
        $display("=====================================================");
        if (fail_count == 0)
            $finish;
        else
            $fatal(1, "tb_wm8731_config FAIL");
    end

endmodule
