`timescale 1ns/1ps
//=============================================================================
//  gpio.v : 通用 GPIO（输出 / 输入 / 方向）
//=============================================================================
module gpio (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        we,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_oe
);

    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_out <= 32'd0;
            gpio_oe  <= 32'd0;
        end else if (we) begin
            case (addr)
                2'd0: gpio_out <= wdata;
                2'd2: gpio_oe  <= wdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (addr)
            2'd1: rdata = gpio_in;
            2'd2: rdata = gpio_oe;
            default: rdata = gpio_out;
        endcase
    end

endmodule
