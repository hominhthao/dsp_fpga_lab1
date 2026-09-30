module ecg_gen (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_en,
    input  wire [31:0]        phase_inc,

    output reg signed [23:0]  ecg_data
);


    reg [31:0] phase;


    reg signed [23:0] ecg_lut [0:255];
	 

    wire [7:0] lut_addr;

    assign lut_addr = phase[31:24];


    initial begin
        $readmemh("ecg_lut.hex", ecg_lut);
    end


    always @(posedge clk) begin

        if (rst) begin

            phase    <= 32'd0;
            ecg_data <= 24'sd0;

        end

        else if (sample_en) begin

            phase <= phase + phase_inc;

            ecg_data <= ecg_lut[lut_addr];

        end

    end

endmodule
