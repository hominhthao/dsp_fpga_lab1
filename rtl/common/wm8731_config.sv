module wm8731_config (
    input  wire clk,
    input  wire rst_n,
    output wire i2c_scl,
    inout  wire i2c_sda,
    output reg  config_done,
    output reg  config_error
);

    localparam [6:0] WM8731_ADDR = 7'h1A;
    localparam integer STARTUP_WAIT = 100_000; // Cho 2 ms voi clock 50 MHz

    reg start;
    reg [3:0] cfg_index;
    reg [16:0] wait_count;
    reg [6:0] reg_addr;
    reg [8:0] reg_data;

    wire busy;
    wire tx_done;
    wire tx_nack;

    always @(*) begin
        case (cfg_index)
            4'd0: begin reg_addr = 7'h0F; reg_data = 9'h000; end // Reset CODEC
            4'd1: begin reg_addr = 7'h02; reg_data = 9'h079; end // Am luong kenh trai
            4'd2: begin reg_addr = 7'h03; reg_data = 9'h079; end // Am luong kenh phai
            4'd3: begin reg_addr = 7'h04; reg_data = 9'h012; end // Chon DAC va tat microphone
            4'd4: begin reg_addr = 7'h05; reg_data = 9'h000; end // Duong xu ly so o che do binh thuong
            4'd5: begin reg_addr = 7'h06; reg_data = 9'h007; end // Tat line-in, microphone va ADC
            4'd6: begin reg_addr = 7'h07; reg_data = 9'h00A; end // I2S 24-bit, CODEC o che do slave
            4'd7: begin reg_addr = 7'h08; reg_data = 9'h000; end // 48 kHz, che do binh thuong, MCLK = 256Fs
            default: begin reg_addr = 7'h09; reg_data = 9'h001; end // Kich hoat CODEC
        endcase
    end

    i2c_master_write #(
        .CLK_HZ (50_000_000),
        .I2C_HZ (100_000)
    ) u_i2c (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .dev_addr (WM8731_ADDR),
        .reg_addr (reg_addr),
        .reg_data (reg_data),
        .scl      (i2c_scl),
        .sda      (i2c_sda),
        .busy     (busy),
        .done     (tx_done),
        .nack     (tx_nack)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start        <= 1'b0;
            cfg_index    <= 4'd0;
            wait_count   <= 17'd0;
            config_done  <= 1'b0;
            config_error <= 1'b0;
        end
        else begin
            start <= 1'b0;

            if (!config_done) begin
                if (wait_count < STARTUP_WAIT - 1) begin
                    wait_count <= wait_count + 1'b1;
                end
                else if (!busy && !tx_done) begin
                    start <= 1'b1;
                end

                if (tx_done) begin
                    if (tx_nack)
                        config_error <= 1'b1;

                    if (cfg_index == 4'd8)
                        config_done <= 1'b1;
                    else
                        cfg_index <= cfg_index + 1'b1;
                end
            end
        end
    end

endmodule
