#=============================================================================
#  timing_template.sdc : 紫光同创 PDS 时序约束模板
#   - 输入时钟 50 MHz；若使用 PLL 输出 100 MHz，请按实际频率修改
#=============================================================================

create_clock -name sys_clk -period 20.000 [get_ports clk]

# 输入/输出延迟（按外设实际时序调整，UART 为异步，可设为 false path）
set_input_delay  -clock sys_clk 2.000 [get_ports {uart_rx key[*] rst_n}]
set_output_delay -clock sys_clk 2.000 [get_ports {uart_tx led[*]}]

set_false_path -from [get_ports uart_rx] -to [all_registers]
set_false_path -from [all_registers]     -to [get_ports uart_tx]
set_false_path -from [get_ports {key[*]}]

# 异步复位
set_false_path -from [get_ports rst_n]
