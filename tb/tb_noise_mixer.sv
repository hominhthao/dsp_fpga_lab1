`timescale 1ns/1ps

module tb_noise_mixer;
    reg signed [23:0] wave_in;
    reg signed [23:0] noise_in;
    reg noise_enable;
    wire signed [23:0] mixed_out;
    integer pass_count, fail_count;

    noise_mixer dut(.wave_in(wave_in),.noise_in(noise_in),.noise_enable(noise_enable),.mixed_out(mixed_out));

    task check;
        input cond; input [8*80-1:0] name;
        begin
            if(cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s",name); end
        end
    endtask

    initial begin
        pass_count=0; fail_count=0;
        wave_in=24'sd1000000; noise_in=24'sd250000; noise_enable=0; #1;
        check(mixed_out===24'sd1000000,"Tat noise thi ngo ra bang waveform goc");
        noise_enable=1; #1;
        check(mixed_out===24'sd1250000,"Cong waveform va noise dung");
        wave_in=24'sd8000000; noise_in=24'sd1000000; #1;
        check(mixed_out===24'sd8388607,"Bao hoa duong dung");
        wave_in=-24'sd8000000; noise_in=-24'sd1000000; #1;
        check(mixed_out===-24'sd8388608,"Bao hoa am dung");
        $display("TONG KET MIXER: PASS=%0d FAIL=%0d",pass_count,fail_count);
        $finish;
    end
endmodule
