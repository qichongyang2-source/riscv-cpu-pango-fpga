`timescale 1ns/1ps
//=============================================================================
//  timer.v : 64 位机器定时器 (mtime / mtimecmp)，产生 MTIP 电平中断
//=============================================================================
module timer (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        we,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        irq
);

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    always @(posedge clk) begin
        if (!rst_n) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            mtime <= mtime + 64'd1;
            if (we) begin
                case (addr)
                    2'd0: mtime[31:0]  <= wdata;
                    2'd1: mtime[63:32] <= wdata;
                    2'd2: mtimecmp[31:0]  <= wdata;
                    2'd3: mtimecmp[63:32] <= wdata;
                endcase
            end
        end
    end

    always @(*) begin
        case (addr)
            2'd0: rdata = mtime[31:0];
            2'd1: rdata = mtime[63:32];
            2'd2: rdata = mtimecmp[31:0];
            2'd3: rdata = mtimecmp[63:32];
            default: rdata = 32'd0;
        endcase
    end

    assign irq = (mtime >= mtimecmp);

endmodule
