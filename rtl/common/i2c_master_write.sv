module i2c_master_write #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer I2C_HZ = 100_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [6:0]  dev_addr,
    input  wire [6:0]  reg_addr,
    input  wire [8:0]  reg_data,
    output reg         scl,
    inout  wire        sda,
    output reg         busy,
    output reg         done,
    output reg         nack
);

    localparam integer HALF_DIV = CLK_HZ / (I2C_HZ * 2);
    localparam integer DIV_W = (HALF_DIV <= 2) ? 1 : $clog2(HALF_DIV);

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_START     = 4'd1;
    localparam [3:0] ST_BIT_LOW   = 4'd2;
    localparam [3:0] ST_BIT_HIGH  = 4'd3;
    localparam [3:0] ST_ACK_LOW   = 4'd4;
    localparam [3:0] ST_ACK_HIGH  = 4'd5;
    localparam [3:0] ST_STOP_LOW  = 4'd6;
    localparam [3:0] ST_STOP_HIGH = 4'd7;
    localparam [3:0] ST_STOP_REL  = 4'd8;

    reg [3:0] state;
    reg [DIV_W-1:0] div_count;
    reg [1:0] byte_index;
    reg [2:0] bit_index;
    reg [6:0] dev_addr_latched;
    reg [6:0] reg_addr_latched;
    reg [8:0] reg_data_latched;
    reg sda_drive_low;

    wire sda_in;
    reg [7:0] current_byte;

    assign sda = sda_drive_low ? 1'b0 : 1'bz;
    assign sda_in = sda;

    always @(*) begin
        case (byte_index)
            2'd0: current_byte = {dev_addr_latched, 1'b0};
            2'd1: current_byte = {reg_addr_latched, reg_data_latched[8]};
            default: current_byte = reg_data_latched[7:0];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            div_count        <= 0;
            byte_index       <= 0;
            bit_index        <= 3'd7;
            dev_addr_latched <= 7'd0;
            reg_addr_latched <= 7'd0;
            reg_data_latched <= 9'd0;
            scl              <= 1'b1;
            sda_drive_low    <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
            nack             <= 1'b0;
        end
        else begin
            done <= 1'b0;

            if (state == ST_IDLE) begin
                div_count <= 0;
                scl <= 1'b1;
                sda_drive_low <= 1'b0;

                if (start) begin
                    dev_addr_latched <= dev_addr;
                    reg_addr_latched <= reg_addr;
                    reg_data_latched <= reg_data;
                    byte_index <= 2'd0;
                    bit_index <= 3'd7;
                    busy <= 1'b1;
                    nack <= 1'b0;
                    state <= ST_START;
                end
            end
            else if (div_count == HALF_DIV - 1) begin
                div_count <= 0;

                case (state)
                    ST_START: begin
                        // Dieu kien START: SDA chuyen tu 1 xuong 0 khi SCL dang o muc 1.
                        scl <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state <= ST_BIT_LOW;
                    end

                    ST_BIT_LOW: begin
                        scl <= 1'b0;
                        sda_drive_low <= ~current_byte[bit_index];
                        state <= ST_BIT_HIGH;
                    end

                    ST_BIT_HIGH: begin
                        scl <= 1'b1;
                        if (bit_index == 3'd0)
                            state <= ST_ACK_LOW;
                        else begin
                            bit_index <= bit_index - 3'd1;
                            state <= ST_BIT_LOW;
                        end
                    end

                    ST_ACK_LOW: begin
                        scl <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state <= ST_ACK_HIGH;
                    end

                    ST_ACK_HIGH: begin
                        scl <= 1'b1;
                        if (sda_in !== 1'b0)
                            nack <= 1'b1;

                        if (byte_index == 2'd2)
                            state <= ST_STOP_LOW;
                        else begin
                            byte_index <= byte_index + 2'd1;
                            bit_index <= 3'd7;
                            state <= ST_BIT_LOW;
                        end
                    end

                    ST_STOP_LOW: begin
                        scl <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_HIGH;
                    end

                    ST_STOP_HIGH: begin
                        scl <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_REL;
                    end

                    ST_STOP_REL: begin
                        scl <= 1'b1;
                        sda_drive_low <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
            else begin
                div_count <= div_count + 1'b1;
            end
        end
    end

endmodule
