`timescale 1ns/1ps

module tb_wm8731_i2s_tx;

    reg clk_audio;
    reg rst_n;
    reg signed [23:0] sample_async;
    wire aud_bclk;
    wire aud_daclrck;
    wire aud_dacdat;
    wire sample_req_toggle;

    integer audio_clk_count;
    integer bclk_rise_count;
    integer lr_edge_count;
    integer req_count;
    reg last_bclk;
    reg last_lr;
    reg last_req;

    wm8731_i2s_tx DUT (
        .clk_audio(clk_audio), .rst_n(rst_n),
        .sample_async(sample_async), .aud_bclk(aud_bclk),
        .aud_daclrck(aud_daclrck), .aud_dacdat(aud_dacdat),
        .sample_req_toggle(sample_req_toggle)
    );

    // Tao clock gan 12.288 MHz de mo phong chuc nang.
    initial clk_audio = 0;
    always #40.69 clk_audio = ~clk_audio;

    initial begin
        rst_n = 0;
        sample_async = 24'sh400000;
        audio_clk_count = 0;
        bclk_rise_count = 0;
        lr_edge_count = 0;
        req_count = 0;
        last_bclk = 0;
        last_lr = 1;
        last_req = 0;

        repeat (5) @(posedge clk_audio);
        rst_n = 1;

        repeat (2048) begin
            @(posedge clk_audio);
            audio_clk_count = audio_clk_count + 1;
            if (!last_bclk && aud_bclk)
                bclk_rise_count = bclk_rise_count + 1;
            if (last_lr != aud_daclrck)
                lr_edge_count = lr_edge_count + 1;
            if (last_req != sample_req_toggle)
                req_count = req_count + 1;
            last_bclk = aud_bclk;
            last_lr = aud_daclrck;
            last_req = sample_req_toggle;
        end

        $display("[KQ] clock_audio=%0d canh_len_BCLK=%0d canh_LRCLK=%0d yeu_cau_mau=%0d",
                 audio_clk_count, bclk_rise_count, lr_edge_count, req_count);
        $display("[YC] BCLK xap xi clk/4, LRCLK xap xi clk/256, moi frame stereo co mot yeu cau mau");

        if ((bclk_rise_count >= 510) && (bclk_rise_count <= 514))
            $display("[PASS] BCLK chia 4 dung");
        else
            $display("[FAIL] BCLK chia 4 sai");

        if ((lr_edge_count >= 15) && (lr_edge_count <= 17))
            $display("[PASS] Timing LRCLK dung");
        else
            $display("[FAIL] Timing LRCLK sai");

        if ((req_count >= 7) && (req_count <= 9))
            $display("[PASS] Moi frame stereo co dung mot yeu cau mau");
        else
            $display("[FAIL] So yeu cau mau tren moi frame stereo sai");

        $finish;
    end

endmodule
