# Run in Questa: cd {F:/DSPFPGA_LAB1/dsp_fpga_lab1_FINAL/dsp_fpga_lab1}
# Then: do tb/run_all_reports.do
# Logs preserve the TB's actual PASS/FAIL text. Runner status is NOT a verdict.
transcript on
set project_root ""
set candidates {}
if {[info script] ne ""} {
    lappend candidates [file normalize [file join [file dirname [file normalize [info script]]] ..]]
}
lappend candidates [file normalize [pwd]] [file normalize [file join [pwd] ..]]
foreach c $candidates {
    if {[file exists [file join $c rtl core sine_gen.v]] && [file isdirectory [file join $c tb]]} {
        set project_root $c
        break
    }
}
if {$project_root eq ""} {
    puts "ERROR: cd to the project root, then do tb/run_all_reports.do"
    return
}

# Keep generated work library and LUT copies in a NEW run directory.
# No existing work library or LUT files are deleted.
set saved_dir [pwd]
set run_stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set report_base [file join $project_root reports "questa_$run_stamp"]
set report_dir $report_base
set suffix 0
while {[file exists $report_dir]} {
    incr suffix
    set report_dir "${report_base}_$suffix"
}
file mkdir $report_dir
cd $report_dir
set main_log [file join $report_dir 00_compile_and_runner.log]
transcript file $main_log
transcript on
puts "PROJECT: $project_root"
puts "REPORT DIRECTORY: $report_dir"

set tests {
    {tb_sine_gen tb_sine_gen.v}
    {tb_ecg_gen tb_ecg_gen.sv}
    {tb_square_gen tb_square_gen.sv}
    {tb_triangle_gen tb_triangle_gen.sv}
    {tb_sawtooth_gen tb_sawtooth_gen.sv}
    {tb_lfsr_noise tb_lfsr_noise.sv}
    {tb_noise_mixer tb_noise_mixer.sv}
    {tb_debounce tb_debounce.sv}
    {tb_lab1_signal_core tb_lab1_signal_core.sv}
    {tb_wm8731_i2s_tx tb_wm8731_i2s_tx.sv}
    {tb_wm8731_i2s_data tb_wm8731_i2s_data.sv}
    {tb_wm8731_config tb_wm8731_config.sv}
    {tb_lab1_top tb_lab1_top.sv}
}

set rtl_files {}
foreach rel {
    rtl/core/button_pulse.v rtl/core/freq_ctrl.v
    rtl/core/amp_ctrl.v rtl/core/amp_scaler.v
    rtl/core/sine_gen.v rtl/core/ecg_gen.v
    rtl/core/sine_gen_top.v rtl/core/ecg_gen_top.v
    rtl/basic/square_gen.sv rtl/basic/triangle_gen.sv
    rtl/basic/sawtooth_gen.sv rtl/common/lfsr_noise.sv
    rtl/common/noise_mixer.sv rtl/common/debounce.sv
    rtl/common/toggle_sync_pulse.sv rtl/common/sync_bus_2ff.sv
    rtl/common/lab1_signal_core.sv rtl/common/wm8731_i2s_tx.sv
    rtl/common/i2c_master_write.sv rtl/common/wm8731_config.sv
    rtl/common/top.v tb/audio_pll_sim.v
} {
    lappend rtl_files [file join $project_root $rel]
}

# CSV records execution stages only; actual functional verdicts are in TB logs.
set summary [open [file join $report_dir runner_summary.csv] w]
puts $summary "testbench,runner_status,functional_result,log_file"
flush $summary
set setup_error [catch {
    foreach lut {sine_lut.hex ecg_lut.hex} {
        file copy [file join $project_root rtl core $lut] [file join $report_dir $lut]
    }
    vlib work
    vmap work [file join $report_dir work]
    vlog -sv {*}$rtl_files
} setup_message]

if {$setup_error} {
    puts "SETUP_OR_RTL_COMPILE_ERROR: $setup_message"
    foreach item $tests {
        set tb_name [lindex $item 0]
        puts $summary "$tb_name,NOT_RUN_SETUP_ERROR,NOT_EVALUATED,00_compile_and_runner.log"
    }
} else {
    foreach item $tests {
        set tb_name [lindex $item 0]
        set tb_file [file join $project_root tb [lindex $item 1]]
        set tb_log [file join $report_dir "${tb_name}.log"]
        transcript off
        transcript file $tb_log
        transcript on
        puts "============================================================"
        puts "TESTBENCH: $tb_name"
        puts "SOURCE: $tb_file"
        puts "START: [clock format [clock seconds]]"
        set runner_status MISSING_TB_FILE
        if {![file exists $tb_file]} {
            puts "ERROR: missing $tb_file"
        } elseif {[catch {vlog -sv $tb_file} message]} {
            set runner_status TB_COMPILE_ERROR
            puts "TB_COMPILE_ERROR: $message"
        } elseif {[catch {vsim work.$tb_name} message]} {
            set runner_status LOAD_ERROR
            puts "LOAD_ERROR: $message"
            catch {quit -sim}
        } else {
            onfinish stop
            if {[catch {run -all} message]} {
                set runner_status RUN_ERROR
                puts "RUN_ERROR: $message"
            } else {
                # May have stopped on $finish, $stop, an assertion or a breakpoint.
                # A return from run is not sufficient evidence of functional PASS.
                set runner_status RUN_RETURNED
            }
            catch {quit -sim}
        }
        puts "RUNNER_STATUS: $runner_status"
        puts "FUNCTIONAL RESULT: read this TB's PASS/FAIL and final summary above."
        puts "END: [clock format [clock seconds]]"
        transcript off
        transcript file $main_log
        transcript on
        puts "${tb_name}: $runner_status; log: $tb_log"
        puts $summary "$tb_name,$runner_status,REVIEW_TB_LOG,${tb_name}.log"
        flush $summary
    }
}
close $summary
puts "REPORT DIRECTORY: $report_dir"
puts "Runner finished. RUN_RETURNED is NOT the same as functional PASS."
puts "This script does not add or invent PASS/FAIL counts."
puts "If run -all never returns, use Break and inspect the current TB log."
transcript off
cd $saved_dir
