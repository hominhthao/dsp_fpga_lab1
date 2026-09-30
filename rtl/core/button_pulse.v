module button_pulse (
	input wire clk,
	input wire rst,
	input wire key_in,
	output reg pulse_out
);
	reg key_sync0, key_sync1;
	// đồng bộ 2 tầng chống metastability
	always @(posedge clk) begin
        if (rst) begin
            key_sync0 <= 1'b1;
            key_sync1 <= 1'b1;
        end else begin
		    key_sync0 <= key_in;
		    key_sync1 <= key_sync0;
        end
	end
	// debounce 20ms 50MHz clk
	parameter integer DEBOUNCE_CNT = 1_000_000;
	reg [19:0] cnt;
	reg key_stable, key_stable_prev;
	
	always @(posedge clk) begin 
		if (rst) begin
			cnt <= 0;
			key_stable <= 1'b1;
		end else if (key_sync1 != key_stable) begin
			 if (cnt == DEBOUNCE_CNT - 1) begin
				key_stable <= key_sync1;
				cnt <= 0;
			 end else begin
					cnt <= cnt + 1;
			 end
      end else begin
          cnt <= 0;
      end
    end
    always @(posedge clk) begin
        if (rst) begin
            key_stable_prev <= 1'b1;
            pulse_out <= 1'b0;
        end else begin
            key_stable_prev <= key_stable;
            pulse_out <= (key_stable_prev == 1'b1) && (key_stable == 1'b0);
        end
    end
endmodule
