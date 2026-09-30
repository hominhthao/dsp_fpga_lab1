`timescale 1ns/1ps

//=============================================================================
// audio_pll_sim.v  --  CHI DUNG CHO MO PHONG (khong dua vao Quartus)
//
// Mo hinh thay the cho audio_pll.v (altera_pll) de mo phong top-level
// ma khong can thu vien altera_lnsim:
//   - clk_12m288: 12.288 MHz (chu ky 81.38 ns), chay tu do, KHONG dong pha
//     voi refclk -> tao dung tinh huong CDC bat dong bo nhu tren board.
//   - locked: len 1 sau 500 chu ky refclk (10 us), ve 0 khi rst = 1.
//=============================================================================

module audio_pll (
    input  wire refclk,
    input  wire rst,
    output reg  clk_12m288,
    output reg  locked
);

    integer lock_cnt;

    initial begin
        clk_12m288 = 1'b0;
        locked     = 1'b0;
        lock_cnt   = 0;
        #3.7;                         // lech pha so voi refclk
        forever #40.690 clk_12m288 = ~clk_12m288;
    end

    always @(posedge refclk or posedge rst) begin
        if (rst) begin
            lock_cnt <= 0;
            locked   <= 1'b0;
        end
        else if (lock_cnt < 500)
            lock_cnt <= lock_cnt + 1;
        else
            locked <= 1'b1;
    end

endmodule
