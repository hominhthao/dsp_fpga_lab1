//=============================================================================
// ecg_gen.v  -  ECG DDS + LUT 256 diem + NOI SUY TUYEN TINH
//
//   phase[31:24] = dia chi LUT (addr)
//   phase[23:16] = phan le giua 2 diem LUT (frac, 0..255)
//
//   ecg = a + ((b - a) * frac) >>> 8      voi a = LUT[addr], b = LUT[addr+1]
//
// Ly do: o 60 BPM moi diem LUT duoc giu 3.9 ms (~187 mau) -> song bac thang,
// buoc nhay ~13% dinh o 2 suon song R. Noi suy chia moi bac thanh 256 buoc nho
// (~15 us < 1 chu ky mau 20.8 us) -> moi mau ra deu khac nhau, song muot.
//
// Pipeline 2 tang (deu tren clk, chi chay khi co sample_en):
//   Tang 1 (sample_en)  : phase += phase_inc ; chot a, b, frac  (ROM doc 2 cong)
//   Tang 2 (sample_en_d): ecg_data <= a + ((b-a)*frac) >>> 8    (1 khoi DSP)
// Tach 2 tang de phep nhan noi suy KHONG noi tiep voi phep nhan bien do
// (amp_scaler) trong cung 1 chu ky -> khong lam giam Fmax.
// Do tre: ecg_data cap nhat 1 chu ky CLOCK_50 sau sample_en, nen top chot
// gia tri cua mau truoc (tre 1 mau = 20.8 us, khong anh huong dang song).
//=============================================================================
module ecg_gen (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_en,
    input  wire [31:0]        phase_inc,

    output reg signed [23:0]  ecg_data
);

    reg [31:0] phase;

    reg signed [23:0] ecg_lut [0:255];

    initial begin
        $readmemh("ecg_lut.hex", ecg_lut);
    end

    wire [7:0] addr_a = phase[31:24];
    wire [7:0] addr_b = phase[31:24] + 8'd1;   // 255 + 1 -> 0 (vong lai dau chu ky)

    // ---------------- Tang 1: doc 2 diem LUT ----------------
    reg signed [23:0] lut_a;
    reg signed [23:0] lut_b;
    reg        [7:0]  frac;
    reg               sample_en_d;

    always @(posedge clk) begin
        if (rst) begin
            phase       <= 32'd0;
            lut_a       <= 24'sd0;
            lut_b       <= 24'sd0;
            frac        <= 8'd0;
            sample_en_d <= 1'b0;
        end
        else begin
            sample_en_d <= sample_en;
            if (sample_en) begin
                phase <= phase + phase_inc;
                lut_a <= ecg_lut[addr_a];
                lut_b <= ecg_lut[addr_b];
                frac  <= phase[23:16];
            end
        end
    end

    // ---------------- Tang 2: noi suy ----------------
    // diff 25 bit co dau, frac 9 bit co dau (bit dau = 0) -> tich 34 bit.
    // Ket qua luon nam giua a va b nen khong the tran 24 bit.
    wire signed [24:0] diff = {lut_b[23], lut_b} - {lut_a[23], lut_a};
    wire signed [33:0] prod = diff * $signed({1'b0, frac});
    wire signed [24:0] interp = {lut_a[23], lut_a} + (prod >>> 8);

    always @(posedge clk) begin
        if (rst)
            ecg_data <= 24'sd0;
        else if (sample_en_d)
            ecg_data <= interp[23:0];
    end

endmodule
