/*
 * Simple SDR SDRAM controller for 4Mx16x4 devices, e.g. ISSI IS45S16160G
 * (32MB).
 */
module sdram_controller(input wire clk,
			input wire cs,
			/* Host interface. */
			input wire [31:2] h_addr,
			input wire [31:0] h_wdata,
			output reg [31:0] h_rdata,
			input wire h_wr_en,
			input wire [3:0] h_bytesel,
			output reg h_compl,
			output reg h_config_done,
			/* SDRAM signals. */
			output wire s_ras_n,
			output wire s_cas_n,
			output wire s_wr_en,
			output wire [1:0] s_bytesel,
			output reg [12:0] s_addr,
			output wire s_cs_n,
			output reg s_clken,
			inout [15:0] s_data,
			output reg [1:0] s_banksel);

parameter clkf			= 50000000;

localparam ns_per_clk		= (1000000000 / clkf);
localparam tReset		= 100000 / ns_per_clk;
localparam tRC			= 8;
localparam tRP			= 2;
localparam tMRD			= 2;
localparam tRCD			= 2;
localparam tDPL			= 2;
localparam cas			= 2;
/*
 * From idle, what is the longest path to get back to idle (excluding
 * autorefresh)?  We need to know this to make sure that we issue the
 * autorefresh command often enough.
 *
 * tRef of 64ms for normal temperatures (< 85C).
 *
 * Need to refresh 8192 times every tRef.
 */
localparam tRef			= ((64 * 1000000) / ns_per_clk) / 8192;
localparam max_cmd_period	= tRCD + tRP + tDPL + 1;

/* Command truth table: CS  RAS  CAS  WE. */
localparam CMD_NOP		= 4'b0111;
localparam CMD_BST		= 4'b0110;
localparam CMD_READ		= 4'b0101;
localparam CMD_WRITE		= 4'b0100;
localparam CMD_ACT		= 4'b0011;
localparam CMD_PRE		= 4'b0010;
localparam CMD_REF		= 4'b0001;
localparam CMD_MRS		= 4'b0000;

localparam STATE_RESET		= 4'b0000;
localparam STATE_RESET_PCH	= 4'b0001;
localparam STATE_RESET_REF1	= 4'b0011;
localparam STATE_RESET_REF2	= 4'b0010;
localparam STATE_MRS		= 4'b0110;
localparam STATE_IDLE		= 4'b0111;
localparam STATE_ACT		= 4'b0101;
localparam STATE_READ		= 4'b1101;
localparam STATE_WRITE		= 4'b1001;
localparam STATE_PCH		= 4'b1000;
localparam STATE_AUTOREF	= 4'b1010;

reg [3:0] state			= STATE_RESET;
reg [3:0] next_state		= STATE_RESET;

reg [3:0] cmd			= CMD_NOP;

reg [31:0] latched_addr		= 32'b0;
reg [31:0] latched_wdata	= 32'b0;
reg latched_wr_en		= 1'b0;
reg [3:0] latched_bytesel	= 4'b0;

reg [15:0] outdata		= 16'b0;
reg [1:0] outbytesel		= 2'b0;

assign s_cs_n			= cmd[3];
assign s_ras_n			= cmd[2];
assign s_cas_n			= cmd[1];
assign s_wr_en			= cmd[0];
assign s_data			= state == STATE_WRITE && timec < 2'd2 ? outdata : {16{1'bz}};
assign s_bytesel		= outbytesel;

/*
 * We support 4 banks of 8MB each, rather than interleaving one bank follows
 * the next.  We ignore the LSB of the address - unaligned accesses are not
 * supported and are undefined.
 */
wire [1:0] latched_banksel	= latched_addr[24:23];
wire [8:0] latched_colsel	= latched_addr[9:1];

wire [1:0] h_banksel		= h_addr[24:23];
wire [12:0] h_rowsel		= h_addr[22:10];

initial begin
	s_clken			= 1'b1;
	s_addr			= 13'b0;
	s_banksel		= 2'b00;
	h_rdata			= 32'b0;
	h_compl			= 1'b0;
	h_config_done		= 1'b0;
end

/*
 * State machine counter.  Counts every cycle, resets on change of state
 * - once we reach one of the timing parameters we can transition again.  On
 * count 0 we emit the command, after that it's NOP's all the way.
 */
localparam timec_width = $clog2(tReset);
wire [timec_width - 1:0] timec;

counter		#(.count_width(timec_width),
		  .count_max(tReset))
		timec_counter(.clk(clk),
			      .count(timec),
			      .reset(state != next_state));

/*
 * Make sure that we refresh the correct number of times per refresh period
 * and have sufficient time to complete any transaction in progress.
 */
localparam refresh_counter_width = $clog2(tRef);
wire [refresh_counter_width - 1:0] refresh_count;
wire autorefresh_counter_clr = state == STATE_AUTOREF && timec == tRC - 1;
counter		#(.count_width(refresh_counter_width),
		  .count_max(tRef - max_cmd_period))
		refresh_counter(.clk(clk),
				.count(refresh_count),
				.reset(autorefresh_counter_clr));
wire autorefresh_pending = refresh_count == tRef[refresh_counter_width - 1:0] - max_cmd_period;

always @(*) begin
	next_state = state;
	case (state)
	STATE_RESET: begin
		if (timec == tReset[timec_width - 1:0] - 1)
			next_state = STATE_RESET_PCH;
	end
	STATE_RESET_PCH: begin
		if (timec == tRP - 1)
			next_state = STATE_RESET_REF1;
	end
	STATE_RESET_REF1: begin
		if (timec == tRC - 1)
			next_state = STATE_RESET_REF2;
	end
	STATE_RESET_REF2: begin
		if (timec == tRC - 1)
			next_state = STATE_MRS;
	end
	STATE_MRS: begin
		if (timec == tMRD - 1)
			next_state = STATE_IDLE;
	end
	STATE_IDLE: begin
		/*
		 * If we have a refresh pending then make sure we handle that
		 * first!
		 */
		if (!h_compl && autorefresh_pending)
			next_state = STATE_AUTOREF;
		else if (!h_compl && cs)
			next_state = STATE_ACT;
	end
	STATE_ACT: begin
		if (timec == tRCD - 1)
			next_state = latched_wr_en ? STATE_WRITE : STATE_READ;
	end
	STATE_WRITE: begin
		/* 2 bursts. */
		if (timec == tRP + tDPL + 1'b1)
			next_state = STATE_IDLE;
	end
	STATE_READ: begin
		/* 2 bursts. */
		if (timec == cas + 1'b1)
			next_state = STATE_IDLE;
	end
	STATE_AUTOREF: begin
		if (timec == tRC - 1)
			next_state = STATE_IDLE;
	end
	default: begin
		next_state = STATE_IDLE;
	end
	endcase
end

always @(posedge clk) begin
	cmd <= CMD_NOP;
	s_addr <= 13'b0;
	s_banksel <= 2'b00;

	if (state != next_state) begin
		case (next_state)
		STATE_RESET_PCH: begin
			cmd <= CMD_PRE;
			s_addr <= 13'b10000000000;
			s_banksel <= 2'b11;
		end
		STATE_RESET_REF1: begin
			cmd <= CMD_REF;
		end
		STATE_RESET_REF2: begin
			cmd <= CMD_REF;
		end
		STATE_MRS: begin
			cmd <= CMD_MRS;
			s_banksel <= 2'b00;
			/* Burst length 2, CAS 2. */
			s_addr <= 13'b0000100001;
		end
		STATE_ACT: begin
			cmd <= CMD_ACT;
			s_banksel <= h_banksel;
			s_addr <= h_rowsel;
		end
		STATE_WRITE: begin
			cmd <= CMD_WRITE;
			/* Write with autoprecharge. */
			s_addr <= {2'b00, 1'b1, 1'b0, latched_colsel};
			s_banksel <= latched_banksel;
		end
		STATE_READ: begin
			cmd <= CMD_READ;
			/* Read with autoprecharge. */
			s_addr <= {2'b00, 1'b1, 1'b0, latched_colsel};
			s_banksel <= latched_banksel;
		end
		STATE_AUTOREF: begin
			cmd <= CMD_REF;
		end
		endcase
	end
end

always @(posedge clk) begin
	if (state == STATE_IDLE)
		h_rdata <= 32'h0;

	if (state == STATE_READ) begin
		if (timec == cas)
			h_rdata[15:0] <= s_data;
		if (timec == cas + 1'b1)
			h_rdata[31:16] <= s_data;
	end
end

always @(posedge clk) begin
	h_compl <= 1'b0;

	if ((state == STATE_READ && timec == cas + 1'b1) ||
	    (state == STATE_WRITE && timec == tRP + tDPL + 1'b1) ||
	    (state == STATE_MRS && timec == tMRD - 1))
		h_compl <= 1'b1;
end

always @(posedge clk) begin
	if (state == STATE_IDLE) begin
		outdata <= h_wdata[15:0];
		outbytesel <= h_wr_en ? ~h_bytesel[1:0] : 2'b00;
	end

	if (state == STATE_WRITE) begin
		if (timec == 0) begin
			outdata <= latched_wdata[31:16];
			outbytesel <= ~latched_bytesel[3:2];
		end
	end
end

always @(posedge clk) begin
	if (state == STATE_IDLE) begin
		h_config_done <= 1'b1;

		if (cs) begin
			latched_addr <= {h_addr, 2'b00};
			latched_wdata <= h_wdata;
			latched_wr_en <= h_wr_en;
			latched_bytesel <= h_bytesel;
		end
	end
end

always @(posedge clk)
	state <= next_state;

endmodule
