# 🚀 EE3041 - DSP ON FPGA: LAB 1 - WAVEFORM GENERATOR

Repository dự án Lab 1: Bộ tạo dạng sóng (Waveform Generator). 
Vui lòng đọc kỹ tài liệu này trước khi bắt đầu viết code để nắm rõ mục tiêu, kiến trúc hệ thống và quy trình làm việc chung.

---

## 📌 1. TỔNG QUAN DỰ ÁN (LAB OVERVIEW)

### 🎯 Mục tiêu
Thiết kế và triển khai một Bộ tạo dạng sóng số (Digital Waveform Generator) trên kit DE10-Standard FPGA.
Hệ thống có khả năng:
1. Tạo ra các loại sóng: Sin, Vuông, Tam giác, Răng cưa, ECG (Điện tim).
2. Điều chỉnh trực tiếp các thông số: Tần số (Frequency), Biên độ (Amplitude), Chu kỳ làm việc (Duty Cycle) bằng công tắc/nút bấm vật lý.
3. Bơm nhiễu ngẫu nhiên (Noise Injection) vào sóng gốc (sử dụng LFSR) – đây là tiền đề bắt buộc cho Lab 2 (Lọc nhiễu).
4. Xuất dữ liệu âm thanh 24-bit qua Audio CODEC (WM8731) ra jack 3.5mm để hiển thị lên Oscilloscope.

---

## 🏗️ 2. KIẾN TRÚC HỆ THỐNG & CHUẨN GIAO TIẾP (SYSTEM ARCHITECTURE)

Để các khối do từng cá nhân viết có thể ghép nối hoàn hảo với nhau tại file Top-level, tất cả mọi người BẮT BUỘC tuân thủ chuẩn giao tiếp sau:

- System Clock: 50 MHz (Tín hiệu clock chuẩn trên kit DE10-Standard).
- Reset Signal: rst_n (Tích cực mức thấp 0).
- Data Output Width: Tín hiệu ngõ ra của MỌI module tạo sóng và bộ trộn nhiễu bắt buộc phải là signed 24-bit (logic signed [23:0] wave_out).
- Nguồn tài liệu tham khảo: https://doelab.github.io/categories/ee3041-dsp-on-fpga-big-project/

---

## 👥 3. PHÂN CÔNG NHIỆM VỤ (TASK ASSIGNMENT)

Mỗi thành viên phụ trách một khối công việc cụ thể. Hãy đảm bảo bạn hoàn thành công việc đúng hạn để nhóm kịp tiến độ.

### 🟡 Thành viên 1: Core Waves (Sóng phức tạp)
- Thư mục làm việc: rtl/core/ và tb/
- Nhiệm vụ:
  - Thiết kế module tạo sóng Sin và sóng ECG (sử dụng phương pháp DDS/NCO kết hợp Lookup Table ROM).
  - Tích hợp khả năng thay đổi Tần số và Biên độ đầu ra.
  - Viết Testbench mô phỏng dạng sóng trên ModelSim/Icarus/Quartus, chụp ảnh màn hình Waveform làm minh chứng.

### 🔵 Thành viên 2: Basic Waves & Noise (Sóng cơ bản & Nhiễu)
- Thư mục làm việc: rtl/basic/, rtl/common/ và tb/
- Nhiệm vụ:
  - Thiết kế module tạo sóng Vuông (có chỉnh Duty Cycle), Tam giác, và Răng cưa bằng bộ đếm (Counters/Accumulators).
  - Thiết kế bộ tạo số ngẫu nhiên giả LFSR (Linear Feedback Shift Register) để làm nguồn nhiễu.
  - Thiết kế bộ cộng/trộn tín hiệu (Mixer/Adder) để cộng nhiễu vào sóng gốc.
  - Viết Testbench mô phỏng kiểm tra sóng và nhiễu, chụp ảnh Waveform minh chứng.

### 🔴 Thành viên 3: Hardware Interface & System Integration (Phần cứng & Tích hợp)
- Thư mục làm việc: rtl/common/, quartus/ và tb/
- Nhiệm vụ:
  - Thiết kế khối Debounce (chống dội) cho phím bấm/switch vật lý trên kit.
  - Trích xuất và cấu hình khối Driver giao tiếp WM8731 Audio CODEC từ repo chính của môn học (xuất data 24-bit ra cổng Line-Out/Headphone).
  - Viết file top.v kết nối tất cả các khối từ Thành viên 1 và Thành viên 2 thành hệ thống hoàn chỉnh.
  - Khởi tạo project Quartus Prime, gán chân (Pin assignments) cho DE10-Standard, chạy Tổng hợp mạch (Synthesis) và biên dịch ra file nạp (.sof).
  - Trích xuất báo cáo tài nguyên (Utilization), tần số tối đa (fmax) và kiểm tra lỗi timing gửi cho Leader.

### 🟢 Leader: Project Management & QA Report
- Nhiệm vụ:
  - Quản lý tiến độ dự án, thiết lập giao thức I/O chuẩn cho 3 thành viên kỹ thuật.
  - Kiểm duyệt chất lượng code, đối chiếu kết quả mô phỏng Waveform của TV1, TV2 và báo cáo tổng hợp Quartus của TV3.
  - Biên soạn toàn bộ Báo cáo tổng hợp (Report PDF) chất lượng cao theo yêu cầu của môn học.
  - Điều phối và tổ chức buổi lên Lab nạp kit, đo kiểm thực tế trên Oscilloscope và chuẩn bị nội dung demo.

---

## 🔄 4. QUY TRÌNH LÀM VIỆC & PUSH CODE (WORKFLOW GUIDELINES)

Mọi thành viên hãy tuân thủ 4 bước làm việc chuẩn sau:

### Bước 1: Khởi tạo & Lấy code mới nhất
Trước khi bắt đầu làm việc, luôn kéo code mới nhất từ GitHub về máy bằng lệnh:
git pull origin main

### Bước 2: Lập trình & Chạy mô phỏng (BẮT BUỘC)
- Viết code Verilog/SystemVerilog trong đúng thư mục được phân công.
- KHÔNG push code chưa qua mô phỏng. Hãy chạy Testbench trên ModelSim/Icarus Verilog để chắc chắn module của bạn xuất đúng dạng sóng.
- Chụp lại ảnh màn hình kết quả mô phỏng (Waveform) và lưu vào thư mục doc/.

### Bước 3: Commit code theo cú pháp chuẩn
Khi code đã chạy đúng, thực hiện commit kèm lời nhắn rõ ràng:
git add .
git commit -m "feat(core): hoan thanh module song sin dung DDS"

(Cú pháp gợi ý: feat(...) cho chức năng mới, fix(...) cho sửa lỗi, test(...) cho file testbench)

### Bước 4: Push code lên GitHub & Cập nhật Báo cáo
git push origin main

Sau khi push code thành công, hãy dán hình ảnh mô phỏng Waveform và mô tả ngắn gọn nguyên lý hoạt động vào file Google Docs Báo cáo chung của nhóm.

---

## 📂 5. CẤU TRÚC THƯ MỤC CỦA REPOSITORY

* dsp_fpga_lab1/
  * rtl/ (Tất cả mã nguồn Verilog/SystemVerilog)
    * core/ ([TV1] Sóng Sin, ECG - DDS, ROM)
    * basic/ ([TV2] Sóng Vuông, Tam giác, Răng cưa)
    * common/ ([TV2 & TV3] LFSR Noise, Debounce, Mixer, CODEC Driver, top.v)
  * tb/ (Các file Testbench mô phỏng .v / .sv)
  * quartus/ (Project Quartus Prime, Pin assignments, File nạp .sof - [TV3])
  * doc/ (Tài liệu tham khảo, Datasheets, Ảnh chụp Waveform mô phỏng)
  * README.md (File hướng dẫn dự án)

---
