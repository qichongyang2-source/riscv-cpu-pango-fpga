`timescale 1ns/1ps
//=============================================================================
//  ai_accel.v : INT8 matrix-vector accelerator (memory mapped)
//
//  Register space 0x2000_4000  (reg_idx = addr[7:2])
//    0  CTRL   W: bit0=start, bit1=clear done    R: bit0=busy, bit1=done
//    1  OP     W: 0=FC, 1=RELU, 2=ARGMAX
//    2  K      inner length (FC)
//    3  N      element count (RELU / ARGMAX)
//    4  WA     weight byte offset (4-byte aligned, K x 4 INT8, row major)
//    5  XA     input byte offset (K INT8)
//    6  YA     output byte offset (N INT32)
//    8  CYC    R: cycles of last op
//    9  ARG    R: ARGMAX result
//
//  Buffer 0x2000_8000 - 0x2000_9FFF (8 KB, 2048 x 32)
//
//  FC     : y[j] = sum_k W[k][j] * x[k], 4 outputs per run, INT8 x INT8 -> INT32
//           (bias is folded into an extra row of W with x set to 1)
//  RELU   : in-place ReLU on N INT32 words at YA
//  ARGMAX : index of max over N INT32 words at YA
//=============================================================================
module ai_accel #(
    parameter LANES = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cs_reg,
    input  wire        cs_buf,
    input  wire [7:0]  reg_idx,
    input  wire [10:0] buf_idx,
    input  wire        we,
    input  wire [3:0]  be,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        busy,
    output wire        done
);

    //--------------------- local buffer --------------------------------------
    reg [31:0] abuf [0:2047];

    reg  [31:0] cfg_op, cfg_k, cfg_n, cfg_wa, cfg_xa, cfg_ya;
    reg  [31:0] cyc_cnt, arg_val;
    reg         op_busy, done_r;

    assign busy = op_busy;
    assign done = done_r;

    //--------------------- states --------------------------------------------
    localparam S_IDLE = 3'd0;
    localparam S_FC   = 3'd1;
    localparam S_WR   = 3'd2;
    localparam S_RELU = 3'd3;
    localparam S_ARG  = 3'd4;
    localparam S_FIN  = 3'd5;

    localparam OP_FC     = 4'd0;
    localparam OP_RELU   = 4'd1;
    localparam OP_ARGMAX = 4'd2;

    reg  [2:0]  state;
    reg  [31:0] k_cnt, wr_cnt, elem_cnt;
    reg signed [63:0] acc0, acc1, acc2, acc3;
    reg  [31:0] max_val, max_idx;

    //--------------------- engine addressing ---------------------------------
    wire [10:0] fc_w_addr = cfg_wa[12:2] + k_cnt[10:0];
    wire [10:0] fc_x_addr = (cfg_xa + k_cnt) >> 2;
    wire [1:0]  fc_x_lane = (cfg_xa + k_cnt) & 3;
    wire [10:0] wr_addr   = cfg_ya[12:2] + wr_cnt[10:0];
    wire [10:0] el_addr   = cfg_ya[12:2] + elem_cnt[10:0];

    reg  [10:0] eng_addr;
    always @(*) begin
        case (state)
            S_FC:          eng_addr = fc_w_addr;
            S_WR:          eng_addr = wr_addr;
            S_RELU, S_ARG: eng_addr = el_addr;
            default:       eng_addr = buf_idx;
        endcase
    end

    wire [10:0] a_addr = op_busy ? eng_addr : buf_idx;
    wire        eng_wr = op_busy && ((state == S_WR) || (state == S_RELU));
    wire        a_we   = eng_wr || (!op_busy && cs_buf && we);

    wire [31:0] port_a_rdata = abuf[a_addr];
    wire [31:0] port_b_rdata = abuf[fc_x_addr];

    wire signed [63:0] w0 = {{32{port_a_rdata[7]}},  port_a_rdata[7:0]};
    wire signed [63:0] w1 = {{32{port_a_rdata[15]}}, port_a_rdata[15:8]};
    wire signed [63:0] w2 = {{32{port_a_rdata[23]}}, port_a_rdata[23:16]};
    wire signed [63:0] w3 = {{32{port_a_rdata[31]}}, port_a_rdata[31:24]};

    wire [7:0] xb_byte = port_b_rdata[{fc_x_lane, 3'b000} +: 8];
    wire signed [63:0] xb = {{56{xb_byte[7]}}, xb_byte};

    wire signed [63:0] p0 = w0 * xb;
    wire signed [63:0] p1 = w1 * xb;
    wire signed [63:0] p2 = w2 * xb;
    wire signed [63:0] p3 = w3 * xb;

    wire [31:0] acc_sel = (wr_cnt == 32'd0) ? acc0[31:0] :
                          (wr_cnt == 32'd1) ? acc1[31:0] :
                          (wr_cnt == 32'd2) ? acc2[31:0] : acc3[31:0];

    wire [31:0] a_wdata = eng_wr ? ((state == S_RELU)
                                     ? (port_a_rdata[31] ? 32'd0 : port_a_rdata)
                                     : acc_sel)
                                  : wdata;
    wire [3:0]  a_be = eng_wr ? 4'b1111 : be;

    always @(posedge clk) begin
        if (a_we) begin
            if (a_be[0]) abuf[a_addr][7:0]   <= a_wdata[7:0];
            if (a_be[1]) abuf[a_addr][15:8]  <= a_wdata[15:8];
            if (a_be[2]) abuf[a_addr][23:16] <= a_wdata[23:16];
            if (a_be[3]) abuf[a_addr][31:24] <= a_wdata[31:24];
        end
    end

    //--------------------- register read ------------------------------------
    always @(*) begin
        if (cs_buf)
            rdata = port_a_rdata;
        else if (cs_reg) begin
            case (reg_idx[3:0])
                4'd0:    rdata = {30'd0, done_r, op_busy};
                4'd1:    rdata = cfg_op;
                4'd2:    rdata = cfg_k;
                4'd3:    rdata = cfg_n;
                4'd4:    rdata = cfg_wa;
                4'd5:    rdata = cfg_xa;
                4'd6:    rdata = cfg_ya;
                4'd8:    rdata = cyc_cnt;
                4'd9:    rdata = arg_val;
                default: rdata = 32'd0;
            endcase
        end else
            rdata = 32'd0;
    end

`ifdef AIDBG
    always @(posedge clk) begin
        if (op_busy && (state == S_FC) && (k_cnt < 32'd4))
            $display("[fc] k=%0d w=%08h xr=%08h b0=%08h b1568=%08h", k_cnt, port_a_rdata, port_b_rdata, abuf[0], abuf[1568]);
    end
`endif

    //--------------------- control FSM --------------------------------------
    wire start = cs_reg && we && (reg_idx[3:0] == 4'd0) && wdata[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            op_busy  <= 1'b0;
            done_r   <= 1'b0;
            k_cnt    <= 32'd0;
            wr_cnt   <= 32'd0;
            elem_cnt <= 32'd0;
            acc0     <= 64'sd0;
            acc1     <= 64'sd0;
            acc2     <= 64'sd0;
            acc3     <= 64'sd0;
            cyc_cnt  <= 32'd0;
            arg_val  <= 32'd0;
            max_val  <= 32'h8000_0000;
            max_idx  <= 32'd0;
            cfg_op   <= 32'd0;
            cfg_k    <= 32'd0;
            cfg_n    <= 32'd0;
            cfg_wa   <= 32'd0;
            cfg_xa   <= 32'd0;
            cfg_ya   <= 32'd0;
        end else begin
            if (cs_reg && we) begin
                case (reg_idx[3:0])
                    4'd0: if (wdata[1]) done_r <= 1'b0;
                    4'd1: cfg_op <= wdata;
                    4'd2: cfg_k  <= wdata;
                    4'd3: cfg_n  <= wdata;
                    4'd4: cfg_wa <= wdata;
                    4'd5: cfg_xa <= wdata;
                    4'd6: cfg_ya <= wdata;
                    default: ;
                endcase
            end

            case (state)
                S_IDLE: begin
                    if (start) begin
                        op_busy  <= 1'b1;
                        done_r   <= 1'b0;
                        cyc_cnt  <= 32'd0;
                        k_cnt    <= 32'd0;
                        wr_cnt   <= 32'd0;
                        elem_cnt <= 32'd0;
                        acc0 <= 64'sd0;
                        acc1 <= 64'sd0;
                        acc2 <= 64'sd0;
                        acc3 <= 64'sd0;
                        max_val <= 32'h8000_0000;
                        max_idx <= 32'd0;
                        case (cfg_op[3:0])
                            OP_FC:     state <= S_FC;
                            OP_RELU:   state <= S_RELU;
                            OP_ARGMAX: state <= S_ARG;
                            default:   state <= S_FIN;
                        endcase
                    end
                end

                S_FC: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    acc0 <= acc0 + p0;
                    acc1 <= acc1 + p1;
                    acc2 <= acc2 + p2;
                    acc3 <= acc3 + p3;
                    if (k_cnt + 32'd1 >= cfg_k)
                        state <= S_WR;
                    else
                        k_cnt <= k_cnt + 32'd1;
                end

                S_WR: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if (wr_cnt == 32'd3)
                        state <= S_FIN;
                    else
                        wr_cnt <= wr_cnt + 32'd1;
                end

                S_RELU: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if (elem_cnt + 32'd1 >= cfg_n)
                        state <= S_FIN;
                    else
                        elem_cnt <= elem_cnt + 32'd1;
                end

                S_ARG: begin
                    cyc_cnt <= cyc_cnt + 32'd1;
                    if ($signed(port_a_rdata) > $signed(max_val)) begin
                        max_val <= port_a_rdata;
                        max_idx <= elem_cnt;
                    end
                    if (elem_cnt + 32'd1 >= cfg_n) begin
                        arg_val <= ($signed(port_a_rdata) > $signed(max_val)) ? elem_cnt : max_idx;
                        state   <= S_FIN;
                    end else begin
                        elem_cnt <= elem_cnt + 32'd1;
                    end
                end

                S_FIN: begin
                    op_busy <= 1'b0;
                    done_r  <= 1'b1;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
