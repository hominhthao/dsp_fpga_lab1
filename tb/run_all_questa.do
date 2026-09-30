transcript on

set project_root "F:/DSPFPGA_LAB1/dsp_fpga_lab1"
set sim_dir "$project_root/quartus"

if {![file exists "$project_root/rtl/core/sine_gen.v"]} {
    puts "LOI: Khong tim thay rtl/core/sine_gen.v"
    puts "Kiem tra lai duong dan project."
    return
}

if {![file exists "$project_root/rtl/core/ecg_gen.v"]} {
    puts "LOI: Khong tim thay rtl/core/ecg_gen.v"
    return
}

if {![file exists "$project_root/tb"]} {
    puts "LOI: Khong tim thay thu muc tb."
    return
}

if {![file exists "$sim_dir"]} {
    puts "LOI: Khong tim thay thu muc quartus."
    return
}

cd $sim_dir

# Copy LUT tam de code TV1 doc dung file khi mo phong
file copy -force \
    "$project_root/rtl/core/sine_lut.hex" \
    "$sim_dir/sine_lut.hex"

file copy -force \
    "$project_root/rtl/core/ecg_lut.hex" \
    "$sim_dir/ecg_lut.hex"

# Tao lai thu vien work
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

puts ""
puts "BIEN DICH RTL"

# Bien dich code TV1, TV2 va cac khoi tich hop
if {[catch {

    vlog -sv \
        "$project_root/rtl/core/button_pulse.v" \
        "$project_root/rtl/core/freq_ctrl.v" \
        "$project_root/rtl/core/amp_ctrl.v" \
        "$project_root/rtl/core/amp_scaler.v" \
        "$project_root/rtl/core/sine_gen.v" \
        "$project_root/rtl/core/ecg_gen.v" \
        "$project_root/rtl/core/sine_gen_top.v" \
        "$project_root/rtl/core/ecg_gen_top.v" \
        "$project_root/rtl/basic/square_gen.sv" \
        "$project_root/rtl/basic/triangle_gen.sv" \
        "$project_root/rtl/basic/sawtooth_gen.sv" \
        "$project_root/rtl/common/lfsr_noise.sv" \
        "$project_root/rtl/common/noise_mixer.sv" \
        "$project_root/rtl/common/debounce.sv" \
        "$project_root/rtl/common/toggle_sync_pulse.sv" \
        "$project_root/rtl/common/sync_bus_2ff.sv" \
        "$project_root/rtl/common/lab1_signal_core.sv" \
        "$project_root/rtl/common/wm8731_i2s_tx.sv"

} result]} {

    puts ""
    puts "LOI BIEN DICH RTL"
    puts "$result"
    return
}

puts "Bien dich RTL thanh cong."

# TV1, TV2 va TV3 dung cac testbench da cap nhat theo kien truc final
set tests {
    {tb_sine_gen         tb_sine_gen.v}
    {tb_ecg_gen          tb_ecg_gen.sv}
    {tb_square_gen       tb_square_gen.sv}
    {tb_triangle_gen     tb_triangle_gen.sv}
    {tb_sawtooth_gen     tb_sawtooth_gen.sv}
    {tb_lfsr_noise       tb_lfsr_noise.sv}
    {tb_noise_mixer      tb_noise_mixer.sv}
    {tb_debounce         tb_debounce.sv}
    {tb_lab1_signal_core tb_lab1_signal_core.sv}
    {tb_wm8731_i2s_tx    tb_wm8731_i2s_tx.sv}
}

foreach item $tests {

    set tb_name   [lindex $item 0]
    set file_name [lindex $item 1]
    set tb_file   "$project_root/tb/$file_name"

    puts ""
    puts "CHAY $tb_name"

    if {![file exists "$tb_file"]} {
        puts "LOI: Khong tim thay $tb_file"
        return
    }

    # Bien dich testbench
    if {[catch {
        vlog -sv "$tb_file"
    } result]} {

        puts "LOI BIEN DICH TESTBENCH: $tb_name"
        puts "$result"
        return
    }

    # Khong dung +acc khi chay toan bo de giam RAM
    if {[catch {
        vsim work.$tb_name
    } result]} {

        puts "LOI KHI NAP MO PHONG: $tb_name"
        puts "$result"
        return
    }

    # $finish chi dung simulation, khong hien hop thoai xac nhan
    onfinish stop

    if {[catch {
        run -all
    } result]} {

        puts "LOI KHI CHAY MO PHONG: $tb_name"
        puts "$result"
        quit -sim
        return
    }

    # Dong simulation hien tai de chay testbench tiep theo
    # Lenh nay khong dong phan mem Questa
    quit -sim
}

# Xoa LUT tam sau khi chay xong
if {[file exists "$sim_dir/sine_lut.hex"]} {
    file delete -force "$sim_dir/sine_lut.hex"
}

if {[file exists "$sim_dir/ecg_lut.hex"]} {
    file delete -force "$sim_dir/ecg_lut.hex"
}

puts ""
puts "DA CHAY XONG TOAN BO TESTBENCH."
puts "Kiem tra cac dong PASS, FAIL va TONG KET o tren."