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
        input cond; input [8*80-1:0] name;
        begin
            if(cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s",name); end
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
        $display("TONG KET SAWTOOTH: PASS=%0d FAIL=%0d",pass_count,fail_count);
        $finish;
    end
endmodule
