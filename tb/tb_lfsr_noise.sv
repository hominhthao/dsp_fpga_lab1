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
        input cond; input [8*80-1:0] name;
        begin
            if(cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s",name); end
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
        $display("TONG KET LFSR: PASS=%0d FAIL=%0d",pass_count,fail_count);
        $finish;
    end
endmodule
