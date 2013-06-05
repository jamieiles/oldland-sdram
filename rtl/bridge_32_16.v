/*
 * 32-bit to 16-bit bridge.
 *
 * Converts 32 bit read/write accesses into 2 16-bit read/write accesses.
 *
 * bytesel != 4'b0000 starts a transfer, the transfer has completed when
 * h_compl goes high.
 */
module bridge_32_16(input wire clk,
		    /* Host side interfaces. */
		    input wire h_cs,
		    input wire [31:0] h_addr,
		    input wire [31:0] h_wdata,
		    output reg [31:0] h_rdata,
		    input wire h_wr_en,
		    input wire [3:0] h_bytesel,
		    output reg h_compl,
		    /* 16-bit bridge interfaces. */
		    output reg [31:0] b_addr,
		    output reg [15:0] b_wdata,
		    input wire [15:0] b_rdata,
		    output reg b_wr_en,
		    output reg [1:0] b_bytesel,
		    input wire b_compl);

initial begin
	h_rdata			= 32'b0;
	h_compl			= 1'b0;
	b_addr			= 32'b0;
	b_wdata			= 16'b0;
	b_bytesel		= 2'b00;
	b_wr_en			= 1'b0;
end

localparam STATE_IDLE		= 2'b00;
localparam STATE_HWORD1		= 2'b01;
localparam STATE_HWORD2		= 2'b11;
localparam STATE_COMPL		= 2'b10;

reg [1:0] state			= STATE_IDLE;
reg [1:0] next_state		= STATE_IDLE;

always @(*) begin
	next_state = state;

	case (state)
	STATE_IDLE: begin
		if (h_cs && |h_bytesel)
			next_state = |h_bytesel[1:0] ? STATE_HWORD1 :
				STATE_HWORD2;
	end
	STATE_HWORD1: begin
		if (b_compl)
			next_state = |h_bytesel[3:2] ? STATE_HWORD2 :
				STATE_COMPL;
	end
	STATE_HWORD2: begin
		if (b_compl)
			next_state = STATE_COMPL;
	end
	STATE_COMPL: begin
		next_state = STATE_IDLE;
	end
	endcase
end

always @(*) begin
	case (state)
	STATE_IDLE: begin
		b_bytesel = 2'b00;
	end
	STATE_HWORD1: begin
		b_addr = {h_addr[31:2], 2'b00};
		b_bytesel = b_compl ? 2'b00 : h_bytesel[1:0];
		b_wdata = h_wdata[15:0];
	end
	STATE_HWORD2: begin
		b_addr = {h_addr[31:2], 2'b10};
		b_bytesel = b_compl ? 2'b00 : h_bytesel[3:2];
		b_wdata = h_wdata[31:16];
	end
	default: begin
	end
	endcase
end

/*
 * Register the 16-bit data into the 32-bit read port.
 */
always @(posedge clk) begin
	h_compl <= 1'b0;

	case (state)
	STATE_IDLE: begin
		h_rdata <= 32'b0;
		if (h_cs && |h_bytesel)
			b_wr_en <= h_wr_en;
	end
	STATE_HWORD1: begin
		if (b_compl && !h_wr_en) begin
			h_rdata[15:0] <= b_rdata;
			if (~|h_bytesel[3:2])
				h_compl <= 1'b1;
		end
	end
	STATE_HWORD2: begin
		if (b_compl && !h_wr_en) begin
			h_rdata[31:16] <= b_rdata;
			h_compl <= 1'b1;
		end
	end
	default: begin
	end
	endcase
end

always @(posedge clk)
	state <= next_state;

endmodule
