`timescale 1ns/1ps

module tb_debounce;
    reg clk;
    reg rst_n;
    reg noisy_in;
    wire debounced_out;
    wire rise_pulse;
    wire fall_pulse;
    integer pass_count, fail_count, fall_count;

    debounce #(.STABLE_CYCLES(5),.INITIAL_STATE(1'b1)) dut (
        .clk(clk),.rst_n(rst_n),.noisy_in(noisy_in),
        .debounced_out(debounced_out),.rise_pulse(rise_pulse),.fall_pulse(fall_pulse)
    );

    initial clk=0;
    always #10 clk=~clk;
    always @(posedge clk) if(fall_pulse) fall_count=fall_count+1;

    task check;
        input cond; input [8*80-1:0] name;
        begin
            if(cond) begin pass_count=pass_count+1; $display("[PASS] %0s",name); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s",name); end
        end
    endtask

    initial begin
        pass_count=0; fail_count=0; fall_count=0; rst_n=0; noisy_in=1;
        repeat(4) @(posedge clk);
        check(debounced_out===1'b1,"KEY active-low co trang thai nghi bang 1 sau reset");
        rst_n=1;
        noisy_in=0; repeat(2) @(posedge clk);
        noisy_in=1; repeat(2) @(posedge clk);
        check(debounced_out===1'b1,"Xung doi ngan bi loai bo");
        noisy_in=0; repeat(10) @(posedge clk);
        check(debounced_out===1'b0,"Nhan phim on dinh duoc chap nhan");
        check(fall_count==1,"Moi lan nhan tao dung mot xung");
        $display("TONG KET DEBOUNCE: PASS=%0d FAIL=%0d",pass_count,fail_count);
        $finish;
    end
endmodule
