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
        input cond; input [8*80-1:0] name;
        begin
            if (cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
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
        $display("TONG KET TRIANGLE: PASS=%0d FAIL=%0d",pass_count,fail_count);
        $finish;
    end
endmodule
