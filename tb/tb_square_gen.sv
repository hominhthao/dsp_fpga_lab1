`timescale 1ns/1ps

module tb_square_gen;
    reg clk;
    reg rst_n;
    reg sample_en;
    reg [31:0] phase_inc;
    reg [8:0] amp_q8;
    reg [8:0] duty_q8;
    wire signed [23:0] wave_out;

    integer pass_count;
    integer fail_count;
    integer i;
    integer sample_index;
    integer rise1;
    integer rise2;
    reg signed [23:0] prev;
    reg signed [23:0] hold_value;

    square_gen dut (
        .clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .phase_inc(phase_inc), .amp_q8(amp_q8), .duty_q8(duty_q8),
        .wave_out(wave_out)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    task pulse_sample;
        begin
            @(negedge clk); sample_en = 1'b1;
            @(negedge clk); sample_en = 1'b0;
            #1;
        end
    endtask

    task check;
        input cond;
        input [8*80-1:0] name;
        begin
            if (cond) begin pass_count = pass_count + 1; $display("[PASS] %0s", name); end
            else begin fail_count = fail_count + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0; sample_en = 0;
        phase_inc = 32'd89_478_485; // 1 kHz voi tan so lay mau 48 kHz
        amp_q8 = 9'd256;
        duty_q8 = 9'd128;
        repeat (4) @(posedge clk);
        check(wave_out === 24'sd0, "Reset dua ngo ra ve 0");
        rst_n = 1;

        pulse_sample;
        check(wave_out > 24'sd8_000_000, "Muc duong cua song vuong dat bien do 100%");

        hold_value = wave_out;
        repeat (20) @(posedge clk);
        check(wave_out === hold_value, "Ngo ra giu nguyen khi sample_en bang 0");

        // Do chu ky bang hai canh len lien tiep.
        prev = wave_out;
        rise1 = -1; rise2 = -1; sample_index = 0;
        for (i = 0; i < 140; i = i + 1) begin
            pulse_sample;
            sample_index = sample_index + 1;
            if ((prev < 0) && (wave_out > 0)) begin
                if (rise1 < 0) rise1 = sample_index;
                else if (rise2 < 0) rise2 = sample_index;
            end
            prev = wave_out;
        end
        check((rise1 > 0) && (rise2 > rise1), "Phat hien duoc hai canh len");
        check(((rise2-rise1) >= 47) && ((rise2-rise1) <= 49), "Chu ky 1 kHz xap xi 48 mau audio");

        // Kiem tra bien do 50%.
        amp_q8 = 9'd128;
        pulse_sample;
        check((wave_out <= 24'sd4_200_000) && (wave_out >= -24'sd4_200_000), "Bien do 50% xap xi mot nua bien do toi da");

        $display("TONG KET SQUARE: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end
endmodule
