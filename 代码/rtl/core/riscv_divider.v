`timescale 1ns/1ps
//=============================================================================
//  riscv_divider.v : 32 位恢复余数除法器（多周期，32 拍）
//    op: 3'd4 DIV, 3'd5 DIVU, 3'd6 REM, 3'd7 REMU
//    start 为单拍脉冲；busy 期间内核冻结；done 单拍有效，result 同拍有效
//    除零：商 = -1，余数 = 被除数（符合 RISC-V 规范）
//=============================================================================
module riscv_divider (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        flush,      // 指令被冲刷：放弃当前运算
    input  wire        start,
    input  wire [2:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg         busy,
    output reg         done
);

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg        state;
    reg [5:0]  cnt;
    reg [63:0] rq;          // {remainder[31:0], quotient[31:0]}
    reg [31:0] dsor;
    reg [31:0] a_q, b_q;
    reg [2:0]  op_q;
    reg        sign_q, sign_r;

    wire [31:0] a_abs = a[31] ? (~a + 32'd1) : a;
    wire [31:0] b_abs = b[31] ? (~b + 32'd1) : b;

    wire [63:0] sh     = {rq[62:0], 1'b0};
    wire [31:0] r_sh   = sh[63:32];
    wire        ge     = (r_sh >= dsor);
    wire [31:0] r_sub  = r_sh - dsor;
    wire [63:0] rq_nxt = ge ? {r_sub, sh[31:1], 1'b1} : sh;

    wire [31:0] q_raw = rq[31:0];
    wire [31:0] r_raw = rq[63:32];
    wire [31:0] q_sgn = sign_q ? (~q_raw + 32'd1) : q_raw;
    wire [31:0] r_sgn = sign_r ? (~r_raw + 32'd1) : r_raw;

    always @(*) begin
        case (op_q)
            3'd4:    result = (b_q == 32'd0) ? 32'hFFFF_FFFF : q_sgn;   // DIV
            3'd5:    result = (b_q == 32'd0) ? 32'hFFFF_FFFF : q_raw;   // DIVU
            3'd6:    result = (b_q == 32'd0) ? a_q : r_sgn;             // REM
            3'd7:    result = (b_q == 32'd0) ? a_q : r_raw;             // REMU
            default: result = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            cnt    <= 6'd0;
            rq     <= 64'd0;
            dsor   <= 32'd0;
            a_q    <= 32'd0;
            b_q    <= 32'd0;
            op_q   <= 3'd0;
            sign_q <= 1'b0;
            sign_r <= 1'b0;
            busy   <= 1'b0;
            done   <= 1'b0;
        end else if (flush) begin
            state <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        // DIVU/REMU (op[0]=1) 直接使用无符号原值
                        if (op[0]) begin
                            rq     <= {32'd0, a};
                            dsor   <= b;
                            sign_q <= 1'b0;
                            sign_r <= 1'b0;
                        end else begin
                            rq     <= {32'd0, a_abs};
                            dsor   <= b_abs;
                            sign_q <= a[31] ^ b[31];
                            sign_r <= a[31];
                        end
                        a_q    <= a;
                        b_q    <= b;
                        op_q   <= op;
                        cnt    <= 6'd32;
                        busy   <= 1'b1;
                        state  <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (cnt == 6'd0) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        rq  <= rq_nxt;
                        cnt <= cnt - 6'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
