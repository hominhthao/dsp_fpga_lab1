module toggle_sync_pulse (
    input  wire clk,
    input  wire rst_n,
    input  wire toggle_async,
    output wire pulse_out
);

    reg sync_ff1;
    reg sync_ff2;
    reg sync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1  <= 1'b0;
            sync_ff2  <= 1'b0;
            sync_prev <= 1'b0;
        end
        else begin
            sync_ff1  <= toggle_async;
            sync_ff2  <= sync_ff1;
            sync_prev <= sync_ff2;
        end
    end

    assign pulse_out = sync_ff2 ^ sync_prev;

endmodule
