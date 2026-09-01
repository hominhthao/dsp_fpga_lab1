# EE3041 - DSP on FPGA: Lab 1 Waveform Generator

Dự án thiết kế Bộ tạo sóng (Sine, Square, Triangle, Sawtooth, ECG, Noise) trên kit FPGA DE10-Standard.

---

## 📂 Hướng dẫn cấu trúc thư mục (Repository Structure)

Các thành viên vui lòng lưu trữ tệp đúng vào các thư mục được phân công dưới đây:

```text
dsp_fpga_lab1/
├── rtl/                        # Chứa toàn bộ mã nguồn Thiết kế (Hardware Description Language)
│   ├── core/                   # [Thành viên 1] Chứa code sóng Sin & ECG (DDS, ROM/LUT)
│   ├── basic/                  # [Thành viên 2] Chứa code sóng Vuông, Tam giác, Răng cưa
│   └── common/                 # [Thành viên 3 & Leader] Chứa bộ tạo nhiễu LFSR, Debounce, Mixer, CODEC Driver
│
├── tb/                         # Chứa các tệp Testbench phục vụ mô phỏng trên ModelSim/Icarus
│
├── quartus/                    # Chứa project Quartus Prime (.qpf, .qsf), file gán chân (Pinout) và file nạp (.sof)
│
└── doc/                        # Chứa tài liệu tham khảo, Datasheet và ảnh chụp Waveform/Oscilloscope# DSP FPGA Lab 1 - Waveform Generator
