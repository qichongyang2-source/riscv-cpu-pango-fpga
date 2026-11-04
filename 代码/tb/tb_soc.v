//=============================================================================
//  tb_soc.v : SoC 自检测试平台
//  运行目录下需有 imem.hex / dmem.hex
//  支持 plusargs: +VCD +TRACE +MAX=<cycles>
//=============================================================================
`timescale 1ns/1ps

module tb_soc;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         uart_rx = 1'b1;
    wire        uart_tx;
    wire [31:0] gpio_out, gpio_oe;
    reg  [31:0] gpio_in = 32'd0;
    wire        test_done, test_pass;
    wire [31:0] test_code;
    wire [31:0] dbg_pc;

    soc_top #(
        .IMEM_FILE("imem.hex"),
        .DMEM_FILE("dmem.hex")
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_tx  (uart_tx),
        .uart_rx  (uart_rx),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe),
        .gpio_in  (gpio_in),
        .test_done(test_done),
        .test_pass(test_pass),
        .test_code(test_code),
        .dbg_pc   (dbg_pc)
    );

    always #10 clk = ~clk;      // 50 MHz

    integer max_cycles = 200000;
    integer cycle_cnt  = 0;
    integer commit_cnt = 0;
    integer dump_i = 0;

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("tb_soc.vcd");
            $dumpvars(0, tb_soc);
        end
        if ($value$plusargs("MAX=%d", max_cycles)) ;
        #200 rst_n = 1'b1;
        $display("[%0t] reset released", $time);
    end

    //------------------------- UART 解码（+UART） ---------------------------
    integer u_state = 0;
    integer u_cnt = 0;
    integer u_bit = 0;
    reg [7:0] u_byte = 8'd0;

    always @(posedge clk) begin
        if ($test$plusargs("UART")) begin
            case (u_state)
                0: if (!uart_tx) begin
                       u_state <= 1; u_cnt <= 0;
                   end
                1: begin
                       u_cnt <= u_cnt + 1;
                       if (u_cnt == 7) begin
                           u_state <= 2; u_cnt <= 0; u_bit <= 0;
                       end
                   end
                2: begin
                       u_cnt <= u_cnt + 1;
                       if (u_cnt == 15) begin
                           u_byte[u_bit] <= uart_tx;
                           u_cnt <= 0;
                           if (u_bit == 7) u_state <= 3;
                           else            u_bit <= u_bit + 1;
                       end
                   end
                3: begin
                       u_cnt <= u_cnt + 1;
                       if (u_cnt == 15) begin
                           $write("%c", u_byte);
                           u_state <= 0; u_cnt <= 0;
                       end
                   end
            endcase
        end
    end

    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
        if (rst_n === 1'b1) begin
            if (dut.u_core.commit_valid) begin
                commit_cnt <= commit_cnt + 1;
                if ($test$plusargs("TRACE"))
                    $display("[%0t] cyc=%0d pc=%08h inst=%08h",
                             $time, cycle_cnt, dut.u_core.commit_pc, dut.u_core.commit_instr);
            end
            if ($test$plusargs("WBTRACE") && dut.u_core.rf_we)
                $display("[%0t] WB  x%0d <= %08h (pc=%08h)", $time,
                         dut.u_core.rf_waddr, dut.u_core.rf_wdata, dut.u_core.memwb_pc);
            if ($test$plusargs("EXTRACE") && dut.u_core.idex_valid)
                $display("[%0t] EX pc=%08h rs1=%0d/%08h rs2=%0d/%08h fwd=%b%b y=%08h rd=%0d wr=%b",
                         $time, dut.u_core.idex_pc,
                         dut.u_core.idex_rs1, dut.u_core.ex_src1,
                         dut.u_core.idex_rs2, dut.u_core.ex_src2,
                         dut.u_core.fwd_a, dut.u_core.fwd_b,
                         dut.u_core.ex_alu_y, dut.u_core.idex_rd, dut.u_core.idex_reg_write);
        end

        if (test_done) begin
            if ($test$plusargs("STATS")) begin
                $display("  ICACHE hits=%0d misses=%0d", dut.u_icache.hit_cnt, dut.u_icache.miss_cnt);
                $display("  DCACHE hits=%0d misses=%0d", dut.u_dcache.hit_cnt, dut.u_dcache.miss_cnt);
            end
            if ($test$plusargs("DUMP")) begin
                for (dump_i = 0; dump_i < 16; dump_i = dump_i + 1)
                    $display("  DMEM[%0d] = %08h", dump_i, dut.u_dmem.mem[dump_i]);
            end
            if (test_pass) begin
                $display("=================================================");
                $display(" TEST PASSED  (cycles=%0d, commits=%0d)", cycle_cnt, commit_cnt);
                $display("=================================================");
            end else begin
                $display("=================================================");
                $display(" TEST FAILED  code=%0d (cycles=%0d, pc=%08h)",
                         test_code, cycle_cnt, dbg_pc);
                $display("=================================================");
            end
            $finish;
        end

        if (cycle_cnt > max_cycles) begin
            $display("=================================================");
            $display(" TIMEOUT after %0d cycles, pc=%08h", cycle_cnt, dbg_pc);
            $display("=================================================");
            $finish;
        end
    end

endmodule
