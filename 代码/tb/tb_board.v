`timescale 1ns/1ps
//=============================================================================
//  tb_board.v : 板级顶层仿真（27 MHz 时钟 + UART 解码 + LED 观察）
//  用法：vvp board.vvp
//=============================================================================
module tb_board;

    localparam CLKS = 234;          // 27 MHz / 115200

    reg clk = 1'b0;
    always #18.5185 clk = ~clk;     // 27 MHz

    reg        rst_n  = 1'b0;       // 板卡可能长期为低，顶层默认内部 POR
    reg        uart_rx = 1'b1;
    wire       uart_tx;
    wire [3:0] led;
    reg  [3:0] key = 4'hF;

    fpga_top #(
        .CLK_HZ(27000000),
        .BAUD  (115200)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .key     (key),
        .led     (led)
    );

    //------------------------- UART 解码 ------------------------------------
    integer ustate = 0;
    integer ucnt   = 0;
    integer ubit   = 0;
    reg [7:0] udata = 8'd0;
    integer nchar  = 0;

    always @(posedge clk) begin
        case (ustate)
            0: if (!uart_tx) begin ustate <= 1; ucnt <= 0; end
            1: begin                    // 起始位，等到中点
                   if (ucnt == CLKS / 2) begin
                       ustate <= 2; ucnt <= 0; ubit <= 0;
                   end else ucnt <= ucnt + 1;
               end
            2: begin                    // 8 个数据位
                   if (ucnt == CLKS - 1) begin
                       udata[ubit] <= uart_tx;
                       ucnt <= 0;
                       if (ubit == 7) ustate <= 3;
                       else           ubit <= ubit + 1;
                   end else ucnt <= ucnt + 1;
               end
            3: begin                    // 停止位
                   if (ucnt == CLKS - 1) begin
                       ustate <= 0; ucnt <= 0;
                       $write("%c", udata);
                       nchar = nchar + 1;
                   end else ucnt <= ucnt + 1;
               end
            default: ustate <= 0;
        endcase
    end

    //------------------------- 超时与结论 -----------------------------------
    integer cyc = 0;
    integer hb_toggles = 0;
    reg led0_q = 1'b1;

    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc == 300000) rst_n <= 1'b1;
        if (led[0] != led0_q) begin
            led0_q <= led[0];
            hb_toggles = hb_toggles + 1;
        end
        if (cyc == 400000) begin
            $display("");
            $display("=================================================");
            $display(" UART chars = %0d", nchar);
            $display(" LED heartbeat toggles = %0d", hb_toggles);
            $display(" LED = %b  (bit3 done, bit2 pass, bit1 key, bit0 hb)", led);
            if (nchar > 0)
                $display(" BOARD SIM PASSED");
            else
                $display(" BOARD SIM: no uart output");
            $display("=================================================");
            $finish;
        end
    end

endmodule
